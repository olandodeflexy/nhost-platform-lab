SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

VERSION ?= dev
COMMIT ?= local
BUILD_TIME ?= unknown
LDFLAGS := -s -w \
	-X github.com/olandodeflexy/nhost-platform-lab/services/demo-api/internal/buildinfo.Version=$(VERSION) \
	-X github.com/olandodeflexy/nhost-platform-lab/services/demo-api/internal/buildinfo.Commit=$(COMMIT) \
	-X github.com/olandodeflexy/nhost-platform-lab/services/demo-api/internal/buildinfo.BuildTime=$(BUILD_TIME)

.PHONY: help test build run clean

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <target>\n\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  %-12s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

test: ## Run tests with the race detector
	go test -race -cover ./...

build: ## Build the service binary
	mkdir -p bin
	CGO_ENABLED=0 go build -trimpath -ldflags "$(LDFLAGS)" -o bin/demo-api ./cmd/demo-api

run: ## Run the service locally
	go run ./cmd/demo-api

clean: ## Remove local build output
	rm -rf bin coverage.out
