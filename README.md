# kubecon-eu-2026

Companion repo for the talk **"How manual OTel instrumentation saves more than just money"** presented at KubeCon EU 2026.

It compares CPU and memory overhead between two OpenTelemetry instrumentation strategies (auto and manual), using uninstrumented services as the baseline. Each variant is implemented in both Java/Spring Boot and Node.js/Express — 6 services total.

| Strategy | Spring Boot | Express |
|---|---|---|
| Auto-instrumented | `songs-spring-auto` (port 8080) | `songs-express-auto` (port 3000) |
| Manual-instrumented | `songs-spring-manual` (port 8081) | `songs-express-manual` (port 3001) |
| Uninstrumented (baseline) | `songs-spring-uninstrumented` (port 8082) | `songs-express-uninstrumented` (port 3002) |

All services expose a single endpoint: `GET /songs/{title}/{artist}`. They check a local PostgreSQL database first, then fall back to the MusicBrainz API.

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with Compose v2
- `curl` (for smoke-testing endpoints)

Verify:

```bash
docker compose version
```

---

## Quick Start

### 1. Configure the observability backend

Copy the example env and fill in your backend choice:

```bash
cp .env.example .env   # if it exists, otherwise edit .env directly
```

**Jaeger only** (no credentials needed — the default for local exploration):

```
OBSERVABILITY_BACKEND=jaeger
```

**Jaeger + Datadog** (requires a Datadog account):

```
OBSERVABILITY_BACKEND=datadog
DD_SITE_PARAMETER=datadoghq.com   # or datadoghq.eu
DD_API_KEY=your_api_key_here
```

> **Warning**: Never commit real credentials. The `.env` file is listed in `.gitignore`.

### 2. Start a service group

```bash
# Auto-instrumented (both Spring and Express)
docker compose --profile auto up

# Manual-instrumented (both Spring and Express)
docker compose --profile manual up

# Uninstrumented / baseline (both Spring and Express)
docker compose --profile uninstrumented up

# All 6 services at once (useful for benchmarking)
docker compose --profile auto --profile manual --profile uninstrumented up
```

Start in the background by appending `-d`.

### 3. Send a request

```bash
# Auto
curl http://localhost:8080/songs/Polly/Nirvana   # Spring
curl http://localhost:3000/songs/Polly/Nirvana   # Express

# Manual
curl http://localhost:8081/songs/Polly/Nirvana   # Spring
curl http://localhost:3001/songs/Polly/Nirvana   # Express

# Uninstrumented
curl http://localhost:8082/songs/Polly/Nirvana   # Spring
curl http://localhost:3002/songs/Polly/Nirvana   # Express
```

### 4. Explore traces

Open the Jaeger UI: [http://localhost:16686](http://localhost:16686)

### 5. Tear down

```bash
docker compose --profile auto down -v
docker compose --profile manual down -v
docker compose --profile uninstrumented down -v
```

---

## Running Individual Services

Each service has its own profile if you only want one:

```bash
docker compose --profile spring-auto up
docker compose --profile express-auto up
docker compose --profile spring-manual up
docker compose --profile express-manual up
docker compose --profile spring-uninstrumented up
docker compose --profile express-uninstrumented up
```

---

## Building Images

```bash
docker compose build songs-spring-auto
docker compose build songs-express-manual
docker compose build otel-collector
# etc.
```

---

## Local Development (without Docker)

### Node.js services

```bash
cd src/auto-instrumentation/express-auto   # or express-manual, express-uninstrumented
npm install

# Auto / manual (loads OTel SDK via --require)
node --require ./instrumentation.js app.js

# Uninstrumented
node app.js
```

Requires `songs-db` (PostgreSQL on port 5432) and `otel-collector` (port 4318) to be running when using instrumented variants.

### Java/Spring Boot services

```bash
cd src/auto-instrumentation/spring-auto   # or spring-manual, spring-uninstrumented
./gradlew bootRun
```

Requires Java 25 and the same shared services listed above.

---

## Benchmarking

The `benchmarks/` directory contains a k6 load-testing suite that measures instrumentation overhead. It benchmarks all 6 services sequentially at 400 rps, comparing CPU and memory via Datadog container metrics.

See **[benchmarks/README.md](benchmarks/README.md)** for full setup and usage instructions.

Quick run:

```bash
cd benchmarks
./scripts/run-benchmark.sh
```

---

## Repository Structure

```
.
├── compose.yaml                  # Docker Compose services + profiles
├── .env                          # Observability backend config (not committed)
├── benchmarks/                   # k6 load tests and result scripts
│   ├── k6/                       # k6 scenarios and shared config
│   ├── scripts/                  # Orchestration script (run-benchmark.sh)
│   └── results/                  # Output from benchmark runs (git-ignored)
└── src/
    ├── auto-instrumentation/
    │   ├── spring-auto/          # Java agent auto-instrumentation
    │   └── express-auto/         # Node.js @opentelemetry/auto-instrumentations-node
    ├── manual-instrumentation/
    │   ├── spring-manual/        # opentelemetry-spring-boot-starter + explicit spans
    │   └── express-manual/       # Selective instrumentations + manual spans
    ├── uninstrumented/
    │   ├── spring-uninstrumented/  # No OTel dependencies
    │   └── express-uninstrumented/ # No OTel dependencies
    ├── otel-collector/           # Custom collector built with OCB
    └── songs-db/                 # PostgreSQL init scripts
```

---

## Shared Infrastructure

| Service | Port | Purpose |
|---|---|---|
| `songs-db` | 5432 | PostgreSQL — song metadata cache |
| `otel-collector` | 4317 (gRPC) / 4318 (HTTP) | Receives OTLP, exports to Jaeger/Datadog |
| `jaeger` | 16686 (UI) | Trace visualization |

---

## Instrumentation Approaches

### Auto-instrumentation

- **Spring**: Java agent (`opentelemetry-javaagent.jar`) injected via `JAVA_TOOL_OPTIONS` in Docker. Spans enriched with `Span.current()` in `SongService`.
- **Express**: `@opentelemetry/auto-instrumentations-node` loaded via `--require ./instrumentation.js`. Captures all HTTP, PostgreSQL, DNS, and net activity automatically.

### Manual-instrumentation

- **Spring**: No Java agent. Uses `opentelemetry-spring-boot-starter` with an explicit `OpenTelemetryConfig`. Manual spans created with `tracer.spanBuilder()` in `SongController` and `SongService`.
- **Express**: Only HTTP, Express, and `pg` instrumentations are loaded. Manual spans added with `tracer.startActiveSpan()` for the MusicBrainz API call and the `persistSong` operation.

### Uninstrumented

All OpenTelemetry dependencies removed. No agent, no SDK, no span code. Serves as the baseline for measuring overhead.
