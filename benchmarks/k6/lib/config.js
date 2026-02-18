// Service endpoint configuration for k6 benchmarks

export const services = {
  'spring-uninstrumented': {
    port: 8082,
    profile: 'spring-uninstrumented',
  },
  'spring-auto': {
    port: 8080,
    profile: 'spring-auto',
  },
  'spring-manual': {
    port: 8081,
    profile: 'spring-manual',
  },
  'express-uninstrumented': {
    port: 3002,
    profile: 'express-uninstrumented',
  },
  'express-auto': {
    port: 3000,
    profile: 'express-auto',
  },
  'express-manual': {
    port: 3001,
    profile: 'express-manual',
  },
};

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
