# AGENTS.md

This file provides guidance to AI coding agents working with code in this repository.

## Project Overview

This repository contains demonstration code for the KubeCon EU 2026 talk "How manual OTel instrumentation saves more than just money". It showcases three instrumentation approaches for a music service, enabling CPU and memory benchmarking:

1. **Auto-instrumentation**: Java agent and Node.js auto-instrumentations
2. **Manual-instrumentation**: Explicit SDK initialization with selective instrumentations
3. **Uninstrumented**: Baseline services with all OpenTelemetry removed

Each approach has both a Java/Spring Boot and a Node.js/Express implementation (6 services total). All services query song metadata from a PostgreSQL database and fall back to the MusicBrainz API when songs are not found locally.

## Architecture

### Directory Structure

```
src/
├── auto-instrumentation/
│   ├── spring-auto/              # Java agent auto-instrumentation
│   └── express-auto/             # Node.js auto-instrumentations
├── manual-instrumentation/
│   ├── spring-manual/            # SDK-based manual spans
│   └── express-manual/           # Selective instrumentations + manual spans
├── uninstrumented/
│   ├── spring-uninstrumented/    # No OpenTelemetry dependencies
│   └── express-uninstrumented/   # No OpenTelemetry dependencies
├── otel-collector/               # Custom OpenTelemetry Collector (shared)
└── songs-db/                     # PostgreSQL database (shared)
```

### Port Allocation

| Service | Auto | Manual | Uninstrumented |
|---------|------|--------|----------------|
| Spring  | 8080 | 8081   | 8082           |
| Express | 3000 | 3001   | 3002           |

Shared services: songs-db (5432), otel-collector (4317/4318), jaeger (16686)

### Service Components

**Auto-instrumented services:**
- **songs-spring-auto**: Spring Boot 4.1 (Java 25, port 8080) with Java agent auto-instrumentation and manual span enrichment in SongService
- **songs-express-auto**: Express 5.2 (Node.js, port 3000) with `@opentelemetry/auto-instrumentations-node` and pino-opentelemetry-transport

**Manual-instrumented services:**
- **songs-spring-manual**: Spring Boot 4.1 (Java 25, port 8081) with OpenTelemetry SDK, explicit spans in SongController and SongService, no Java agent
- **songs-express-manual**: Express 5.2 (Node.js, port 3001) with selective instrumentations (HTTP, Express, pg) and manual spans for MusicBrainz/persist operations

**Uninstrumented services (baseline):**
- **songs-spring-uninstrumented**: Spring Boot 4.1 (Java 25, port 8082) with no OpenTelemetry dependencies
- **songs-express-uninstrumented**: Express 5.2 (Node.js, port 3002) with no OpenTelemetry dependencies

**Shared infrastructure:**
- **otel-collector**: Custom OpenTelemetry Collector built with OCB, supports Jaeger and Datadog backends
- **songs-db**: PostgreSQL 18.6-alpine3.23 database
- **jaeger**: Jaeger 2.20.0 for trace visualization (UI on port 16686)

### Data Flow

1. Client requests song metadata via `/songs/{title}/{artist}` endpoint
2. Service checks PostgreSQL database first
3. If not found, queries MusicBrainz API (`https://musicbrainz.org/ws/2/recording/`)
4. Response is persisted to database for future requests
5. Telemetry data (instrumented services only) sent to OTel Collector via OTLP HTTP (port 4318)
6. Collector processes and exports to Jaeger or Datadog

## Development Commands

### Building Services

```bash
# Build specific service
docker compose build songs-spring-auto
docker compose build songs-spring-manual
docker compose build songs-spring-uninstrumented
docker compose build songs-express-auto
docker compose build songs-express-manual
docker compose build songs-express-uninstrumented
docker compose build otel-collector
```

### Running Services

The project uses Docker Compose profiles:

```bash
# Run by instrumentation type (both languages)
docker compose --profile auto up
docker compose --profile manual up
docker compose --profile uninstrumented up

# Run individual services
docker compose --profile spring-auto up
docker compose --profile spring-manual up
docker compose --profile spring-uninstrumented up
docker compose --profile express-auto up
docker compose --profile express-manual up
docker compose --profile express-uninstrumented up

# Run all variants for benchmarking
docker compose --profile auto --profile manual --profile uninstrumented up

# Run in background
docker compose --profile spring-auto up -d
```

### Testing Endpoints

```bash
# Auto-instrumented
curl http://localhost:8080/songs/Polly/Nirvana   # Spring auto
curl http://localhost:3000/songs/Polly/Nirvana   # Express auto

# Manual-instrumented
curl http://localhost:8081/songs/Polly/Nirvana   # Spring manual
curl http://localhost:3001/songs/Polly/Nirvana   # Express manual

# Uninstrumented
curl http://localhost:8082/songs/Polly/Nirvana   # Spring uninstrumented
curl http://localhost:3002/songs/Polly/Nirvana   # Express uninstrumented
```

### Accessing Observability UIs

- **Jaeger UI**: http://localhost:16686
- **OTel Collector Health**: http://localhost:13133/health/status

### Cleanup

```bash
# Stop and remove containers with volumes
docker compose --profile spring-auto down -v
docker compose --profile auto down -v
docker compose --profile auto --profile manual --profile uninstrumented down -v
```

## Environment Configuration

The [.env](.env) file controls the observability backend:

- `OBSERVABILITY_BACKEND=jaeger` (default): Send telemetry only to Jaeger
- `OBSERVABILITY_BACKEND=datadog`: Send telemetry to both Datadog and Jaeger (requires credentials)

**Datadog Configuration** (if using):
- Set `DD_SITE_PARAMETER` (e.g., `datadoghq.com`)
- Set `DD_API_KEY` with your Datadog API key

## Instrumentation Approach Comparison

### Auto-instrumentation
- **Spring**: Java agent (`opentelemetry-javaagent.jar`) added via Dockerfile, enriches spans via `Span.current()` in SongService
- **Express**: `@opentelemetry/auto-instrumentations-node` loaded via `--require ./instrumentation.js`, captures all HTTP/DB/DNS activity

### Manual-instrumentation
- **Spring**: No Java agent. Uses `opentelemetry-spring-boot-starter` + explicit SDK configuration in [OpenTelemetryConfig.java](src/manual-instrumentation/spring-manual/src/main/java/com/slct/demo/config/OpenTelemetryConfig.java). Manual spans with `tracer.spanBuilder()` in SongController (HTTP) and SongService (DB)
- **Express**: Selective instrumentations (HTTP, Express, pg) in [instrumentation.js](src/manual-instrumentation/express-manual/instrumentation.js). Manual spans with `tracer.startActiveSpan()` for MusicBrainz API and persistSong in [app.js](src/manual-instrumentation/express-manual/app.js)

### Uninstrumented
- **Spring**: No OTel dependencies in build.gradle, no agent in Dockerfile, no span code in SongService
- **Express**: No OTel packages in package.json, no instrumentation.js, plain pino logger (no OTel transport)

## Java Services

### Build System
- Gradle 9+ with Gradle wrapper
- Java 25 toolchain required
- Key build files:
  - [Auto build.gradle](src/auto-instrumentation/spring-auto/build.gradle)
  - [Manual build.gradle](src/manual-instrumentation/spring-manual/build.gradle) (includes OTel SDK BOM)
  - [Uninstrumented build.gradle](src/uninstrumented/spring-uninstrumented/build.gradle) (no OTel deps)

### Local Development (without Docker)

```bash
cd src/auto-instrumentation/spring-auto  # or manual-instrumentation/spring-manual, etc.
./gradlew build
./gradlew bootRun  # requires PostgreSQL and OTel Collector for instrumented variants
```

## Node.js Services

### Package Manager
- npm with package-lock.json

### Local Development (without Docker)

```bash
cd src/auto-instrumentation/express-auto  # or manual-instrumentation/express-manual, etc.
npm install

# Auto/Manual (with instrumentation)
node --require ./instrumentation.js app.js

# Uninstrumented
node app.js
```

## OpenTelemetry Collector

### Building Custom Collector

The collector is built using OpenTelemetry Collector Builder (OCB):

```bash
cd src/otel-collector
# The Dockerfile handles the build, or manually:
# ocb --config ocb-manifest.yaml
```

### Configuration Switching

The collector configuration is selected at runtime via `OBSERVABILITY_BACKEND`:
- `jaeger` -> Uses [otel-collector-config-jaeger.yaml](src/otel-collector/otel-collector-config-jaeger.yaml)
- `datadog` -> Uses [otel-collector-config-datadog.yaml](src/otel-collector/otel-collector-config-datadog.yaml)

### Key Collector Features

1. **OTTL Filtering**: Removes noisy `@opentelemetry/instrumentation-net` and `@opentelemetry/instrumentation-dns` spans
2. **Resource Processing**: Adds `deployment.environment.name=dev` attribute
3. **Health Checks**: Exposes `/health/status` endpoint on port 13133
4. **Multiple Exporters**: Supports both Jaeger (OTLP) and Datadog exporters

## CI/CD

GitHub Actions workflows are located in [.github/workflows/](.github/workflows/):

### Build and Test Workflow ([build-test.yml](.github/workflows/build-test.yml))

Triggers on PRs to main branch. Uses path filtering to only test changed services:
- `src/auto-instrumentation/spring-auto/**` -> Builds and tests songs-spring-auto
- `src/auto-instrumentation/express-auto/**` -> Builds and tests songs-express-auto
- `src/manual-instrumentation/spring-manual/**` -> Builds and tests songs-spring-manual
- `src/manual-instrumentation/express-manual/**` -> Builds and tests songs-express-manual
- `src/uninstrumented/spring-uninstrumented/**` -> Builds and tests songs-spring-uninstrumented
- `src/uninstrumented/express-uninstrumented/**` -> Builds and tests songs-express-uninstrumented
- `src/otel-collector/**` -> Builds and caches otel-collector

**Integration Tests**:
- Instrumented services: Starts with Docker Compose, sends test request, verifies traces in Jaeger
- Uninstrumented services: Starts with Docker Compose, validates HTTP response only

**OTel Collector Caching**:
- Collector image is cached based on hash of YAML and Dockerfile
- Shared between integration test jobs to reduce build time

### Renovate Workflow ([renovate-daily.yml](.github/workflows/renovate-daily.yml))

Runs daily to check for dependency updates via Renovate bot. Dependencies are grouped per variant (auto/manual/uninstrumented) for both npm and Gradle.

## MusicBrainz API Integration

All 6 service variants implement the same logic to find the best song metadata from MusicBrainz:
1. Search for recordings matching title and artist
2. Filter out live recordings/concerts when possible
3. Select the recording with the earliest studio release year
4. Extract genre from recording tags
5. Persist to database with conflict handling (upsert)

The User-Agent header `otel-demo/1.0` is required by MusicBrainz API.
