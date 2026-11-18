# Build outputs stay in .data/, which git and scripts/validate.sh ignore.
# The Vite build must write to ../internal/webui/dist with emptyOutDir false: the
# tracked placeholder.html there keeps go:embed valid in a clean checkout.
GO ?= go
NPM ?= npm
BINARY := .data/bin/container-console-colima
DIST := internal/webui/dist

.PHONY: build web check install

## build: compile the service, with the front-end when web/package.json exists
build: web
	$(GO) build -trimpath -o $(BINARY) ./cmd/container-console-colima

## web: rebuild the embedded front-end; without web/package.json the placeholder stays
web:
	@if [ -f web/package.json ]; then \
		[ -d web/node_modules ] || $(NPM) --prefix web ci; \
		find $(DIST) -mindepth 1 ! -name placeholder.html -delete; \
		$(NPM) --prefix web run build; \
	fi

## check: format, vet and compile the service; audit and check the front-end when present
check:
	@unformatted="$$(gofmt -l cmd internal)"; \
	if [ -n "$$unformatted" ]; then echo "gofmt: $$unformatted"; exit 1; fi
	$(GO) vet ./...
	$(GO) build ./...
	@if [ -f web/package-lock.json ]; then \
		$(NPM) --prefix web audit --audit-level=high && \
		$(NPM) --prefix web run check; \
	fi

## install: build and install the launchd agent and the Dock icon
install: build
	@if [ ! -f macos/install-console.sh ]; then echo "macos/install-console.sh does not exist yet"; exit 1; fi
	bash macos/install-console.sh
