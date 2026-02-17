package com.slct.demo;

import jakarta.persistence.*;

@Entity
@Table(name = "songs")
public class Song {
    
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(name = "title", nullable = false)
    private String title;
    
    @Column(name = "artist", nullable = false)
    private String artist;
    
    @Column(name = "album")
    private String album;
    
    @Column(name = "year")
    private Integer year;
    
    @Column(name = "duration_ms")
    private Integer durationMs;
    
    @Column(name = "genre")
    private String genre;
    
    // Default constructor
    public Song() {}
    
    // Constructor with parameters
    public Song(String title, String artist, String album, Integer year, Integer durationMs, String genre) {
        this.title = title;
        this.artist = artist;
        this.album = album;
        this.year = year;
        this.durationMs = durationMs;
        this.genre = genre;
    }
    
    // Getters and Setters
    public Long getId() {
        return id;
    }
    
    public void setId(Long id) {
        this.id = id;
    }
    
    public String getTitle() {
        return title;
    }
    
    public void setTitle(String title) {
        this.title = title;
    }
    
    public String getArtist() {
        return artist;
    }
    
    public void setArtist(String artist) {
        this.artist = artist;
    }
    
    public String getAlbum() {
        return album;
    }
    
    public void setAlbum(String album) {
        this.album = album;
    }
    
    public Integer getYear() {
        return year;
    }
    
    public void setYear(Integer year) {
        this.year = year;
    }
    
    public Integer getDurationMs() {
        return durationMs;
    }
    
    public void setDurationMs(Integer durationMs) {
        this.durationMs = durationMs;
    }
    
    public String getGenre() {
        return genre;
    }
    
    public void setGenre(String genre) {
        this.genre = genre;
    }
    
    @Override
    public String toString() {
        return String.format("Song{title='%s', artist='%s', album='%s', year=%s, durationMs=%s, genre='%s'}", 
                           title, artist, album, year, durationMs, genre);
    }
}
