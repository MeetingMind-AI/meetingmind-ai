.PHONY: all vexa-up app-up down stop logs status ps

COLOR_RESET=\033[0m
COLOR_TITLE=\033[1;36m
COLOR_OK=\033[1;32m

all:
	@printf "$(COLOR_TITLE)[meetingmind] Bootstrapping full stack...$(COLOR_RESET)\n"
	@$(MAKE) vexa-up
	@$(MAKE) app-up
	@printf "$(COLOR_OK)[meetingmind] All services started.$(COLOR_RESET)\n"

vexa-up:
	@printf "$(COLOR_TITLE)[vexa] Starting sensor zone...$(COLOR_RESET)\n"
	@$(MAKE) -C vexa all
	@printf "$(COLOR_OK)[vexa] Sensor zone up.$(COLOR_RESET)\n"

app-up:
	@printf "$(COLOR_TITLE)[app] Starting core platform...$(COLOR_RESET)\n"
	docker compose up -d
	@printf "$(COLOR_OK)[app] Core platform up.$(COLOR_RESET)\n"

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
