# Shared PostgreSQL for the workspace apps. Apps call bin/ensure-db themselves;
# these targets are for people.
DB ?=
ROLE ?= reader

.PHONY: up local ensure psql backup selftest status down

up: ## Start the shared container (does nothing if it is already running)
	bin/ensure-db --server-only

local: ## Also publish it on 127.0.0.1:5433 for local tools and native tests
	cp compose.local.yaml compose.override.yaml
	docker compose up -d --wait
	@echo "PostgreSQL on 127.0.0.1:$${POSTGRES_PORT:-5433}. Undo: rm compose.override.yaml && make up"

ensure: ## Create or repair one app database: make ensure DB=rental_review
	@test -n "$(DB)" || { echo "Usage: make ensure DB=<database>" >&2; exit 2; }
	bin/ensure-db $(DB)

psql: ## Open psql: make psql DB=rental_review ROLE=reader|writer|owner|admin
	@test -n "$(DB)$(filter admin,$(ROLE))" || { echo "Usage: make psql DB=<database> [ROLE=reader]" >&2; exit 2; }
	@if [ "$(ROLE)" = admin ]; then \
		docker exec -it shared-postgres psql -U platform_admin -d $${DB:-postgres}; \
	else \
		docker exec -it shared-postgres psql -U $(DB)_$(ROLE) -d $(DB); \
	fi

backup: ## Dump every app database to ~/postgres-backups
	bin/backup

selftest: ## Prove the role permissions on throwaway databases
	bin/selftest

status: ## Show the container and its databases
	docker ps --filter name=shared-postgres --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
	docker exec shared-postgres psql -U platform_admin -d postgres -c '\l'

down: ## Stop the container. Data stays in the postgres-platform_data volume.
	docker compose stop
