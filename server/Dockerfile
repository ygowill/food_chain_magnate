FROM debian:bookworm-slim

ARG GODOT_TAG="4.5.1-stable"
ARG TARGETARCH

# Godot (Linux editor build) depends on a few runtime libraries even when running with --headless.
RUN apt-get update && apt-get install -y --no-install-recommends \
	ca-certificates \
	curl \
	unzip \
	libasound2 \
	libfontconfig1 \
	libgl1 \
	libx11-6 \
	libxcursor1 \
	libxi6 \
	libxinerama1 \
	libxrandr2 \
	&& rm -rf /var/lib/apt/lists/*

RUN case "${TARGETARCH}" in \
		amd64) godot_arch="x86_64" ;; \
		arm64) godot_arch="arm64" ;; \
		*) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
	esac \
	&& curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_TAG}/Godot_v${GODOT_TAG}_linux.${godot_arch}.zip" \
	&& unzip -q /tmp/godot.zip -d /tmp/godot \
	&& mv "/tmp/godot/Godot_v${GODOT_TAG}_linux.${godot_arch}" /usr/local/bin/godot \
	&& chmod +x /usr/local/bin/godot \
	&& rm -rf /tmp/godot /tmp/godot.zip

WORKDIR /app
COPY . /app

RUN chmod +x /app/server/entrypoint.sh \
	&& useradd -m godot \
	&& chown -R godot:godot /app

USER godot

ENV PORT=7000
ENV BIND=*

EXPOSE 7000

ENTRYPOINT ["/app/server/entrypoint.sh"]
