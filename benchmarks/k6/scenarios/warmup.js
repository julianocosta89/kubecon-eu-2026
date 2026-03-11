import http from 'k6/http';
import { check } from 'k6';
import { getServiceUrl, testSong, buildSongEndpoint } from '../lib/config.js';

// Match steady-state rate so the service reaches thermal equilibrium at the exact
// load it will face during measurement — avoids a 2000→400 RPS transition artifact.
const RATE = parseInt(__ENV.RATE || '400');
const WARMUP_DURATION = __ENV.WARMUP_DURATION || '120s';

export const options = {
  scenarios: {
    warmup: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: WARMUP_DURATION,
      preAllocatedVUs: 50,
      maxVUs: 200,
    },
  },
};

export default function () {
  const baseUrl = getServiceUrl();
  const endpoint = buildSongEndpoint(baseUrl, testSong.title, testSong.artist);

  const response = http.get(endpoint);

  check(response, {
    'status is 200': (r) => r.status === 200,
  });
}
