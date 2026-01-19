package com.slct.demo;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@RestController
public class SongController {

    @Autowired
    private SongService songService;
    
    @Value("${MUSIC_SERVICE_URL:https://musicbrainz.org/ws/2/recording/}")
    private String musicServiceUrl;
    
    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper objectMapper = new ObjectMapper();
    private static final Logger logger = LoggerFactory.getLogger(SongController.class);

    @GetMapping("/songs/{title}/{artist}")
    public String getSongs(@PathVariable String title, @PathVariable String artist) {        
        Song song = songService.getSongFromDatabase(title, artist);

        if (song != null) {
            return String.format("{\"title\":\"%s\",\"artist\":\"%s\",\"album\":\"%s\",\"year\":%s,\"duration_ms\":%s,\"genre\":\"%s\"}", 
                               song.getTitle(), song.getArtist(), song.getAlbum(), song.getYear(), song.getDurationMs(), song.getGenre());
        } else {
            try {
                String url = String.format("%s?query=recording:\"%s\" AND artist:\"%s\"&fmt=json&limit=20", 
                    musicServiceUrl, title, artist);
                HttpHeaders headers = new HttpHeaders();
                headers.set("User-Agent", "otel-demo/1.0");
                
                HttpEntity<String> entity = new HttpEntity<>(headers);
                ResponseEntity<String> response = restTemplate.exchange(url, HttpMethod.GET, entity, String.class);
                
                // Parse the JSON response and save to database
                try {
                    JsonNode jsonNode = objectMapper.readTree(response.getBody());
                    JsonNode recordings = jsonNode.get("recordings");
                    if (recordings != null && recordings.isArray() && recordings.size() > 0) {
                        
                        // Find the best recording - prioritize studio albums over live recordings
                        JsonNode bestRecording = null;
                        Integer bestYear = null;
                        boolean foundStudioAlbum = false;
                        
                        for (JsonNode recording : recordings) {
                            JsonNode releases = recording.get("releases");
                            if (releases != null && releases.isArray() && releases.size() > 0) {
                                
                                // Check if this recording has any official studio releases
                                boolean hasStudioRelease = false;
                                Integer earliestYear = null;
                                
                                for (JsonNode release : releases) {
                                    if (release.has("date")) {
                                        String releaseDate = release.get("date").asText();
                                        Integer releaseYear = extractYear(releaseDate);
                                        
                                        if (releaseYear != null) {
                                            // Check if this is likely a studio album (not live/compilation)
                                            String albumTitle = release.has("title") ? release.get("title").asText().toLowerCase() : "";
                                            boolean isLive = albumTitle.contains("live") || albumTitle.contains("concert") || 
                                                           albumTitle.contains("stage") || albumTitle.contains("tour") ||
                                                           releaseDate.matches(".*\\d{4}-\\d{2}-\\d{2}.*"); // Specific dates often indicate live shows
                                            
                                            if (!isLive) {
                                                hasStudioRelease = true;
                                            }
                                            
                                            if (earliestYear == null || releaseYear < earliestYear) {
                                                earliestYear = releaseYear;
                                            }
                                        }
                                    }
                                }
                                
                                // Prioritize studio releases, then earliest year
                                boolean shouldUpdate = false;
                                if (bestRecording == null) {
                                    shouldUpdate = true;
                                } else if (!foundStudioAlbum && hasStudioRelease) {
                                    shouldUpdate = true; // First studio release found
                                } else if (foundStudioAlbum == hasStudioRelease && earliestYear != null && 
                                          (bestYear == null || earliestYear < bestYear)) {
                                    shouldUpdate = true; // Same type but earlier year
                                }
                                
                                if (shouldUpdate && earliestYear != null) {
                                    bestYear = earliestYear;
                                    bestRecording = recording;
                                    foundStudioAlbum = hasStudioRelease;
                                }
                            }
                        }
                        
                        // If no recording with release date found, use the first one
                        JsonNode selectedRecording = bestRecording != null ? bestRecording : recordings.get(0);
                        
                        Integer durationMs = selectedRecording.has("length") ? selectedRecording.get("length").asInt() : null;
                        
                        // Try to get album and year from the best studio release
                        String album = "Unknown";
                        Integer year = null;
                        JsonNode releases = selectedRecording.get("releases");
                        if (releases != null && releases.isArray() && releases.size() > 0) {
                            // Find the best studio release for this recording
                            JsonNode bestRelease = null;
                            Integer bestReleaseYear = null;
                            boolean foundStudioRelease = false;
                            
                            for (JsonNode release : releases) {
                                if (release.has("date")) {
                                    String releaseDate = release.get("date").asText();
                                    Integer releaseYear = extractYear(releaseDate);
                                    String albumTitle = release.has("title") ? release.get("title").asText().toLowerCase() : "";
                                    
                                    boolean isLive = albumTitle.contains("live") || albumTitle.contains("concert") || 
                                                   albumTitle.contains("stage") || albumTitle.contains("tour") ||
                                                   releaseDate.matches(".*\\d{4}-\\d{2}-\\d{2}.*");
                                    
                                    boolean shouldUpdate = false;
                                    if (bestRelease == null) {
                                        shouldUpdate = true;
                                    } else if (!foundStudioRelease && !isLive) {
                                        shouldUpdate = true; // First studio release found
                                    } else if (foundStudioRelease == !isLive && releaseYear != null && 
                                              (bestReleaseYear == null || releaseYear < bestReleaseYear)) {
                                        shouldUpdate = true; // Same type but earlier year
                                    }
                                    
                                    if (shouldUpdate && releaseYear != null) {
                                        bestReleaseYear = releaseYear;
                                        bestRelease = release;
                                        foundStudioRelease = !isLive;
                                    }
                                }
                            }
                            
                            // Use the best release or first release if no dates found
                            JsonNode targetRelease = bestRelease != null ? bestRelease : releases.get(0);
                            
                            if (targetRelease.has("title")) {
                                album = targetRelease.get("title").asText();
                            }
                            if (targetRelease.has("date")) {
                                String date = targetRelease.get("date").asText();
                                year = extractYear(date);
                            }
                        }
                        
                        // Try to get genre from tags - search all recordings if needed
                        String genre = "Unknown";
                        JsonNode tags = selectedRecording.get("tags");
                        if (tags != null && tags.isArray() && tags.size() > 0) {
                            genre = tags.get(0).get("name").asText();
                        } else {
                            // Look through all recordings for tags
                            for (JsonNode recording : recordings) {
                                JsonNode recordingTags = recording.get("tags");
                                if (recordingTags != null && recordingTags.isArray() && recordingTags.size() > 0) {
                                    genre = recordingTags.get(0).get("name").asText();
                                    break;
                                }
                            }
                        }
                        
                        // Save to database
                        Song savedSong = songService.saveSong(title, artist, album, year, durationMs, genre);
                        
                        return String.format("{\"title\":\"%s\",\"artist\":\"%s\",\"album\":\"%s\",\"year\":%s,\"duration_ms\":%s,\"genre\":\"%s\"}", 
                                           savedSong.getTitle(), savedSong.getArtist(), savedSong.getAlbum(), savedSong.getYear(), savedSong.getDurationMs(), savedSong.getGenre());
                    } else {
                        return String.format("{\"message\":\"Song not found for title: %s, artist: %s\"}", 
                                           title, artist);
                    }
                } catch (Exception e) {
                    // Return basic song info even if saving fails
                    return String.format("{\"title\":\"%s\",\"artist\":\"%s\",\"album\":\"Unknown\",\"year\":null,\"duration_ms\":null,\"genre\":\"Unknown\"}", 
                                       title, artist);
                }
            } catch (Exception e) {
                return String.format("{\"error\":\"Song not found for title: %s, artist: %s, external service error: %s\"}", 
                                   title, artist, e.getMessage());
            }
        }
    }
    
    private Integer extractYear(String dateString) {
        if (dateString == null || dateString.trim().isEmpty()) {
            return null;
        }
        
        try {
            // Handle various date formats: YYYY, YYYY-MM, YYYY-MM-DD
            String[] parts = dateString.split("-");
            if (parts.length > 0 && parts[0].length() == 4) {
                return Integer.parseInt(parts[0]);
            }
        } catch (NumberFormatException e) {
            logger.debug("Could not parse year from date string: {}", dateString);
        }
        
        return null;
    }
}
