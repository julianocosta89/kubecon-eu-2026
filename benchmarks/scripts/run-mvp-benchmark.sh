#!/bin/bash
# MVP Benchmark Orchestration Script
# Benchmarks Spring uninstrumented vs auto-instrumented services

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

# Services to benchmark (MVP: 2 services only)
SERVICES=("spring-uninstrumented" "spring-auto")
PORTS=(8082 8080)
PROFILES=("spring-uninstrumented" "spring-auto")

# Test configuration
WARMUP_DURATION=120  # seconds
STEADY_STATE_DURATION=300  # seconds
COOLDOWN_DURATION=120  # seconds between services

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
echo "k6 MVP Benchmark - Spring Services"
echo "=========================================="
echo "Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
echo "Services: ${SERVICES[*]}"
echo "Warmup: ${WARMUP_DURATION}s"
echo "Steady State: ${STEADY_STATE_DURATION}s"
echo "Cooldown: ${COOLDOWN_DURATION}s"
echo "=========================================="
echo ""

# Function to wait for health check
wait_for_health() {
    local service_name=$1
    local port=$2
    local max_attempts=60
    local attempt=0

    echo -e "${YELLOW} Waiting for ${service_name} to be healthy...${NC}"

    # Wait for OTel Collector
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

    # Wait for service
    attempt=0
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

# Function to run benchmark for a service
run_service_benchmark() {
    local service_name=$1
    local port=$2
    local profile=$3

    echo ""
    echo "=========================================="
    echo "Benchmarking: ${service_name}"
    echo "=========================================="

    # Record start time
    START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "Start time: ${START_TIME}"

    # Step 1: Clean environment
    echo -e "${BLUE} Cleaning environment...${NC}"
    cd "$PROJECT_ROOT"
    docker compose down -v > /dev/null 2>&1

    # Step 2: Start service + infrastructure
    echo -e "${BLUE} Starting ${service_name} (profile: ${profile})...${NC}"
    docker compose --profile "$profile" up -d

    # Step 3: Wait for health checks
    if ! wait_for_health "$service_name" "$port"; then
        echo -e "${RED} Health check failed for ${service_name}, skipping benchmark${NC}"
        docker compose logs --tail=50 "$service_name"
        docker compose down -v
        return 1
    fi

    # Step 4: Run warmup
    echo -e "${BLUE} Running warmup (${WARMUP_DURATION}s at 10 VUs)...${NC}"
    cd "$BENCHMARK_DIR"
    SERVICE_URL="http://localhost:${port}" k6 run \
        --out "json=${RUN_DIR}/k6-${service_name}-warmup.json" \
        k6/scenarios/warmup.js

    # Step 5: Run steady-state test
    echo -e "${BLUE} Running steady-state test (${STEADY_STATE_DURATION}s at 50 VUs)...${NC}"
    SERVICE_URL="http://localhost:${port}" k6 run \
        --out "json=${RUN_DIR}/k6-${service_name}-steady-state.json" \
        k6/scenarios/steady-state.js

    # Record end time
    END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "End time: ${END_TIME}"

    # Save time range for Datadog correlation
    cat > "${RUN_DIR}/${service_name}-timerange.txt" <<EOF
Service: ${service_name}
Start: ${START_TIME}
End: ${END_TIME}
Container: songs-${service_name}
Port: ${port}
EOF

    echo -e "${GREEN} Benchmark complete for ${service_name}${NC}"

    # Step 7: Shutdown
    echo -e "${BLUE} Shutting down ${service_name}...${NC}"
    cd "$PROJECT_ROOT"
    docker compose --profile "$profile" down -v

    # Step 8: Cooldown before next service
    if [ "$service_name" != "${SERVICES[$((${#SERVICES[@]}-1))]}" ]; then
        echo -e "${YELLOW} Cooldown period (${COOLDOWN_DURATION}s)...${NC}"
        sleep "$COOLDOWN_DURATION"
    fi
}

# Main benchmark loop
for i in "${!SERVICES[@]}"; do
    run_service_benchmark "${SERVICES[$i]}" "${PORTS[$i]}" "${PROFILES[$i]}"
done

echo ""
echo "=========================================="
echo "MVP Benchmark Complete!"
echo "=========================================="
echo "Results directory: ${RUN_DIR}"
echo ""
echo "Files generated:"
ls -lh "$RUN_DIR"
echo ""
echo "Next steps:"
echo "1. View k6 metrics: cat ${RUN_DIR}/k6-*-steady-state.json | jq '.metrics'"
echo "2. Check Datadog Metrics Explorer for container metrics during test time ranges"
echo "3. See timerange files for Datadog correlation: cat ${RUN_DIR}/*-timerange.txt"
echo ""
echo "For detailed instructions, see benchmarks/README.md"
echo "=========================================="
