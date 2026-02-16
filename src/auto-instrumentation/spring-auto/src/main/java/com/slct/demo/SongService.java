package com.slct.demo;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.trace.Span;

@Service
public class SongService {
    
    @Autowired
    private SongRepository songRepository;
    
    public Song getSongFromDatabase(String title, String artist) {
        try {
            var song = songRepository.findByTitleAndArtistIgnoreCase(title, artist);
            
            if (song.isPresent()) {
                return song.get();
            } else {
                return null;
            }
        } catch (Exception e) {
            throw new RuntimeException("Database error: " + e.getMessage(), e);
        }
    }
    
    public Song saveSong(String title, String artist, String album, Integer year, Integer durationMs, String genre) {
        try {
            Song song = new Song(title, artist, album, year, durationMs, genre);

            Span span = Span.current();
            span.setAllAttributes(Attributes.builder()
                .put("media.song.name", title)
                .put("media.artist.name", artist)
                .put("media.album.name", album != null ? album : "Unknown")
                .put("media.song.year", year != null ? year : 0)
                .put("media.song.duration_ms", durationMs != null ? durationMs : 0)
                .put("media.song.genre", genre != null ? genre : "Unknown")
                .build());

            return songRepository.save(song);
        } catch (Exception e) {
            throw new RuntimeException("Error saving song: " + e.getMessage(), e);
        }
    }
}
