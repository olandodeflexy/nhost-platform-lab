SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

.PHONY: help check public-surface test build image manifests fmt infra-fmt

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <target>\n\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  %-16s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

check: public-surface test manifests infra-fmt ## Run the local checks available without AWS

public-surface: ## Reject sensitive or deployment-specific data from Git-addable files
	./scripts/check-public-surface.sh

test: ## Run Go tests
	$(MAKE) -C services/demo-api test

build: ## Build the Go service
	$(MAKE) -C services/demo-api build

image: ## Build the OCI archive with Nix
	nix build .#demo-api-image

manifests: ## Render and validate every Kustomize overlay
	./scripts/check-manifests.sh

fmt: ## Format Go, Terraform, Terragrunt, and Nix files
	gofmt -w services/demo-api
	terraform fmt -recursive infra
	terragrunt hcl fmt --working-dir infra/live --exclude-dir .terraform
	@if command -v alejandra >/dev/null 2>&1; then alejandra flake.nix services/demo-api/project.nix; fi

infra-fmt: ## Check Terraform and Terragrunt formatting
	terraform fmt -check -recursive infra
	terragrunt hcl fmt --check --working-dir infra/live --exclude-dir .terraform

.PHONY: infra-validate

infra-validate: ## Initialize and validate every Terraform root
	./scripts/validate-terraform.sh
