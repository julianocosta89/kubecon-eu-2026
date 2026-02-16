const express = require('express')
const { Pool } = require('pg')
const helmet = require('helmet')
const pino = require('pino')
const app = express()
const port = 3000

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
})

app.use(helmet())
app.disable('x-powered-by')

const opentelemetry = require('@opentelemetry/api')
const { 
  ATTR_HTTP_REQUEST_METHOD, 
  ATTR_HTTP_RESPONSE_STATUS_CODE,
  ATTR_HTTP_ROUTE,
  ATTR_SERVER_ADDRESS, 
  ATTR_SERVER_PORT, 
  ATTR_URL_FULL,
  ATTR_URL_PATH,
  ATTR_URL_SCHEME,
  ATTR_USER_AGENT_ORIGINAL,
  ATTR_DB_SYSTEM_NAME,
  ATTR_DB_OPERATION_NAME,
  DB_SYSTEM_NAME_VALUE_POSTGRESQL,
  HTTP_REQUEST_METHOD_VALUE_GET,
  ATTR_DB_QUERY_TEXT,
} = require('@opentelemetry/semantic-conventions')

const requiredEnvVars = ['DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASSWORD']
const missingEnvVars = requiredEnvVars.filter(envVar => !process.env[envVar])
if (missingEnvVars.length > 0) {
  logger.error({ missingEnvVars }, 'Missing required environment variables')
  process.exit(1)
}

const tracer = opentelemetry.trace.getTracer(
  'music-tracer',
  '1.0.0',
);

// PostgreSQL connection pool configuration
const pool = new Pool({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT, 10),
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 20, // Maximum number of clients in the pool
  idleTimeoutMillis: 30000, // Close idle clients after 30 seconds
  connectionTimeoutMillis: 2000, // Return an error after 2 seconds if connection could not be established
})

// Handle pool errors
pool.on('error', (err) => {
  logger.error({ err }, 'Unexpected error on idle client')
  process.exit(-1)
})

app.get('/songs/:title/:artist', async (req, res) => {
  const title = req.params.title
  const artist = req.params.artist
  const host = req.headers['host']

  // Extract trace context from incoming headers
  const activeContext = opentelemetry.propagation.extract(opentelemetry.context.active(), req.headers)

  const span = tracer.startSpan('GET /songs/:title/:artist', {
    kind: 1, // server
    attributes: {
      [ATTR_HTTP_REQUEST_METHOD]: HTTP_REQUEST_METHOD_VALUE_GET,
      [ATTR_HTTP_ROUTE]: '/songs/:title/:artist',
      [ATTR_SERVER_ADDRESS]: host,
      [ATTR_SERVER_PORT]: host.split(':')[1],
      [ATTR_URL_FULL]: `http://${host}/songs/${title}/${artist}`,
      [ATTR_URL_PATH]: `/songs/${title}/${artist}`,
      [ATTR_URL_SCHEME]: req.query.scheme,
      [ATTR_USER_AGENT_ORIGINAL]: req.headers['user-agent'],
    },
  }, activeContext)

  let client
  try {
    const query = `
      SELECT title, artist, album, year, duration_ms, genre
      FROM songs 
      WHERE title ILIKE $1 AND artist ILIKE $2
    `

    const dbSpan = tracer.startSpan('SELECT songs_db.songs', {
      kind: 2, // client
      attributes: {
        [ATTR_DB_SYSTEM_NAME]: [DB_SYSTEM_NAME_VALUE_POSTGRESQL],
        [ATTR_DB_QUERY_TEXT]: query,
        [ATTR_DB_OPERATION_NAME]: 'SELECT',
      },
    }, opentelemetry.trace.setSpan(opentelemetry.context.active(), span))

    client = await pool.connect()  
    
    const result = await client.query(query, [title, artist])

    dbSpan.end()
    if (result.rows.length > 0) {
      const song = result.rows[0]
      res.json({
        title: song.title,
        artist: song.artist,
        album: song.album,
        year: song.year,
        duration_ms: song.duration_ms,
        genre: song.genre
      })
    } else {
      const songData = await getSongFromMusicBrainz(title, artist, span)
      if (songData) {
        persistSong(title, artist, songData, span)

        res.json({
          title: songData.title,
          artist: songData.artist,
          album: songData.album,
          year: songData.year,
          duration_ms: songData.duration_ms,
          genre: songData.genre
        })
      } else {
        res.status(404).json({
          error: 'Song not found',
          title: title,
          artist: artist
        })
      }
    }

    span.setAttributes({
      [ATTR_HTTP_RESPONSE_STATUS_CODE]: 200
    })

  } catch (error) {
    logger.error({ error }, 'Database query error')
    res.status(500).json({
      error: 'Database error',
      message: error.message
    })
  } finally {
    span.end()

    if (client) {
      client.release()
    }
  }
})

async function getSongFromMusicBrainz(title, artist, parentSpan) {
  const musicServiceUrl = process.env.MUSIC_SERVICE_URL || 'https://musicbrainz.org/ws/2/recording'
  const query = encodeURIComponent(`recording:"${title}" AND artist:"${artist}"`)
  const url = `${musicServiceUrl}?query=${query}&fmt=json&limit=20`
  
  const span = tracer.startSpan('GET', {
      kind: 2, // client
      attributes: {
        [ATTR_HTTP_REQUEST_METHOD]: HTTP_REQUEST_METHOD_VALUE_GET,
        [ATTR_URL_FULL]: url,
        [ATTR_URL_PATH]: `/?query=${query}&fmt=json&limit=20`,
        [ATTR_URL_SCHEME]: 'https',
      },
    }, opentelemetry.trace.setSpan(opentelemetry.context.active(), parentSpan))
  
  try {
    const response = await fetch(url, {
      headers: { 'User-Agent': 'otel-demo/1.0' }
    })
    const data = await response.json()

    span.setAttributes({
      [ATTR_HTTP_RESPONSE_STATUS_CODE]: response.status,
    })
    span.end()
    
    if (!data.recordings || data.recordings.length === 0) {
      return null
    }
    
    // Find the recording with the oldest available year (any year is better than null)
    let bestRecording = null
    let oldestYear = null
    
    for (const recording of data.recordings) {
      const releases = recording.releases || []
      if (releases.length === 0) continue
      
      // Find the earliest year from any release in this recording
      let earliestYear = null
      
      for (const release of releases) {
        if (release.date) {
          const releaseYear = extractYear(release.date)
          if (releaseYear && (!earliestYear || releaseYear < earliestYear)) {
            earliestYear = releaseYear
          }
        }
      }
      
      // Update if this recording has an earlier year than our current best
      if (earliestYear && (!oldestYear || earliestYear < oldestYear)) {
        oldestYear = earliestYear
        bestRecording = recording
      }
    }
    
    if (!bestRecording) {
      bestRecording = data.recordings[0]
    }
    
    // Extract song data from the best recording - find the release with oldest year
    const releases = bestRecording.releases || []
    let bestRelease = null
    let bestReleaseYear = null
    
    for (const release of releases) {
      if (release.date) {
        const releaseYear = extractYear(release.date)
        if (releaseYear && (!bestReleaseYear || releaseYear < bestReleaseYear)) {
          bestReleaseYear = releaseYear
          bestRelease = release
        }
      }
    }
    
    const targetRelease = bestRelease || (releases.length > 0 ? releases[0] : null)
    
    // Try to get genre from tags - search all recordings if needed
    let genre = 'Unknown'
    if (bestRecording.tags && bestRecording.tags.length > 0) {
      genre = bestRecording.tags[0].name
    } else {
      // Look through all recordings for tags
      for (const recording of data.recordings) {
        if (recording.tags && recording.tags.length > 0) {
          genre = recording.tags[0].name
          break
        }
      }
    }
    
    return {
      title: title,
      artist: artist,
      album: targetRelease ? targetRelease.title || 'Unknown' : 'Unknown',
      year: targetRelease?.date ? extractYear(targetRelease.date) : null,
      duration_ms: bestRecording.length || null,
      genre: genre
    }
  } catch (error) {
    logger.error({ error }, 'Error fetching from MusicBrainz')
    span.setAttributes({
      [ATTR_HTTP_RESPONSE_STATUS_CODE]: 500,
    })
    span.end()
    return null
  }
}

function extractYear(dateString) {
  if (!dateString || typeof dateString !== 'string') {
    return null
  }
  
  try {
    // Handle various date formats: YYYY, YYYY-MM, YYYY-MM-DD
    const parts = dateString.split('-')
    if (parts.length > 0 && parts[0].length === 4) {
      return parseInt(parts[0], 10)
    }
  } catch (error) {
    logger.debug({ dateString }, 'Could not parse year from date string')
  }
  
  return null
}

async function persistSong(title, artist, songData, parentSpan) {
  const query = `
    INSERT INTO songs (title, artist, album, year, duration_ms, genre)
    VALUES ($1, $2, $3, $4, $5, $6)
    ON CONFLICT (title, artist) DO NOTHING
  `

  const dbSpan = tracer.startSpan('INSERT songs_db.songs', {
      kind: 2, // client
      attributes: {
        [ATTR_DB_SYSTEM_NAME]: [DB_SYSTEM_NAME_VALUE_POSTGRESQL],
        [ATTR_DB_QUERY_TEXT]: query,
        [ATTR_DB_OPERATION_NAME]: 'INSERT',
      },
    }, opentelemetry.trace.setSpan(opentelemetry.context.active(), parentSpan))

  await pool.query(query, [title, artist, songData.album, songData.year, songData.duration_ms, songData.genre])
  dbSpan.end()
}

app.listen(port, () => {
  logger.info({ port }, 'Music service listening')
})

// Graceful shutdown
process.on('SIGINT', () => {
  pool.end()
  process.exit(0)
})