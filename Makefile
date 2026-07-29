.PHONY: all vexa-up app-up app-restart down stop logs status ps

COLOR_RESET=\033[0m
COLOR_TITLE=\033[1;36m
COLOR_OK=\033[1;32m

# The Vexa gateway container name (set by COMPOSE_PROJECT_NAME=vexa-v012 in vexa/.env)
VEXA_GATEWAY_CONTAINER ?= vexa-v012-gateway-1

all:
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
		$(MAKE) -C vexa all; \
		printf "$(COLOR_OK)[vexa] Sensor zone up.$(COLOR_RESET)\n"; \
	fi

app-up:
	@printf "$(COLOR_TITLE)[app] Starting core platform...$(COLOR_RESET)\n"
	docker compose up -d
	@printf "$(COLOR_OK)[app] Core platform up.$(COLOR_RESET)\n"

# Restart only the app stack (backend + frontend) — does NOT touch Vexa or mint a new key.
app-restart:
	@printf "$(COLOR_TITLE)[app] Restarting core platform...$(COLOR_RESET)\n"
	docker compose restart backend frontend
	@printf "$(COLOR_OK)[app] Core platform restarted.$(COLOR_RESET)\n"

down:
	@printf "$(COLOR_TITLE)[meetingmind] Shutting down all services...$(COLOR_RESET)\n"
	docker compose down
	docker compose -f vexa/deploy/compose/docker-compose.yml down
	@printf "$(COLOR_OK)[meetingmind] All services stopped.$(COLOR_RESET)\n"

stop: down

logs:
	@printf "$(COLOR_TITLE)[app] Tailing backend logs...$(COLOR_RESET)\n"
	docker compose logs -f backend

status:
	@printf "$(COLOR_TITLE)[app] Service status...$(COLOR_RESET)\n"
	docker compose ps
	@printf "$(COLOR_TITLE)[vexa] Service status...$(COLOR_RESET)\n"
	docker compose -f vexa/deploy/compose/docker-compose.yml ps

ps: status
