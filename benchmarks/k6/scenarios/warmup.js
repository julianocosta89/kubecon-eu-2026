import http from 'k6/http';
import { check, sleep } from 'k6';
import { getServiceUrl, testSong, buildSongEndpoint } from '../lib/config.js';

const WARMUP_VUS = parseInt(__ENV.WARMUP_VUS || '10');
const WARMUP_DURATION = __ENV.WARMUP_DURATION || '120s';

export const options = {
  scenarios: {
    warmup: {
      executor: 'constant-vus',
      vus: WARMUP_VUS,
      duration: WARMUP_DURATION,
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

  sleep(0.1);
}
