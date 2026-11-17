# syntax=docker/dockerfile:1
# Build context: this folder. Used by compose.yaml.
FROM node:24.21.0-bookworm-slim@sha256:d6aa754f16b3197301076f047b5def2f02ea1dbbc2ca920407d46d7ec7f87b20 AS web
WORKDIR /src/web
COPY web/package.json web/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --no-audit --no-fund
COPY web/ ./
RUN npm run build

FROM golang:1.27.3-trixie@sha256:1896654cfc5c2b5ad74c07f29cb36f5d2d1cbed42e3054070fbfe444e521e83c AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags "-s -w" -o /out/azurite-console .

# The docker CLI reads the access log of the azurite container through the
# Docker socket that Compose mounts.
FROM docker:29.9.1-cli@sha256:6fae2214c3121a28d5aa639d09032f61310b7c9c75ffbad1025f261a1b621800 AS docker

FROM gcr.io/distroless/static-debian13:nonroot@sha256:516757106de35205efb70b91ba03f6f1298424a0678c603255cf2852a7000087
COPY --from=docker /usr/local/bin/docker /usr/local/bin/docker
COPY --from=build /out/azurite-console /azurite-console
COPY --from=web /src/web/dist /web
USER 65532:65532
EXPOSE 28091
ENTRYPOINT ["/azurite-console"]
CMD ["-container", "-addr", ":28091", "-host", "azurite", "-azurite-port", "10000", "-web", "/web"]
