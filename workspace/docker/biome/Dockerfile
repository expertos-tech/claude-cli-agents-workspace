# Image of the typescript check in scripts/validate.sh: only the static Biome binary, without the Alpine packages of the official image.
FROM ghcr.io/biomejs/biome:2.6.4@sha256:7ca467dc36a0773e8bb92c169a40725c5f5cd0018b034e6b2bb6a991e337cedf AS source

FROM scratch
COPY --from=source /usr/local/bin/biome /biome
USER 65534:65534
ENTRYPOINT ["/biome"]
