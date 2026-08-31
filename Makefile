# Hermetic repro interface. Requires Git + Docker Compose v2.
DOCKER_BUILDKIT ?= 1
export DOCKER_BUILDKIT
COMPOSE := docker compose
REV_SKILLS := vendor/rev-skills

.PHONY: setup up down clean rebuild test check

setup:
	@if [ ! -f $(REV_SKILLS)/validate.mjs ]; then git submodule update --init --recursive; fi
	@if [ ! -f .env ]; then cp .env.example .env; fi

up: setup
	$(COMPOSE) up -d --build --wait

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down -v

rebuild: setup
	$(COMPOSE) build --no-cache --pull

# Acceptance: real upstream validate + unit tests + installer dry-run.
test: setup
	$(COMPOSE) run --rm --build app sh -c 'npm test && node bin/install.mjs --dry-run --project --target all'

# Same gate on the host Node (not hermetic; useful while iterating).
check: setup
	cd $(REV_SKILLS) && npm test
	cd $(REV_SKILLS) && node bin/install.mjs --dry-run --project --target all
