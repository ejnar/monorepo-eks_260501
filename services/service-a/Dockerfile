# =============================================================================
# Monorepo — service-a Dockerfile
# Build context: repo root  →  docker build -f services/service-a/Dockerfile .
# =============================================================================

# ─────────────────────────────────────────────
# Stage 1 — Dependency cache
# Copies only Gradle descriptor files first so
# the dependency layer is reused on src changes
# ─────────────────────────────────────────────
# FROM --platform=linux/amd64 eclipse-temurin:21-jdk-alpine AS deps
FROM eclipse-temurin:21-jdk AS deps
WORKDIR /workspace

# Gradle wrapper + root build files (layer changes rarely)
COPY gradlew                                    ./gradlew
COPY gradle/                                    ./gradle/
COPY settings.gradle                            ./settings.gradle
COPY build.gradle                               ./build.gradle

# Service-specific build descriptor only (no source yet)
COPY services/service-a/build.gradle            ./services/service-a/build.gradle

RUN chmod +x ./gradlew \
 && ./gradlew :services:service-a:dependencies --no-daemon --quiet

# ─────────────────────────────────────────────
# Stage 2 — Build
# Source is copied after deps so cache is valid
# as long as descriptors don't change
# ─────────────────────────────────────────────
FROM deps AS builder

COPY services/service-a/src ./services/service-a/src

RUN ./gradlew :services:service-a:bootJar --no-daemon \
 && ls -lh services/service-a/build/libs/

# ─────────────────────────────────────────────
# Stage 3 — Runtime
# Minimal JRE image, non-root user, hardened
# ─────────────────────────────────────────────
# FROM --platform=linux/amd64 eclipse-temurin:21-jre-alpine AS runtime
FROM eclipse-temurin:21-jre-alpine AS runtime
WORKDIR /app

# curl needed for HEALTHCHECK (not always present in jre-alpine)
RUN apk add --no-cache curl \
 && addgroup -S appgroup \
 && adduser  -S appuser -G appgroup

# Correct path: /workspace/services/service-a/build/libs/
COPY --from=builder \
     /workspace/services/service-a/build/libs/service-a.jar \
     app.jar

RUN chown appuser:appgroup app.jar

USER appuser

EXPOSE 8080

HEALTHCHECK \
  --interval=30s \
  --timeout=10s  \
  --start-period=40s \
  --retries=3 \
  CMD curl -sf http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", \
  "-XX:+UseContainerSupport", \
  "-XX:MaxRAMPercentage=75.0", \
  "-Djava.security.egd=file:/dev/./urandom", \
  "-jar", "app.jar"]