const express = require('express')
const { Pool } = require('pg')
const helmet = require('helmet')
const pino = require('pino')
const app = express()
const port = 3000

app.use(helmet())
app.disable('x-powered-by')

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport: {
    target: 'pino-opentelemetry-transport'
  }
})

// Validate required environment variables
const requiredEnvVars = ['DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASSWORD']
const missingEnvVars = requiredEnvVars.filter(envVar => !process.env[envVar])

if (missingEnvVars.length > 0) {
  logger.error({ missingEnvVars }, 'Missing required environment variables')
  process.exit(1)
}

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

  let client
  try {
    // Get a client from the pool (connection happens automatically)
    client = await pool.connect()
    
    // Query to get song metadata for the title and artist
    const query = `
      SELECT title, artist, album, year, duration_ms, genre
      FROM songs 
      WHERE title ILIKE $1 AND artist ILIKE $2
    `
    
    const result = await client.query(query, [title, artist])
    
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
      const songData = await getSongFromMusicBrainz(title, artist)
      if (songData) {
        await persistSong(title, artist, songData)

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
  } catch (error) {
    logger.error({ error }, 'Database query error')
    res.status(500).json({
      error: 'Database error',
      message: error.message
    })
  } finally {
    if (client) {
      client.release()
    }
  }
})

async function getSongFromMusicBrainz(title, artist) {
  try {
    const url = `https://musicbrainz.org/ws/2/recording/?query=recording:"${title}" AND artist:"${artist}"&fmt=json&limit=20`
    const response = await fetch(url, {
      headers: { 'User-Agent': 'otel-demo/1.0' }
    })
    const data = await response.json()
    
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

async function persistSong(title, artist, songData) {
  const query = `
    INSERT INTO songs (title, artist, album, year, duration_ms, genre)
    VALUES ($1, $2, $3, $4, $5, $6)
    ON CONFLICT (title, artist) DO NOTHING
  `
  await pool.query(query, [title, artist, songData.album, songData.year, songData.duration_ms, songData.genre])
}

app.listen(port, () => {
  logger.info({ port }, 'Music service listening')
})

// Graceful shutdown
process.on('SIGINT', () => {
  pool.end()
  process.exit(0)
})
