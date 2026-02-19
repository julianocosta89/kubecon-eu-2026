import http from 'k6/http';
import { check, sleep } from 'k6';
import exec from 'k6/execution';
import { getServiceUrl, testSong, buildSongEndpoint } from '../lib/config.js';

// Configurable via environment variables
const WARMUP_VUS = parseInt(__ENV.WARMUP_VUS || '10');
const WARMUP_DURATION = __ENV.WARMUP_DURATION || '120s';
const RATE = parseInt(__ENV.RATE || '200');         // requests/second
const STEADY_STATE_DURATION = __ENV.STEADY_STATE_DURATION || '300s';

export const options = {
  scenarios: {
    // Warmup: constant VUs to stabilize JVM JIT / Node.js runtime
    warmup: {
      executor: 'constant-vus',
      vus: WARMUP_VUS,
      duration: WARMUP_DURATION,
    },
    // Steady-state: fixed arrival rate so both services receive equal pressure.
    // With constant-vus, a slower service naturally generates fewer requests,
    // making it impossible to compare overhead at equivalent load.
    steady_state: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: STEADY_STATE_DURATION,
      preAllocatedVUs: 50,
      maxVUs: 100,
      startTime: WARMUP_DURATION,
    },
  },
  thresholds: {
    // Scoped to steady_state only — warmup traffic is excluded
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

  // Think time during warmup only.
  // constant-arrival-rate manages its own pacing — adding sleep here
  // would cause k6 to spin up more VUs to compensate, skewing results.
  if (exec.scenario.name === 'warmup') {
    sleep(0.1);
  }
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
