# syntax=docker/dockerfile:1.7
FROM golang:1.22-alpine AS build
WORKDIR /src

# Separate layer so module cache survives source changes.
COPY go.mod ./
RUN go mod download

COPY . .
ARG VERSION=dev
# CGO_ENABLED=0 produces a fully static binary — no libc, runs on distroless/static.
RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w -X main.version=${VERSION}" \
    -o /out/orders-api .

FROM gcr.io/distroless/static:nonroot
WORKDIR /
COPY --from=build /out/orders-api /orders-api
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/orders-api"]
