package com.slct.demo;

import org.springframework.stereotype.Service;

import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.context.Scope;
import io.opentelemetry.semconv.DbAttributes;
import io.opentelemetry.api.common.Attributes;
import com.slct.demo.config.MediaContentAttributes;

@Service
public class SongService {

    // db.collection.name is the bare table name; the database name goes in db.namespace.
    // Span names follow the "{db.operation.name} {db.collection.name}" convention.
    private static final Attributes SELECT_BASE_ATTRS = Attributes.of(
        DbAttributes.DB_SYSTEM_NAME, DbAttributes.DbSystemNameValues.POSTGRESQL,
        DbAttributes.DB_OPERATION_NAME, "SELECT",
        DbAttributes.DB_COLLECTION_NAME, "songs",
        DbAttributes.DB_NAMESPACE, "songs_db",
        DbAttributes.DB_QUERY_TEXT, SongRepository.FIND_BY_TITLE_AND_ARTIST_QUERY
    );

    private static final Attributes INSERT_BASE_ATTRS = Attributes.of(
        DbAttributes.DB_SYSTEM_NAME, DbAttributes.DbSystemNameValues.POSTGRESQL,
        DbAttributes.DB_OPERATION_NAME, "INSERT",
        DbAttributes.DB_COLLECTION_NAME, "songs",
        DbAttributes.DB_NAMESPACE, "songs_db",
        DbAttributes.DB_QUERY_TEXT, "INSERT INTO songs (title, artist, album, year, duration_ms, genre) VALUES (?, ?, ?, ?, ?, ?)"
    );

    private final SongRepository songRepository;
    private final Tracer tracer;

    public SongService(SongRepository songRepository, Tracer tracer) {
        this.songRepository = songRepository;
        this.tracer = tracer;
    }

    public Song getSongFromDatabase(String title, String artist) {
        Span span = tracer.spanBuilder("SELECT songs")
                .setSpanKind(SpanKind.CLIENT)
                .setAllAttributes(SELECT_BASE_ATTRS)
                .setAttribute(MediaContentAttributes.ATTR_MEDIA_SONG_NAME, title)
                .setAttribute(MediaContentAttributes.ATTR_MEDIA_ARTIST_NAME, artist)
                .startSpan();

        try (Scope scope = span.makeCurrent()) {
            var song = songRepository.findByTitleAndArtistIgnoreCase(title, artist);

            if (song.isPresent()) {
                return song.get();
            } else {
                return null;
            }
        } catch (Exception e) {
            span.recordException(e);
            span.setStatus(StatusCode.ERROR);
            throw new RuntimeException("Database error: " + e.getMessage(), e);
        } finally {
            span.end();
        }
    }

    public Song saveSong(String title, String artist, String album, Integer year, Integer durationMs, String genre) {
        Span span = tracer.spanBuilder("INSERT songs")
                .setSpanKind(SpanKind.CLIENT)
                .setAllAttributes(INSERT_BASE_ATTRS)
                .setAttribute(MediaContentAttributes.ATTR_MEDIA_SONG_NAME, title)
                .setAttribute(MediaContentAttributes.ATTR_MEDIA_ARTIST_NAME, artist)
                .setAttribute(MediaContentAttributes.ATTR_MEDIA_ALBUM_NAME, album)
                .setAttribute(MediaContentAttributes.ATTR_MEDIA_SONG_GENRE, genre)
                .startSpan();

        if (year != null) {
            span.setAttribute(MediaContentAttributes.ATTR_MEDIA_SONG_YEAR, year.longValue());
        }
        if (durationMs != null) {
            span.setAttribute(MediaContentAttributes.ATTR_MEDIA_SONG_DURATION_MS, durationMs.longValue());
        }

        try (Scope scope = span.makeCurrent()) {
            Song song = new Song(title, artist, album, year, durationMs, genre);
            Song savedSong = songRepository.save(song);

            return savedSong;
        } catch (Exception e) {
            span.recordException(e);
            span.setStatus(StatusCode.ERROR);
            throw new RuntimeException("Error saving song: " + e.getMessage(), e);
        } finally {
            span.end();
        }
    }
}
