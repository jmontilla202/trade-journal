SHELL := /bin/sh

.PHONY: dev dev-down up down build logs test migrate-up clean

dev:
	docker compose --env-file .env -f compose.dev.yaml up --build
#dev:
#	docker compose \
		--env-file .env \
		-f compose.dev.yaml \
		up \
		--build \
		postgres \
		migrate \
		api
dev-down:
	docker compose --env-file .env -f compose.dev.yaml down

up:
	docker compose --env-file .env up --build -d

down:
	docker compose --env-file .env down

build:
	docker compose --env-file .env build

logs:

	docker compose --env-file .env logs -f

test:
	docker compose --env-file .env -f compose.dev.yaml run --rm api go test ./...

migrate-up:
	docker compose --env-file .env -f compose.dev.yaml run --rm migrate

clean:
	docker compose --env-file .env down --volumes --remove-orphans
	docker compose --env-file .env -f compose.dev.yaml down --volumes --remove-orphans

.PHONY: check smoke api-test web-test

api-test:
	docker compose \
		--env-file .env \
		-f compose.dev.yaml \
		run \
		--rm \
		--no-deps \
		api \
		go test ./...

web-test:
	docker compose \
		--env-file .env \
		-f compose.dev.yaml \
		run \
		--rm \
		--no-deps \
		web \
		npm run test

smoke:
	./scripts/smoke-test.sh

check: api-test web-test smoke

