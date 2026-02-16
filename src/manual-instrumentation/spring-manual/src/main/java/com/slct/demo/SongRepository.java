package com.slct.demo;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface SongRepository extends JpaRepository<Song, Long> {
    
    @Query("SELECT s FROM Song s WHERE LOWER(s.title) = LOWER(:title) AND LOWER(s.artist) = LOWER(:artist)")
    Optional<Song> findByTitleAndArtistIgnoreCase(@Param("title") String title, @Param("artist") String artist);
    
} 
