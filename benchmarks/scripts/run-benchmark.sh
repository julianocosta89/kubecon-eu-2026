#!/bin/bash
# Benchmark Orchestration Script
# Benchmarks all 6 service variants: spring/express × uninstrumented/auto/manual

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$BENCHMARK_DIR")"
RESULTS_DIR="${BENCHMARK_DIR}/results"

# Load environment variables from .env file
if [ -f "${PROJECT_ROOT}/.env" ]; then
    set -a
    source "${PROJECT_ROOT}/.env"
    set +a
fi
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
RUN_DIR="${RESULTS_DIR}/${TIMESTAMP}"

# Services to benchmark (name, port, profile)
# Order: uninstrumented → auto → manual, Spring then Express
SERVICES=("spring-uninstrumented" "spring-auto"    "spring-manual"
          "express-uninstrumented" "express-auto"  "express-manual")
PORTS=(8082 8080 8081 3002 3000 3001)
PROFILES=("spring-uninstrumented" "spring-auto"    "spring-manual"
          "express-uninstrumented" "express-auto"  "express-manual")

# k6 configuration (overridable via env)
RATE="${RATE:-400}"                        # requests/second during steady-state
WARMUP_DURATION="${WARMUP_DURATION:-120s}" # JVM needs 120s; Node.js stabilizes in 60s
STEADY_STATE_DURATION="${STEADY_STATE_DURATION:-800s}"
COOLDOWN="${COOLDOWN:-120}"                # seconds between services

# Validate SERVICE if provided
if [ -n "$SERVICE" ]; then
    found=false
    for svc in "${SERVICES[@]}"; do
        if [ "$svc" = "$SERVICE" ]; then
            found=true
            break
        fi
    done
    if [ "$found" = false ]; then
        echo -e "${RED}Unknown service: $SERVICE${NC}"
        echo "Valid services: ${SERVICES[*]}"
        exit 1
    fi
fi

# Ensure k6 is installed
if ! command -v k6 &> /dev/null; then
    echo -e "${RED}k6 is not installed. Install it with: brew install k6${NC}"
    exit 1
fi

# Ensure observability backend is set to datadog
if [ "$OBSERVABILITY_BACKEND" != "datadog" ]; then
    echo -e "${YELLOW}   OBSERVABILITY_BACKEND is not set to 'datadog'${NC}"
    echo -e "${YELLOW}   Current value: ${OBSERVABILITY_BACKEND:-not set}${NC}"
    echo -e "${YELLOW}   Please set it in .env file or export OBSERVABILITY_BACKEND=datadog${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create results directory
mkdir -p "$RUN_DIR"
echo -e "${BLUE} Benchmark results will be saved to: ${RUN_DIR}${NC}"

# Log file
LOG_FILE="${RUN_DIR}/benchmark.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
if [ -n "$SERVICE" ]; then
    echo "k6 Benchmark - ${SERVICE}"
else
    echo "k6 Benchmark - All 6 Service Variants"
fi
echo "=========================================="
echo "Timestamp:      $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
echo "Services:       ${SERVICE:-${SERVICES[*]}}"
echo "Rate:           ${RATE} rps"
echo "Warmup:         ${WARMUP_DURATION}"
echo "Steady-state:   ${STEADY_STATE_DURATION}"
echo "Cooldown:       ${COOLDOWN}s between services"
echo "=========================================="
echo ""

# Wait for a service to be healthy
wait_for_health() {
    local service_name=$1
    local port=$2
    local max_attempts=60
    local attempt=0

    echo -e "${YELLOW} Waiting for ${service_name} to be healthy...${NC}"

    # Wait for OTel Collector (only needed for instrumented services)
    case "$service_name" in
        *uninstrumented*) ;;  # no collector needed
        *)
            while [ $attempt -lt $max_attempts ]; do
                if docker compose ps otel-collector 2>/dev/null | grep -q "healthy"; then
                    echo -e "${GREEN}OTel Collector is healthy${NC}"
                    break
                fi
                attempt=$((attempt + 1))
                echo "Attempt $attempt/$max_attempts: OTel Collector not ready..."
                sleep 2
            done
            if [ $attempt -eq $max_attempts ]; then
                echo -e "${RED} OTel Collector failed to become healthy${NC}"
                return 1
            fi
            attempt=0
            ;;
    esac

    # Wait for the service itself
    while [ $attempt -lt $max_attempts ]; do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${port}/songs/Polly/Nirvana" | grep -q "200"; then
            echo -e "${GREEN} ${service_name} is healthy (port ${port})${NC}"
            return 0
        fi
        attempt=$((attempt + 1))
        echo "Attempt $attempt/$max_attempts: ${service_name} not ready..."
        sleep 2
    done

    echo -e "${RED} ${service_name} failed to become healthy${NC}"
    return 1
}

# Run the full benchmark for one service
run_service_benchmark() {
    local service_name=$1
    local port=$2
    local profile=$3

    echo ""
    echo "=========================================="
    echo "Benchmarking: ${service_name}"
    echo "=========================================="

    START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "Start time: ${START_TIME}"

    # Clean environment
    echo -e "${BLUE} Cleaning environment...${NC}"
    cd "$PROJECT_ROOT"
    docker compose down -v > /dev/null 2>&1

    # Start service + infrastructure
    echo -e "${BLUE} Starting ${service_name} (profile: ${profile})...${NC}"
    docker compose --profile "$profile" up -d

    # Wait for health
    if ! wait_for_health "$service_name" "$port"; then
        echo -e "${RED} Health check failed for ${service_name}, skipping${NC}"
        docker compose logs --tail=50 "$service_name" 2>/dev/null || true
        docker compose down -v
        return 1
    fi

    # Phase 1: Warmup (separate invocation — no OTel export, not sent to Datadog)
    echo -e "${BLUE} Running warmup (${WARMUP_DURATION})...${NC}"
    cd "$BENCHMARK_DIR"
    SERVICE_URL="http://localhost:${port}" \
    WARMUP_VUS="${WARMUP_VUS:-10}" \
    WARMUP_DURATION="${WARMUP_DURATION}" \
        k6 run k6/scenarios/warmup.js

    STEADY_STATE_START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "Steady-state start: ${STEADY_STATE_START_TIME}"

    # Phase 2: Steady-state (metrics exported to OTel Collector / Datadog)
    echo -e "${BLUE} Running steady-state (${STEADY_STATE_DURATION} at ${RATE} rps)...${NC}"
    SERVICE_URL="http://localhost:${port}" \
    SERVICE_NAME="${service_name}" \
    SUMMARY_FILE="${RUN_DIR}/${service_name}-summary.json" \
    RATE="${RATE}" \
    STEADY_STATE_DURATION="${STEADY_STATE_DURATION}" \
    K6_OTEL_GRPC_EXPORTER_INSECURE=true \
    K6_OTEL_SERVICE_NAME="k6-${service_name}" \
        k6 run \
            --out opentelemetry \
            --out "json=${RUN_DIR}/k6-${service_name}-raw.json" \
            k6/scenarios/benchmark.js

    END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "End time: ${END_TIME}"

    # Save time range for Datadog metric correlation
    # Use STEADY_STATE_START_TIME to exclude warmup when querying container metrics
    cat > "${RUN_DIR}/${service_name}-timerange.txt" <<EOF
Service: ${service_name}
Start: ${START_TIME}
Steady-state start: ${STEADY_STATE_START_TIME}
End: ${END_TIME}
Container: songs-${service_name}
Port: ${port}
EOF

    echo -e "${GREEN} Benchmark complete for ${service_name}${NC}"

    # Shutdown
    echo -e "${BLUE} Shutting down ${service_name}...${NC}"
    cd "$PROJECT_ROOT"
    docker compose --profile "$profile" down -v

    # Cooldown between services (skip after last, skip for single-service runs)
    local last_service="${SERVICES[$((${#SERVICES[@]}-1))]}"
    if [ -z "$SERVICE" ] && [ "$service_name" != "$last_service" ]; then
        echo -e "${YELLOW} Cooldown (${COOLDOWN}s)...${NC}"
        sleep "$COOLDOWN"
    fi
}

# Main benchmark loop
for i in "${!SERVICES[@]}"; do
    [ -n "$SERVICE" ] && [ "${SERVICES[$i]}" != "$SERVICE" ] && continue
    run_service_benchmark "${SERVICES[$i]}" "${PORTS[$i]}" "${PROFILES[$i]}"
done

echo ""
echo "=========================================="
echo "Benchmark Complete!"
echo "=========================================="
echo "Results directory: ${RUN_DIR}"
echo ""
echo "Files generated:"
ls -lh "$RUN_DIR"
echo ""
echo "Summary per service (p95 latency, failure rate):"
for service in "${SERVICES[@]}"; do
    summary_file="${RUN_DIR}/${service}-summary.json"
    if [ -f "$summary_file" ]; then
        p95=$(jq -r '.p95_ms // "N/A"' "$summary_file" 2>/dev/null)
        fail=$(jq -r '.failure_rate // "N/A"' "$summary_file" 2>/dev/null)
        echo "  ${service}: p95=${p95}ms  failure_rate=${fail}"
    fi
done
echo ""
echo "Next steps:"
echo "1. Compare summaries: cat ${RUN_DIR}/*-summary.json | jq ."
echo "2. Check Datadog Metrics Explorer for container CPU/memory using timerange files"
echo "3. See benchmarks/README.md for detailed analysis instructions"
echo "=========================================="
