SHELL := /bin/sh

.PHONY: dev dev-down up down build logs test migrate-up clean

COMPOSE_DEV := docker compose --env-file .env -f compose.dev.yaml

OPENAPI_CLI_VERSION := 1.34.3

dev:
	docker compose --env-file .env -f compose.dev.yaml up --build

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

#check: api-test web-test smoke

.PHONY: api-format api-fmt-check api-vet api-test web-test web-build smoke check

api-format:
	$(COMPOSE_DEV) run --rm --no-deps api sh -c 'find . -name "*.go" -type f -exec gofmt -w {} +'

api-fmt-check:
	@files="$$( $(COMPOSE_DEV) run --rm --no-deps api sh -c 'find . -name "*.go" -type f -exec gofmt -l {} +' )"; \
	if [ -n "$$files" ]; then \
		echo "The following Go files need formatting:"; \
		echo "$$files"; \
		exit 1; \
	fi

api-vet:
	$(COMPOSE_DEV) run --rm --no-deps api go vet ./...

api-test:
	$(COMPOSE_DEV) run --rm --no-deps api go test ./...


web-test:
	$(COMPOSE_DEV) run --rm --no-deps web npm run test

web-build:
	$(COMPOSE_DEV) run --rm --no-deps web npm run build

smoke:
	./scripts/smoke-test.sh

check: openapi-lint api-fmt-check api-vet api-test web-test web-build smoke

.PHONY: openapi-lint

openapi-lint:
	docker run --rm \
		--volume "$(CURDIR):/workspace" \
		--workdir /workspace \
		node:22-alpine \
		npx --yes @redocly/cli@$(OPENAPI_CLI_VERSION) lint api/openapi.yaml

HELM_RELEASE ?= trade-journal
HELM_NAMESPACE ?= trade-journal
HELM_CHART ?= deploy/helm/trade-journal
HELM_VALUES ?= deploy/helm/trade-journal/values-k3s.yaml

.PHONY: helm-lint helm-template helm-install helm-status helm-uninstall

helm-lint:
	@helm lint $(HELM_CHART) \
		--values $(HELM_VALUES) \
		--set-string database.password=validation-only


helm-template:
	@helm template $(HELM_RELEASE) $(HELM_CHART) \
		--namespace $(HELM_NAMESPACE) \
		--values $(HELM_VALUES) \
		--set-string database.password=validation-only

helm-install:
	@test -n "$(DATABASE_PASSWORD)" || \
		(echo "DATABASE_PASSWORD is required" && exit 1)
	helm upgrade --install $(HELM_RELEASE) $(HELM_CHART) \
		--namespace $(HELM_NAMESPACE) \
		--create-namespace \
		--values $(HELM_VALUES) \
		--set-string database.password="$(DATABASE_PASSWORD)" \
		--wait \
		--wait-for-jobs \
		--timeout 10m

helm-status:
	helm status $(HELM_RELEASE) \
		--namespace $(HELM_NAMESPACE)
	kubectl get pods,services,ingress,pvc,jobs \
		--namespace $(HELM_NAMESPACE)

helm-uninstall:
	helm uninstall $(HELM_RELEASE) \
		--namespace $(HELM_NAMESPACE)

