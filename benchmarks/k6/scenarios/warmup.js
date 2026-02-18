import http from 'k6/http';
import { check, sleep } from 'k6';
import { getServiceUrl, testSong, buildSongEndpoint } from '../lib/config.js';

// Warmup scenario - 120 seconds at 10 VUs
// Purpose: Stabilize JVM JIT compilation before measurement
export const options = {
  scenarios: {
    warmup: {
      executor: 'constant-vus',
      vus: 10,
      duration: '120s',
    },
  },
  // No thresholds during warmup - just stabilization
};

export default function() {
  const baseUrl = getServiceUrl();
  const endpoint = buildSongEndpoint(baseUrl, testSong.title, testSong.artist);

  const response = http.get(endpoint);

  check(response, {
    'status is 200': (r) => r.status === 200,
    'response has body': (r) => r.body && r.body.length > 0,
  });

  // 100ms think time between requests
  sleep(0.1);
}
