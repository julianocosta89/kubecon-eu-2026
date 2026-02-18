.PHONY: help run run-attach build stop clean logs

# Default target
help:
	@echo "How Manual OTel Instrumentation Saves More Than Just Money"
	@echo ""
	@echo "Run Services (detached by default):"
	@echo "  make run spring-auto              Spring Boot with auto-instrumentation - http://localhost:8080"
	@echo "  make run express-auto             Express with auto-instrumentation - http://localhost:3000"
	@echo "  make run spring-manual            Spring Boot with manual-instrumentation - http://localhost:8081"
	@echo "  make run express-manual           Express with manual-instrumentation - http://localhost:3001"
	@echo "  make run spring-uninstrumented    Spring Boot uninstrumented - http://localhost:8082"
	@echo "  make run express-uninstrumented   Express uninstrumented - http://localhost:3002"
	@echo ""
	@echo "Run by Instrumentation Type:"
	@echo "  make run auto                     All auto-instrumented services"
	@echo "  make run manual                   All manual-instrumented services"
	@echo "  make run uninstrumented           All uninstrumented services"
	@echo "  make run all                      Everything (6 services + infra)"
	@echo ""
	@echo "Run Attached (with logs):"
	@echo "  make run-attach spring-auto       Run in foreground to watch logs"
	@echo "  make run-attach <any-service>     (Use Ctrl+C to stop)"
	@echo ""
	@echo "Build Services:"
	@echo "  make build spring-auto            Build specific service"
	@echo "  make build all                    Build all services"
	@echo ""
	@echo "Stop & Clean:"
	@echo "  make stop spring-auto             Stop specific service"
	@echo "  make stop all                     Stop all services"
	@echo "  make clean spring-auto            Stop and remove volumes"
	@echo "  make clean all                    Nuclear option (clean everything)"
	@echo ""

# Run services (detached/background - default mode)
run:
	@if [ "$(filter-out $@,$(MAKECMDGOALS))" = "spring-auto" ]; then \
		docker compose --profile spring-auto up -d; \
		echo ""; \
		echo "Spring Boot with auto-instrumentation is running on port 8080"; \
		echo "Try it: curl http://localhost:8080/songs/Polly/Nirvana | jq"; \
		echo "View logs: make logs spring-auto"; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "express-auto" ]; then \
		docker compose --profile express-auto up -d; \
		echo ""; \
		echo "Express with auto-instrumentation is running on port 3000"; \
		echo "Try it: curl http://localhost:3000/songs/Polly/Nirvana | jq"; \
		echo "View logs: make logs express-auto"; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "spring-manual" ]; then \
		docker compose --profile spring-manual up -d; \
		echo ""; \
		echo "Spring Boot with manual-instrumentation is running on port 8081"; \
		echo "Try it: curl http://localhost:8081/songs/Polly/Nirvana | jq"; \
		echo "View logs: make logs spring-manual"; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "express-manual" ]; then \
		docker compose --profile express-manual up -d; \
		echo ""; \
		echo "Express with manual-instrumentation is running on port 3001"; \
		echo "Try it: curl http://localhost:3001/songs/Polly/Nirvana | jq"; \
		echo "View logs: make logs express-manual"; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "spring-uninstrumented" ]; then \
		docker compose --profile spring-uninstrumented up -d; \
		echo ""; \
		echo "Spring Boot uninstrumented (baseline) is running on port 8082"; \
		echo "Try it: curl http://localhost:8082/songs/Polly/Nirvana | jq"; \
		echo "View logs: make logs spring-uninstrumented"; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "express-uninstrumented" ]; then \
		docker compose --profile express-uninstrumented up -d; \
		echo ""; \
		echo "Express uninstrumented (baseline) is running on port 3002"; \
		echo "Try it: curl http://localhost:3002/songs/Polly/Nirvana | jq"; \
		echo "View logs: make logs express-uninstrumented"; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "auto" ]; then \
		docker compose --profile auto up -d; \
		echo ""; \
		echo "All auto-instrumented services are running!"; \
		echo "Spring: curl http://localhost:8080/songs/Polly/Nirvana | jq"; \
		echo "Express: curl http://localhost:3000/songs/Polly/Nirvana | jq"; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "manual" ]; then \
		docker compose --profile manual up -d; \
		echo ""; \
		echo "All manual-instrumented services are running!"; \
		echo "Spring: curl http://localhost:8081/songs/Polly/Nirvana | jq"; \
		echo "Express: curl http://localhost:3001/songs/Polly/Nirvana | jq"; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "uninstrumented" ]; then \
		docker compose --profile uninstrumented up -d; \
		echo ""; \
		echo "All uninstrumented services are running!"; \
		echo "Spring: curl http://localhost:8082/songs/Polly/Nirvana | jq"; \
		echo "Express: curl http://localhost:3002/songs/Polly/Nirvana | jq"; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "all" ]; then \
		docker compose --profile auto --profile manual --profile uninstrumented up -d; \
		echo ""; \
		echo "All 6 services + infrastructure are running!"; \
		echo ""; \
		echo "Auto-instrumented:"; \
		echo "  Spring:  curl http://localhost:8080/songs/Polly/Nirvana | jq"; \
		echo "  Express: curl http://localhost:3000/songs/Polly/Nirvana | jq"; \
		echo ""; \
		echo "Manual-instrumented:"; \
		echo "  Spring:  curl http://localhost:8081/songs/Polly/Nirvana | jq"; \
		echo "  Express: curl http://localhost:3001/songs/Polly/Nirvana | jq"; \
		echo ""; \
		echo "Uninstrumented:"; \
		echo "  Spring:  curl http://localhost:8082/songs/Polly/Nirvana | jq"; \
		echo "  Express: curl http://localhost:3002/songs/Polly/Nirvana | jq"; \
		echo ""; \
		echo "Test all: make test all"; \
	else \
		echo "Usage: make run <service-name>"; \
		echo "Available services: spring-auto, express-auto, spring-manual, express-manual, spring-uninstrumented, express-uninstrumented"; \
		echo "Or use: auto, manual, uninstrumented, all"; \
	fi

# Run services (attached/foreground - watch logs)
run-attach:
	@if [ "$(filter-out $@,$(MAKECMDGOALS))" = "spring-auto" ]; then \
		docker compose --profile spring-auto up; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "express-auto" ]; then \
		docker compose --profile express-auto up; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "spring-manual" ]; then \
		docker compose --profile spring-manual up; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "express-manual" ]; then \
		docker compose --profile express-manual up; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "spring-uninstrumented" ]; then \
		docker compose --profile spring-uninstrumented up; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "express-uninstrumented" ]; then \
		docker compose --profile express-uninstrumented up; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "auto" ]; then \
		docker compose --profile auto up; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "manual" ]; then \
		docker compose --profile manual up; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "uninstrumented" ]; then \
		docker compose --profile uninstrumented up; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "all" ]; then \
		docker compose --profile auto --profile manual --profile uninstrumented up; \
	else \
		echo "Usage: make run-attach <service-name>"; \
		echo "Available services: spring-auto, express-auto, spring-manual, express-manual, spring-uninstrumented, express-uninstrumented"; \
		echo "Or use: auto, manual, uninstrumented, all"; \
		echo "Tip: Use Ctrl+C to stop"; \
	fi

# Build services
build:
	@if [ "$(filter-out $@,$(MAKECMDGOALS))" = "all" ]; then \
		docker compose build; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "" ]; then \
		echo "Usage: make build <service-name>"; \
		echo "Available: spring-auto, express-auto, spring-manual, express-manual, spring-uninstrumented, express-uninstrumented, otel-collector, all"; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "otel-collector" ]; then \
		docker compose build otel-collector; \
	else \
		docker compose build songs-$(filter-out $@,$(MAKECMDGOALS)); \
	fi

# Stop services
stop:
	@if [ "$(filter-out $@,$(MAKECMDGOALS))" = "all" ]; then \
		docker compose --profile auto --profile manual --profile uninstrumented down; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "" ]; then \
		echo "Usage: make stop <service-name>"; \
	else \
		docker compose --profile $(filter-out $@,$(MAKECMDGOALS)) down; \
	fi

# Clean (stop + remove volumes)
clean:
	@if [ "$(filter-out $@,$(MAKECMDGOALS))" = "all" ]; then \
		docker compose --profile auto --profile manual --profile uninstrumented down -v; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "" ]; then \
		echo "Usage: make clean <service-name>"; \
	else \
		docker compose --profile $(filter-out $@,$(MAKECMDGOALS)) down -v; \
	fi

# Show logs
logs:
	@if [ "$(filter-out $@,$(MAKECMDGOALS))" = "" ]; then \
		echo "Usage: make logs <service-name>"; \
	elif [ "$(filter-out $@,$(MAKECMDGOALS))" = "otel-collector" ] || [ "$(filter-out $@,$(MAKECMDGOALS))" = "jaeger" ] || [ "$(filter-out $@,$(MAKECMDGOALS))" = "songs-db" ]; then \
		docker compose logs -f $(filter-out $@,$(MAKECMDGOALS)); \
	else \
		docker compose logs -f songs-$(filter-out $@,$(MAKECMDGOALS)); \
	fi

# Dummy targets to allow service names as arguments
spring-auto express-auto spring-manual express-manual spring-uninstrumented express-uninstrumented auto manual uninstrumented all otel-collector jaeger songs-db:
	@:
