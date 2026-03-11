// Test data - single song for consistent benchmarking
export const testSong = {
  title: 'Polly',
  artist: 'Nirvana',
};

// Build endpoint URL from environment variable or default
export function getServiceUrl() {
  return __ENV.SERVICE_URL || 'http://localhost:8080';
}

export function buildSongEndpoint(baseUrl, title, artist) {
  return `${baseUrl}/songs/${encodeURIComponent(title)}/${encodeURIComponent(artist)}`;
}
