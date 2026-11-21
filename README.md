# postgres-platform

One PostgreSQL server (`postgres:18.6-bookworm`, the same version as meal-manager) shared by
the workspace apps: **rental-review** and **wardrobe-manager**. It runs as the Docker
container `shared-postgres` on the network `shared-postgres`, locally and on the Google Cloud
VM.

**Requirements:** Docker with Compose, and **Python 3.13** for the `bin/` scripts (standard
library only). The VM's Debian 13 `python3` is 3.13; on a Mac, run
`brew install python@3.13`.

Apps don't start it themselves. Their `make up` and deploy scripts expect this repo next to
them (`../postgres-platform`, or `~/postgres-platform` on the VM), clone it if it's missing, and
run:

```sh
../postgres-platform/bin/ensure-db rental_review
```

`ensure-db` is safe to run any number of times:

1. It starts the container only if it isn't already running and healthy.
2. It creates the database and its roles only if they are missing, and keeps existing
   passwords.
3. It re-applies the grants, so any drift is repaired.
4. It (re)writes the app's credentials files.

## Roles

| Role | Can | Used by |
| --- | --- | --- |
| `platform_admin` (superuser) | Everything | `ensure-db`, backups, manual admin. Never given to apps. |
| `<db>_owner` | Owns the database and schema: create, alter and drop tables | Migrations (Alembic) |
| `<db>_writer` | `SELECT`, `INSERT`, `UPDATE`, `DELETE`; use sequences | The running API and workers |
| `<db>_reader` | `SELECT` only | People and tools (psql, TablePlus, reports) |

- **Isolation:** each database has `CONNECT` revoked from `PUBLIC` and granted only to its own
  three roles. No app role can reach another app's database or the `postgres` maintenance
  database, and none is a superuser or can create roles or databases.
- **New tables:** default privileges give the writer and reader access to tables the owner
  creates later, so migrations don't have to grant anything.
- **Proof:** `make selftest` checks all of this on throwaway databases.

## Passwords and credentials

All passwords are generated on the machine running the container. They're never stored in
Git or CI, and are only readable by you (mode 600).

| File | Contents | Used by |
| --- | --- | --- |
| `.env` | `POSTGRES_ADMIN_PASSWORD` (superuser) | This repo's Compose file |
| `credentials/<db>.secret` | Owner, writer and reader passwords. **The source of truth.** | `ensure-db` |
| `credentials/<db>.env` | `DATABASE_URL` (writer) and `READ_DATABASE_URL` (reader) | The app at runtime, via Compose `env_file` |
| `credentials/<db>.migrate.env` | `MIGRATION_DATABASE_URL` (owner) | The app's migration step only |

- **Rotating a password:** delete its line from `<db>.secret`, run `ensure-db <db>`, then
  restart the app.
- **Hostnames:** the URLs use the host `shared-postgres` (inside Docker). For tools on your
  Mac, run `make local`, then use `127.0.0.1:5433` with the same user and password.

## Commands

| Command | What it does |
| --- | --- |
| `make up` | Start the container if it isn't running |
| `make local` | Also publish it on `127.0.0.1:5433` (local only) |
| `make ensure DB=rental_review` | Create or repair one app's database |
| `make psql DB=rental_review ROLE=reader` | Open psql as a role (`reader`, `writer`, `owner` or `admin`) |
| `bin/import-dump <db> <file.dump>` | Restore a `pg_dump -Fc` file into an empty app database |
| `make backup` | Dump every app database to `~/postgres-backups/<db>/<time>.dump`, keeping 14 days |
| `make selftest` | Prove the role permissions |
| `make down` | Stop the container. The data volume `postgres-platform_data` is kept. |
| `make colima_up` | Mac: start the shared Colima VM if it is stopped, and make it the Docker context |
| `make colima_down` | Mac: stop the whole Colima VM (every app and this container). Data is kept. |
| `make colima_resize` | Mac: restart the VM to apply `COLIMA_MEMORY` / `COLIMA_CPUS` (default 8 GiB / 4 CPUs) |

On the VM, run backups daily from cron:

```cron
17 3 * * * $HOME/postgres-platform/bin/backup >> $HOME/postgres-backups/backup.log 2>&1
```

## Adding an app

1. In the app's Makefile and deploy script, run `ensure-db <db>` before starting it.
2. Join the external network `shared-postgres`.
3. Load `credentials/<db>.env` into the API and workers, and `credentials/<db>.migrate.env`
   into the migration step.

## Local Docker note

On a Mac with several Colima profiles, each profile is a separate Docker daemon. Apps share
this container only when they run on the same daemon. Run them in one profile to share it;
otherwise each daemon gets its own `shared-postgres`.
This repo owns that VM: `make colima_up`, `colima_down` and `colima_resize` start, stop and resize the
`default` profile (override with `COLIMA_PROFILE`). The apps' `make full_up` calls `colima_up`
here, which never restarts a running VM; stopping or resizing it is done only from this repo,
because it affects every app.
