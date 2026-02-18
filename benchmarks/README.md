# k6 Benchmarking Infrastructure

This directory contains load testing infrastructure to benchmark OpenTelemetry instrumentation overhead for the KubeCon EU 2026 talk "How manual OTel instrumentation saves more than just money".

## Overview

The benchmark suite quantifies CPU and memory differences between:
- **Uninstrumented** (baseline) - No OpenTelemetry dependencies
- **Auto-instrumented** - Java agent / Node.js auto-instrumentations
- **Manual-instrumented** - Selective SDK-based instrumentation (future)

### MVP Scope

The current implementation benchmarks:
- ✅ `songs-spring-uninstrumented` (baseline)
- ✅ `songs-spring-auto` (auto-instrumented with Java agent)

Future expansion: Express services, manual-instrumented services, additional test scenarios.

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

3. **Datadog Account** - Metrics collection backend
   - Set up account at https://www.datadoghq.com/
   - Obtain API key from https://app.datadoghq.com/organization-settings/api-keys

### Environment Configuration

1. **Set Datadog credentials** in `.env` file (project root):
   ```bash
   OBSERVABILITY_BACKEND=datadog
   DD_SITE_PARAMETER=datadoghq.com  # or datadoghq.eu
   DD_API_KEY=your_api_key_here
   ```

2. **Verify configuration**:
   ```bash
   cat ../.env | grep -E "(OBSERVABILITY_BACKEND|DD_SITE_PARAMETER|DD_API_KEY)"
   ```

## Quick Start

### Run MVP Benchmark

From the `benchmarks/` directory:

```bash
# Ensure you're in the benchmarks directory
cd benchmarks

# Run the full MVP benchmark suite
./scripts/run-mvp-benchmark.sh
```

This will:
1. Test `spring-uninstrumented` (baseline) → warmup → steady-state
2. Cooldown (2 minutes)
3. Test `spring-auto` (auto-instrumented) → warmup → steady-state
4. Generate results in `results/{timestamp}/`

**Duration**: ~15 minutes total (7 minutes per service + cooldown)

### Manual Testing (Single Service)

To test a single service manually:

```bash
cd benchmarks

# Start service
cd ..
docker compose --profile spring-uninstrumented up -d
cd benchmarks

# Wait for health check (30-60 seconds)
curl http://localhost:8082/songs/Polly/Nirvana

# Run warmup
SERVICE_URL=http://localhost:8082 k6 run k6/scenarios/warmup.js

# Run steady-state test
SERVICE_URL=http://localhost:8082 k6 run \
  --out json=results/manual-test.json \
  k6/scenarios/steady-state.js

# Shutdown
cd ..
docker compose --profile spring-uninstrumented down -v
```

## Benchmark Scenarios

### 1. Warmup (`k6/scenarios/warmup.js`)

**Purpose**: Stabilize JVM JIT compilation before measurement

**Configuration**:
- Duration: 120 seconds
- Load: 10 VUs (constant)
- Endpoint: `GET /songs/Polly/Nirvana`

**Metrics**: Basic HTTP duration tracking (no thresholds)

### 2. Steady-State (`k6/scenarios/steady-state.js`)

**Purpose**: Measure baseline instrumentation overhead with cached data

**Configuration**:
- Duration: 300 seconds (5 minutes)
- Load: 50 VUs (constant)
- Endpoint: `GET /songs/Polly/Nirvana` (cached in DB)

**Metrics**:
- HTTP request duration (p50, p95, p99)
- Requests per second
- Failure rate

**Thresholds**:
- `http_req_failed < 0.01` (less than 1% failures)
- `http_req_duration p(95) < 2000` (p95 under 2 seconds)

## Understanding Results

### k6 Output Files

Results are saved to `results/{timestamp}/`:

```
results/20260217-143022/
├── benchmark.log                           # Full orchestration log
├── k6-spring-uninstrumented-warmup.json    # Warmup metrics
├── k6-spring-uninstrumented-steady-state.json  # Steady-state metrics
├── k6-spring-auto-warmup.json
├── k6-spring-auto-steady-state.json
├── spring-uninstrumented-timerange.txt     # Datadog correlation timestamps
└── spring-auto-timerange.txt
```

### Viewing k6 Metrics

**Quick summary**:
```bash
cd results/{timestamp}
cat k6-spring-uninstrumented-steady-state.json | jq '.metrics | {
  http_req_duration: .http_req_duration.values,
  http_reqs: .http_reqs.values,
  http_req_failed: .http_req_failed.values
}'
```

**Key metrics to compare**:
- `http_req_duration.values.p(95)` - 95th percentile latency (ms)
- `http_req_duration.values.avg` - Average latency (ms)
- `http_reqs.values.rate` - Requests per second
- `http_req_failed.values.rate` - Failure rate

**Expected results** (uninstrumented vs auto):
- P95 latency increase: 5-15%
- RPS decrease: 5-10%
- Failure rate: <1% for both

### Viewing Datadog Metrics

The OTel Collector automatically exports container metrics to Datadog during the test.

#### 1. Navigate to Metrics Explorer

Go to: https://app.datadoghq.com/metric/explorer

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

Set Datadog time picker to match the `Start` → `End` range.

#### 3. Key Metrics to Visualize

**CPU Usage**:
- Metric: `container.cpu.usage.total`
- Filter: `container_name:songs-spring-uninstrumented` or `container_name:songs-spring-auto`
- Aggregation: `avg` or `max`

**Memory Usage**:
- Metric: `container.memory.usage.total`
- Filter: `container_name:songs-spring-uninstrumented` or `container_name:songs-spring-auto`
- Aggregation: `avg` or `max`

**Host-level metrics** (if needed):
- `system.cpu.usage`
- `system.mem.used`

#### 4. Create Comparison Dashboard

**Example query** for side-by-side comparison:

```
avg:container.cpu.usage.total{container_name:songs-spring-uninstrumented}
avg:container.cpu.usage.total{container_name:songs-spring-auto}
```

This will show both services on the same graph.

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
- ✅ Datadog metrics show data for test time ranges
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
k6 (50 VUs)
    ↓
    GET /songs/Polly/Nirvana
    ↓
Spring Service (instrumented or not)
    ↓
PostgreSQL (cached lookup)
    ↓
OTLP telemetry → OTel Collector → Datadog
                     ↓
                 docker_stats receiver → Container metrics → Datadog
```

**Key components**:
- **k6**: Generates constant load
- **Service**: Processes requests, emits OTLP telemetry (instrumented only)
- **OTel Collector**: Samples container metrics every 10s, exports to Datadog
- **Datadog**: Visualizes CPU/memory over time

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

### No metrics in Datadog

```bash
# Verify OBSERVABILITY_BACKEND is set
cat ../.env | grep OBSERVABILITY_BACKEND

# Check OTel Collector health
curl http://localhost:13133/health/status

# Check Datadog exporter logs
docker compose logs otel-collector | grep datadog
```

### k6 threshold failures

**Symptom**: `http_req_duration p(95)<2000` threshold fails

**Causes**:
- Service under extreme load (normal for first run)
- System resource contention (close other apps)

**Solution**: Re-run benchmark with longer warmup or lower VU count

## Future Expansion

### Phase 2: Express Services

Add `songs-express-uninstrumented` and `songs-express-auto`:

1. Update `run-mvp-benchmark.sh`: Add Express services to `SERVICES` array
2. Reduce warmup to 60s (Node.js stabilizes faster)
3. Compare Java agent vs Node.js auto-instrumentations

### Phase 3: Manual-Instrumented Services

Benchmark `songs-spring-manual` and `songs-express-manual`:

1. Add manual services to benchmark script
2. Compare manual vs auto overhead
3. Quantify optimization potential

### Phase 4: Additional Scenarios

Implement new k6 scenarios:

**Ramp-up** (`ramp-up.js`):
- 10-minute load progression (0 → 100 VUs)
- Measure instrumentation impact during scaling

**Cache-miss** (`cache-miss.js`):
- Random song queries (MusicBrainz API-heavy)
- Measure instrumentation impact on I/O-bound operations

**Mixed-workload** (`mixed-workload.js`):
- 80% cached queries, 20% cache misses
- Realistic production simulation

### Phase 5: Statistical Analysis

Python script for automated analysis:

```python
# benchmarks/analysis/analyze.py
import json
import numpy as np
from scipy import stats

def calculate_overhead(uninstrumented_metrics, auto_metrics):
    # Load k6 JSON results
    # Calculate mean, std, confidence intervals
    # Perform Welch's t-test
    # Generate comparison report
    pass
```

### Phase 6: Reproducibility

Repeat full benchmark suite 3× to measure stability:

```bash
for run in 1 2 3; do
  ./scripts/run-mvp-benchmark.sh
  sleep 600  # 10-minute cooldown between runs
done
```

**Success criteria**: Coefficient of variation (CV) < 15% across runs

## Contributing

When adding new services or scenarios:

1. **Update config**: Add service to `k6/lib/config.js`
2. **Create scenario**: Add new scenario to `k6/scenarios/`
3. **Update orchestration**: Modify `scripts/run-mvp-benchmark.sh`
4. **Document**: Update this README with new metrics/interpretation

## Resources

- [k6 Documentation](https://k6.io/docs/)
- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [Datadog Metrics Explorer](https://docs.datadoghq.com/metrics/explorer/)
- [Project CLAUDE.md](../CLAUDE.md) - Full architecture reference

## License

Part of KubeCon EU 2026 talk materials. See repository root for license information.
