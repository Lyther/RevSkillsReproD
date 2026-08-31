# Hermetic repro interface. Product entry is npm test (src/repro.mjs).
DOCKER_BUILDKIT ?= 1
export DOCKER_BUILDKIT
COMPOSE := docker compose
REV_SKILLS := vendor/rev-skills

.PHONY: setup install overlay bump-upstream up down clean rebuild test check probe-llm live-skill remote-repro

setup:
	@if [ ! -f $(REV_SKILLS)/validate.mjs ]; then git submodule update --init --recursive; fi
	@if [ ! -f .env ]; then cp .env.example .env; fi

install: setup
	node src/repro.mjs install

overlay: setup
	./scripts/apply-overlay.sh

bump-upstream:
	./scripts/bump-upstream.sh $(REF)

up: setup
	$(COMPOSE) up -d --build --wait

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down -v

rebuild: setup
	$(COMPOSE) build --no-cache --pull

test: setup
	$(COMPOSE) run --rm --build app npm run test:repro

check: setup
	npm test

probe-llm:
	./scripts/probe-llm.sh

live-skill:
	./scripts/live-skill.sh

remote-repro:
	./scripts/remote-repro.sh
