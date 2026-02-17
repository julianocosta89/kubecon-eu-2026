package com.slct.demo;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

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
            return songRepository.save(song);
        } catch (Exception e) {
            throw new RuntimeException("Error saving song: " + e.getMessage(), e);
        }
    }
}
