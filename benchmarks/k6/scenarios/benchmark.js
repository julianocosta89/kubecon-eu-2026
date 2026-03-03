import http from 'k6/http';
import { check } from 'k6';
import { getServiceUrl, testSong, buildSongEndpoint } from '../lib/config.js';

// Configurable via environment variables
const RATE = parseInt(__ENV.RATE || '400');         // requests/second
const STEADY_STATE_DURATION = __ENV.STEADY_STATE_DURATION || '800s';

export const options = {
  scenarios: {
    // Steady-state: fixed arrival rate so both services receive equal pressure.
    // With constant-vus, a slower service naturally generates fewer requests,
    // making it impossible to compare overhead at equivalent load.
    // Warmup is handled by a separate k6 invocation (warmup.js).
    steady_state: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: STEADY_STATE_DURATION,
      preAllocatedVUs: 50,
      maxVUs: 100,
    },
  },
  thresholds: {
    'http_req_failed{scenario:steady_state}': ['rate<0.01'],
    'http_req_duration{scenario:steady_state}': ['p(95)<2000'],
  },
};

export default function () {
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
  // No sleep: constant-arrival-rate manages its own pacing.
}

export function handleSummary(data) {
  const serviceName = __ENV.SERVICE_NAME || 'unknown';
  const summaryFile = __ENV.SUMMARY_FILE;

  // Prefer scenario-tagged metrics (tracked via thresholds) for steady-state accuracy.
  // Falls back to aggregate if not available.
  const durationMetric =
    data.metrics['http_req_duration{scenario:steady_state}'] ||
    data.metrics.http_req_duration;

  const failureMetric =
    data.metrics['http_req_failed{scenario:steady_state}'] ||
    data.metrics.http_req_failed;

  const summary = {
    service: serviceName,
    timestamp: new Date().toISOString(),
    rate_rps: RATE,
    p95_ms: durationMetric?.values['p(95)'],
    avg_ms: durationMetric?.values.avg,
    failure_rate: failureMetric?.values.rate,
  };

  const result = {
    stdout: JSON.stringify(summary, null, 2) + '\n',
  };

  if (summaryFile) {
    result[summaryFile] = JSON.stringify(summary, null, 2);
  }

  return result;
}
