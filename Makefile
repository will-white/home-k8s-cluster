# Makefile for convenient commands
# This is a simple wrapper around Task for discoverability
# Use 'make help' to see available commands

.PHONY: help
help: ## Show this help message
	@echo "Available commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "For full task list, run: task --list"

.PHONY: validate
validate: ## Validate all Kubernetes manifests
	@echo "🔍 Running validation..."
	@./scripts/validate-before-commit.sh

.PHONY: validate-app
validate-app: ## Validate specific app (usage: make validate-app NAMESPACE=media APP=bazarr)
	@if [ -z "$(NAMESPACE)" ] || [ -z "$(APP)" ]; then \
		echo "❌ Error: NAMESPACE and APP required"; \
		echo "Usage: make validate-app NAMESPACE=media APP=bazarr"; \
		exit 1; \
	fi
	@./scripts/validate-app.sh $(NAMESPACE) $(APP)

.PHONY: scaffold
scaffold: ## Generate new app scaffold (usage: make scaffold APP=bazarr NAMESPACE=media)
	@if [ -z "$(APP)" ] || [ -z "$(NAMESPACE)" ]; then \
		echo "❌ Error: APP and NAMESPACE required"; \
		echo "Usage: make scaffold APP=bazarr NAMESPACE=media"; \
		exit 1; \
	fi
	@./scripts/generate-app-scaffold.sh $(APP) $(NAMESPACE)

.PHONY: repo-map
repo-map: ## Generate repository structure map
	@./scripts/generate-repo-map.sh

.PHONY: lint
lint: ## Run YAML linting
	@echo "🔍 Running yamllint..."
	@yamllint -s kubernetes/ || echo "⚠️  yamllint not installed"

.PHONY: kubeconform
kubeconform: ## Validate Kubernetes manifests with kubeconform
	@echo "🔍 Running kubeconform..."
	@task kubernetes:kubeconform

.PHONY: flux-diff
flux-diff: ## Show what would change if applied (requires cluster access)
	@echo "🔍 Running flux diff..."
	@flux diff kustomization cluster --path ./kubernetes/flux

.PHONY: pre-commit-install
pre-commit-install: ## Install pre-commit hooks
	@if command -v pre-commit &> /dev/null; then \
		pre-commit install; \
		echo "✅ Pre-commit hooks installed"; \
	else \
		echo "❌ pre-commit not found. Install with: pip install pre-commit"; \
		exit 1; \
	fi

.PHONY: pre-commit-run
pre-commit-run: ## Run pre-commit hooks on all files
	@pre-commit run --all-files

.PHONY: setup
setup: ## Initial setup - install pre-commit hooks
	@echo "🔧 Setting up development environment..."
	@$(MAKE) pre-commit-install
	@echo "✅ Setup complete!"
	@echo ""
	@echo "Quick start:"
	@echo "  make validate              - Validate all manifests"
	@echo "  make scaffold APP=x NS=y   - Generate app scaffold"
	@echo "  make help                  - Show all commands"

.PHONY: clean
clean: ## Clean temporary files and caches
	@echo "🧹 Cleaning temporary files..."
	@find . -type f -name "*.pyc" -delete
	@find . -type d -name "__pycache__" -delete
	@find . -type d -name ".pytest_cache" -delete
	@rm -rf .task .pre-commit-cache
	@echo "✅ Cleanup complete"

.DEFAULT_GOAL := help
