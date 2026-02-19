package com.slct.demo;

import org.springframework.stereotype.Service;

import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.context.Scope;
import io.opentelemetry.semconv.DbAttributes;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;

@Service
public class SongService {

    private static final AttributeKey<String> SONG_TITLE_KEY = AttributeKey.stringKey("song.title");
    private static final AttributeKey<String> SONG_ARTIST_KEY = AttributeKey.stringKey("song.artist");

    private final SongRepository songRepository;
    private final Tracer tracer;

    public SongService(SongRepository songRepository, Tracer tracer) {
        this.songRepository = songRepository;
        this.tracer = tracer;
    }

    public Song getSongFromDatabase(String title, String artist) {
        // Create database client span - span name should be the operation name
        Span span = tracer.spanBuilder("SELECT songs_db.songs")
                .setSpanKind(SpanKind.CLIENT)
                .setAllAttributes(Attributes.of(
                    DbAttributes.DB_SYSTEM_NAME, DbAttributes.DbSystemNameValues.POSTGRESQL,
                    DbAttributes.DB_OPERATION_NAME, "SELECT",
                    DbAttributes.DB_COLLECTION_NAME, "songs_db.songs",
                    DbAttributes.DB_QUERY_TEXT, SongRepository.FIND_BY_TITLE_AND_ARTIST_QUERY,
                    SONG_TITLE_KEY, title,
                    SONG_ARTIST_KEY, artist
                ))
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
        // Create database client span - span name should be the operation name
        Span span = tracer.spanBuilder("INSERT into songs_db.songs")
                .setSpanKind(SpanKind.CLIENT)
                .setAllAttributes(Attributes.of(
                    DbAttributes.DB_SYSTEM_NAME, DbAttributes.DbSystemNameValues.POSTGRESQL,
                    DbAttributes.DB_OPERATION_NAME, "INSERT",
                    DbAttributes.DB_QUERY_TEXT, "INSERT INTO songs_db.songs (title, artist, album, year, duration_ms, genre) VALUES (?, ?, ?, ?, ?, ?)",
                    DbAttributes.DB_COLLECTION_NAME, "songs_db.songs",
                    SONG_TITLE_KEY, title,
                    SONG_ARTIST_KEY, artist
                ))
                .startSpan();

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
