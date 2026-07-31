.PHONY: all up setup vexa-up app-up app-restart rebuild down stop logs status ps

COLOR_RESET=\033[0m
COLOR_TITLE=\033[1;36m
COLOR_OK=\033[1;32m

# The Vexa gateway container name (set by COMPOSE_PROJECT_NAME=vexa-v012 in vexa/.env)
VEXA_GATEWAY_CONTAINER ?= vexa-v012-gateway-1

all: up
up:
	@printf "$(COLOR_TITLE)[meetingmind] Bootstrapping full stack...$(COLOR_RESET)\n"
	@$(MAKE) vexa-up
	@$(MAKE) app-up
	@printf "$(COLOR_OK)[meetingmind] All services started.$(COLOR_RESET)\n"

# Start Vexa only if the gateway isn't already running.
# This prevents a new API key from being minted on every `make all`.
vexa-up:
	@if docker ps --format '{{.Names}}' | grep -q "^$(VEXA_GATEWAY_CONTAINER)$$"; then \
		printf "$(COLOR_OK)[vexa] Already running — skipping bootstrap (no new API key minted).$(COLOR_RESET)\n"; \
	else \
		printf "$(COLOR_TITLE)[vexa] Starting sensor zone...$(COLOR_RESET)\n"; \
		$(MAKE) -C vexa all COMPOSE="docker compose -p vexa-v012 -f docker-compose.yml -f ../../../vexa.override.yml --env-file ../../.env"; \
		printf "$(COLOR_OK)[vexa] Sensor zone up.$(COLOR_RESET)\n"; \
	fi

app-up:
	@printf "$(COLOR_TITLE)[app] Starting core platform...$(COLOR_RESET)\n"
	docker compose up -d --remove-orphans
	@printf "$(COLOR_OK)[app] Core platform up.$(COLOR_RESET)\n"

app-restart:
	@printf "$(COLOR_TITLE)[app] Restarting core platform...$(COLOR_RESET)\n"
	docker compose restart backend frontend
	@printf "$(COLOR_OK)[app] Core platform restarted.$(COLOR_RESET)\n"

setup:
	@printf "$(COLOR_TITLE)[meetingmind] Running cold start setup...$(COLOR_RESET)\n"
	./setup.sh
	@printf "$(COLOR_OK)[meetingmind] Setup finished.$(COLOR_RESET)\n"

rebuild:
	@printf "$(COLOR_TITLE)[meetingmind] Rebuilding MeetingMind core images...$(COLOR_RESET)\n"
	docker compose up -d --build --remove-orphans
	@printf "$(COLOR_TITLE)[vexa] Restarting/Rebuilding Vexa...$(COLOR_RESET)\n"
	docker compose -p vexa-v012 -f vexa/deploy/compose/docker-compose.yml -f vexa.override.yml --env-file vexa/.env up -d --build --remove-orphans
	@printf "$(COLOR_OK)[meetingmind] Rebuild complete.$(COLOR_RESET)\n"

down:
	@printf "$(COLOR_TITLE)[meetingmind] Shutting down all services...$(COLOR_RESET)\n"
	docker compose down
	docker compose -f vexa/deploy/compose/docker-compose.yml -f vexa.override.yml down
	@printf "$(COLOR_OK)[meetingmind] All services stopped.$(COLOR_RESET)\n"

stop: down

logs:
	@printf "$(COLOR_TITLE)[app] Tailing backend logs...$(COLOR_RESET)\n"
	docker compose logs -f backend

status:
	@printf "$(COLOR_TITLE)[app] Service status...$(COLOR_RESET)\n"
	docker compose ps
	@printf "$(COLOR_TITLE)[vexa] Service status...$(COLOR_RESET)\n"
	docker compose -f vexa/deploy/compose/docker-compose.yml -f vexa.override.yml ps

ps: status
