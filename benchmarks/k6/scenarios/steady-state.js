import http from 'k6/http';
import { check, sleep } from 'k6';
import { getServiceUrl, testSong, buildSongEndpoint } from '../lib/config.js';

// Steady-state scenario - 300 seconds at 50 VUs
// Purpose: Measure baseline instrumentation overhead with cached data
export const options = {
  scenarios: {
    steady_state: {
      executor: 'constant-vus',
      vus: 50,
      duration: '300s',
    },
  },
  thresholds: {
    // Less than 1% request failures
    'http_req_failed': ['rate<0.01'],
    // P95 latency under 2 seconds
    'http_req_duration': ['p(95)<2000'],
  },
};

export default function() {
  const baseUrl = getServiceUrl();
  const endpoint = buildSongEndpoint(baseUrl, testSong.title, testSong.artist);

  const response = http.get(endpoint);

  check(response, {
    'status is 200': (r) => r.status === 200,
    'response has body': (r) => r.body && r.body.length > 0,
    'response is JSON': (r) => {
      try {
        JSON.parse(r.body);
        return true;
      } catch (e) {
        return false;
      }
    },
  });

  // 100ms think time between requests
  sleep(0.1);
}
