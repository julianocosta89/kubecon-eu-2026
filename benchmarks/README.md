# k6 Benchmarking Infrastructure

This directory contains load testing infrastructure to benchmark OpenTelemetry instrumentation overhead for the KubeCon EU 2026 talk "How manual OTel instrumentation saves more than just money".

## Overview

The benchmark suite quantifies CPU and memory differences between:
- **Uninstrumented** (baseline) - No OpenTelemetry dependencies
- **Auto-instrumented** - Java agent / Node.js auto-instrumentations
- **Manual-instrumented** - Selective SDK-based instrumentation

### Scope

All 6 service variants are benchmarked:

| Service | Uninstrumented | Auto | Manual |
|---------|---------------|------|--------|
| Spring  | ✅ port 8082  | ✅ port 8080 | ✅ port 8081 |
| Express | ✅ port 3002  | ✅ port 3000 | ✅ port 3001 |

## Prerequisites

### Required Tools

1. **k6** - Load testing tool
   ```bash
   # macOS
   brew install k6

   # Linux
   sudo gpg -k
   sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
   echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
   sudo apt-get update
   sudo apt-get install k6

   # Verify installation
   k6 version
   ```

2. **Docker Compose** - Container orchestration
   ```bash
   docker compose version
   ```

3. **Dash0 Account** - Metrics collection backend
   - Sign up at https://www.dash0.com/
   - Create an auth token under **Settings → Auth Tokens**
   - Find your region's OTLP gRPC endpoint under **Settings → Endpoints**

### Environment Configuration

1. **Set Dash0 credentials** in `.env` file (project root):
   ```bash
   OBSERVABILITY_BACKEND=dash0
   DASH0_ENDPOINT=ingress.eu-west-1.aws.dash0.com:4317  # your region's endpoint, without scheme
   DASH0_AUTHORIZATION_TOKEN=your_auth_token_here
   ```

2. **Verify configuration**:
   ```bash
   cat ../.env | grep -E "(OBSERVABILITY_BACKEND|DASH0_ENDPOINT|DASH0_AUTHORIZATION_TOKEN)"
   ```

## Quick Start

### Run the Full Benchmark

From the `benchmarks/` directory:

```bash
cd benchmarks
./scripts/run-benchmark.sh
```

This will benchmark all 6 services sequentially:
1. `spring-uninstrumented` → `spring-auto` → `spring-manual`
2. `express-uninstrumented` → `express-auto` → `express-manual`

Each service runs: warmup (120s) → steady-state (800s at 400 rps) → cooldown (120s).

**Total duration**: ~60 minutes for all 6 services.

### Overriding Parameters

```bash
# Lower rate for resource-constrained machines
RATE=100 ./scripts/run-benchmark.sh

# Shorter warmup for Node.js-only runs
WARMUP_DURATION=60s ./scripts/run-benchmark.sh

# Shorter steady-state for a quick check
STEADY_STATE_DURATION=60s RATE=50 ./scripts/run-benchmark.sh
```

### Manual Testing (Single Service)

To test a single service manually:

```bash
# Start service
docker compose --profile spring-uninstrumented up -d

# Wait for health check (30-60 seconds)
curl http://localhost:8082/songs/Polly/Nirvana

# Warmup — stabilizes JVM JIT / Node.js runtime before measurement
cd benchmarks
SERVICE_URL=http://localhost:8082 \
  k6 run k6/scenarios/warmup.js

# Steady-state measurement
SERVICE_URL=http://localhost:8082 \
SERVICE_NAME=spring-uninstrumented \
SUMMARY_FILE=results/manual-test-summary.json \
  k6 run \
    --out json=results/manual-test-raw.json \
    k6/scenarios/benchmark.js

# Shutdown
docker compose --profile spring-uninstrumented down -v
```

## Benchmark Scenario (`k6/scenarios/benchmark.js`)

A single script with two named k6 scenarios that run back-to-back.

### Warmup

**Purpose**: Stabilize JVM JIT compilation / Node.js runtime before measurement.

| Parameter | Default | Env var |
|-----------|---------|---------|
| Executor | `constant-arrival-rate` | — |
| Rate | 400 rps | `RATE` |
| Duration | 120s | `WARMUP_DURATION` |
| Pre-allocated VUs | 50 | — |
| Max VUs | 200 | — |

No thresholds — warmup traffic is excluded from pass/fail evaluation.

### Steady-State

**Purpose**: Measure instrumentation overhead at equivalent load.

Uses `constant-arrival-rate` so both services receive the same number of requests regardless of their latency. With `constant-vus`, a slower service would naturally process fewer requests, giving it an unfair advantage.

| Parameter | Default | Env var |
|-----------|---------|---------|
| Executor | `constant-arrival-rate` | — |
| Rate | 400 rps | `RATE` |
| Duration | 800s | `STEADY_STATE_DURATION` |
| Pre-allocated VUs | 50 | — |
| Max VUs | 200 | — |

**Thresholds** (steady-state only):
- `http_req_failed < 0.01` (less than 1% failures)
- `http_req_duration p(95) < 2000` (p95 under 2 seconds)

## Understanding Results

### k6 Output Files

Results are saved to `results/{timestamp}/`:

```
results/20260217-143022/
├── benchmark.log                              # Full orchestration log
├── spring-uninstrumented-summary.json         # Compact per-service summary
├── spring-auto-summary.json
├── spring-manual-summary.json
├── express-uninstrumented-summary.json
├── express-auto-summary.json
├── express-manual-summary.json
├── k6-spring-uninstrumented-raw.json          # Full k6 data (all data points)
├── k6-spring-auto-raw.json
├── ...
├── spring-uninstrumented-timerange.txt        # Dash0 correlation timestamps
└── ...
```

### Viewing k6 Metrics

**Compare all services at a glance** (summary files):
```bash
cat results/{timestamp}/*-summary.json | jq -s 'sort_by(.service) | .[] | {service, p95_ms, avg_ms, failure_rate}'
```

**Deep-dive into raw data** (if needed):
```bash
cat results/{timestamp}/k6-spring-auto-raw.json | jq 'select(.type == "Point" and .metric == "http_req_duration")'
```

**Key metrics to compare**:
- `p95_ms` - 95th percentile latency (ms) during steady-state
- `avg_ms` - Average latency (ms) during steady-state
- `failure_rate` - Request failure rate during steady-state

**Expected results** (uninstrumented vs auto vs manual):
- P95 latency increase auto vs uninstrumented: 5-15%
- P95 latency increase manual vs uninstrumented: 2-8% (selective instrumentation)
- Failure rate: <1% for all variants at 200 rps

### Viewing Metrics in Dash0

The OTel Collector exports container metrics (`docker_stats` receiver) and k6 metrics (k6 OpenTelemetry output) to Dash0 during the test.

#### 1. Import the Dashboards

[`dashboards/`](dashboards/) contains two Perses dashboards:

- **`kubecon-eu-2026.json`** - Container CPU and memory for all 6 variants, per language and side by side
- **`k6-four-golden-signals.json`** - Latency, traffic, errors, and saturation from k6, filterable by service

To import one: in Dash0, go to **Dashboards → + Add**, click **Edit as JSON**, upload the file, and click **Apply**.

#### 2. Set Time Range

Use the timestamps from `*-timerange.txt` files:

```bash
cat results/{timestamp}/spring-uninstrumented-timerange.txt
# Output:
# Service: spring-uninstrumented
# Start: 2026-02-17T14:30:22Z
# End: 2026-02-17T14:37:42Z
# Container: songs-spring-uninstrumented
# Port: 8082
```

Set the Dash0 time picker to match the `Start` → `End` range.

#### 3. Key Metrics to Visualize

**CPU Usage**:
- Metric: `container.cpu.usage.total` (cumulative nanoseconds; use `rate()` and divide by `1e9` for cores)
- Filter: `container.name` = `songs-spring-uninstrumented` or `songs-spring-auto`

**Memory Usage**:
- Metric: `container.memory.usage.total`
- Filter: `container.name` = `songs-spring-uninstrumented` or `songs-spring-auto`

**Host-level metrics** (if needed):
- `system.cpu.utilization`
- `system.memory.usage`

#### 4. Compare Services in the Query Builder

**Example PromQL query** for side-by-side comparison:

```promql
avg by (container_name) (
  rate({otel_metric_name="container.cpu.usage.total", container_name=~"songs-spring-(uninstrumented|auto)"}[1m])
) / 1e9
```

This will show both services on the same graph, in CPU cores.

#### 5. Calculate Overhead Percentage

1. Note average CPU during steady-state window (5-minute flat load)
2. Calculate: `((auto_cpu - uninstrumented_cpu) / uninstrumented_cpu) × 100%`

**Example**:
- Uninstrumented: 15% CPU
- Auto: 18% CPU
- Overhead: `((18 - 15) / 15) × 100% = 20%`

### Interpreting Results

**Successful benchmark**:
- ✅ k6 tests complete without errors
- ✅ Failure rate < 1% for both services
- ✅ Dash0 metrics show data for test time ranges
- ✅ Visually observable difference in CPU/memory between uninstrumented and auto
- ✅ P95 latency differs measurably (expected: 5-15% increase for auto)

**Red flags**:
- ❌ High failure rate (>5%) - service may be overloaded or unhealthy
- ❌ No difference in metrics - instrumentation may not be active
- ❌ Extreme variance between runs - test environment is unstable

## Test Data Flow

1. **Cache-first strategy**: Database is pre-populated with "Polly by Nirvana" at startup via the DB init script
2. **Steady-state queries**: All k6 requests hit cached data (fast DB query path)
3. **Isolation**: MusicBrainz API latency variance is eliminated
4. **Focus**: Measures pure instrumentation overhead on DB operations

## Architecture

```
k6 (constant-arrival-rate: 200 rps)
    ↓
    GET /songs/Polly/Nirvana
    ↓
Service (Spring or Express × uninstrumented/auto/manual)
    ↓
PostgreSQL (cached lookup — eliminates MusicBrainz variance)
    ↓
OTLP telemetry → OTel Collector → Dash0
                     ↓
                 docker_stats receiver → Container CPU/memory → Dash0
```

**Key design decisions**:
- **`constant-arrival-rate`**: Both services receive equal request pressure; latency differences appear as VU exhaustion rather than reduced throughput
- **Single cached song**: Eliminates MusicBrainz API latency variance; isolates instrumentation overhead on DB operations
- **One service at a time**: Prevents resource contention between variants skewing results

## Troubleshooting

### k6 not installed

```bash
# macOS
brew install k6

# Verify
k6 version
```

### Service health check timeout

```bash
# Check logs
docker compose logs songs-spring-uninstrumented --tail=50

# Common issues:
# - PostgreSQL not ready (wait 30s after startup)
# - Port conflict (check nothing else is on 8080/8082)
# - OTel Collector not healthy (check port 13133)
```

### No metrics in Dash0

```bash
# Verify OBSERVABILITY_BACKEND is set
cat ../.env | grep OBSERVABILITY_BACKEND

# Check OTel Collector health
curl http://localhost:13133/health/status

# Check Dash0 exporter logs
docker compose logs otel-collector | grep -i dash0
```

### k6 threshold failures

**Symptom**: `http_req_duration p(95)<2000` threshold fails

**Causes**:
- Service under extreme load (normal for first run)
- System resource contention (close other apps)

**Solution**: Re-run benchmark with longer warmup or lower VU count

## Reproducibility

Run the benchmark suite multiple times to verify result stability:

```bash
for run in 1 2 3; do
  ./scripts/run-benchmark.sh
  sleep 600  # 10-minute cooldown between runs
done
```

**Success criteria**: Coefficient of variation (CV) < 15% across runs for p95 latency and CPU usage.

## Contributing

When adding new services:
1. Add the service to `k6/lib/config.js`
2. Add it to the `SERVICES`, `PORTS`, and `PROFILES` arrays in `scripts/run-benchmark.sh`

When adding new k6 scenarios (e.g., cache-miss, ramp-up):
1. Create `k6/scenarios/<name>.js` following the same `warmup` + `steady_state` pattern
2. Pass scenario file via env var or add a flag to the orchestration script

## Resources

- [k6 Documentation](https://k6.io/docs/)
- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [Dash0: Import Dashboards](https://dash0.com/docs/dash0/dashboards/import-dashboards)
- [Dash0: OpenTelemetry Metric Names in PromQL](https://dash0.com/docs/dash0/telemetry/metrics/understand-otel-metric-names)

## License

Part of KubeCon EU 2026 talk materials. See repository root for license information.
