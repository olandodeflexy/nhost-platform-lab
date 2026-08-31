# The GitHub release path builds the image with Nix. This Dockerfile is retained
# as a familiar local fallback and must produce the same binary contract.
FROM golang:1.26.0-alpine AS build

ARG VERSION=dev
ARG COMMIT=unknown
ARG BUILD_TIME=unknown

WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath \
    -ldflags "-s -w -X github.com/olandodeflexy/nhost-platform-lab/services/demo-api/internal/buildinfo.Version=${VERSION} -X github.com/olandodeflexy/nhost-platform-lab/services/demo-api/internal/buildinfo.Commit=${COMMIT} -X github.com/olandodeflexy/nhost-platform-lab/services/demo-api/internal/buildinfo.BuildTime=${BUILD_TIME}" \
    -o /out/demo-api ./cmd/demo-api

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/demo-api /demo-api
EXPOSE 3000
USER nonroot:nonroot
ENTRYPOINT ["/demo-api"]
