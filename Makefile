# Shared PostgreSQL for the workspace apps. Apps call bin/ensure-db themselves;
# these targets are for people.
DB ?=
ROLE ?= reader
# Local Mac only: one Colima VM for every workspace app, so they share one shared-postgres.
COLIMA ?= colima
COLIMA_PROFILE ?= default
COLIMA_MEMORY ?= 8
COLIMA_CPUS ?= 4
COLIMA_CONTEXT = $(if $(filter default,$(COLIMA_PROFILE)),colima,colima-$(COLIMA_PROFILE))
COLIMA_START = $(COLIMA) start --profile "$(COLIMA_PROFILE)" --memory "$(COLIMA_MEMORY)" --cpus "$(COLIMA_CPUS)"

.PHONY: up local ensure psql backup selftest status down check-colima colima_up colima_running colima_down colima_resize

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

check-colima:
	@command -v $(COLIMA) > /dev/null 2>&1 || { echo "Colima is not installed. Use Docker Desktop or another engine with the apps' make up/down." >&2; exit 1; }

colima_up: check-colima ## Start the shared Colima VM if it is stopped (never restarts it) and make it the Docker context
	@$(COLIMA) status --profile "$(COLIMA_PROFILE)" > /dev/null 2>&1 || $(COLIMA_START)
	@docker context use $(COLIMA_CONTEXT) > /dev/null

colima_running: check-colima ## Exit 0 if the shared Colima VM is running (for the apps' full_down)
	@$(COLIMA) status --profile "$(COLIMA_PROFILE)" > /dev/null 2>&1

colima_down: check-colima ## Stop the whole Colima VM: every app and shared-postgres. Data is kept.
	$(COLIMA) stop --profile "$(COLIMA_PROFILE)"

colima_resize: check-colima ## Restart the VM with COLIMA_MEMORY / COLIMA_CPUS (stops every app in it)
	$(COLIMA) stop --profile "$(COLIMA_PROFILE)"
	$(COLIMA_START)
	docker context use $(COLIMA_CONTEXT)
