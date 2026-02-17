package com.slct.demo;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface SongRepository extends JpaRepository<Song, Long> {
    String FIND_BY_TITLE_AND_ARTIST_QUERY = "SELECT s FROM Song s WHERE LOWER(s.title) = LOWER(:title) AND LOWER(s.artist) = LOWER(:artist)";

    @Query(FIND_BY_TITLE_AND_ARTIST_QUERY)
    Optional<Song> findByTitleAndArtistIgnoreCase(@Param("title") String title, @Param("artist") String artist);    
} 
