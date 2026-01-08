# Juice Framework - Development Utilities
# ========================================

.PHONY: help
.DEFAULT_GOAL := help

# Colors for output
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RESET := \033[0m

# ============================================================================
# HELP
# ============================================================================

help: ## Show this help message
	@echo ""
	@echo "$(CYAN)Juice Framework - Development Utilities$(RESET)"
	@echo "=========================================="
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""

# ============================================================================
# QUALITY - Formatting & Analysis
# ============================================================================

format: ## Format all Dart files
	@echo "$(CYAN)Formatting Dart files...$(RESET)"
	dart format lib/ test/ example/lib/ example/test/

format-check: ## Check formatting without changes
	@echo "$(CYAN)Checking Dart formatting...$(RESET)"
	dart format --set-exit-if-changed lib/ test/ example/lib/ example/test/

analyze: ## Run Flutter analyzer on all code
	@echo "$(CYAN)Analyzing code...$(RESET)"
	flutter analyze

analyze-lib: ## Analyze only the core library
	@echo "$(CYAN)Analyzing lib/...$(RESET)"
	flutter analyze lib/

analyze-example: ## Analyze only the example app
	@echo "$(CYAN)Analyzing example/...$(RESET)"
	cd example && flutter analyze

lint: format analyze ## Format and analyze all code

# ============================================================================
# TESTING - Unit & Integration Tests
# ============================================================================

test: ## Run all tests (lib + example)
	@echo "$(CYAN)Running all tests...$(RESET)"
	flutter test
	cd example && flutter test

test-lib: ## Run core library tests only
	@echo "$(CYAN)Running library tests...$(RESET)"
	flutter test

test-example: ## Run example app tests only
	@echo "$(CYAN)Running example tests...$(RESET)"
	cd example && flutter test

test-coverage: ## Run tests with coverage report
	@echo "$(CYAN)Running tests with coverage...$(RESET)"
	flutter test --coverage
	@echo "$(GREEN)Coverage report generated at coverage/lcov.info$(RESET)"

test-bloc: ## Run BLoC-specific tests
	@echo "$(CYAN)Running BLoC tests...$(RESET)"
	flutter test test/bloc/

test-ui: ## Run UI widget tests
	@echo "$(CYAN)Running UI tests...$(RESET)"
	flutter test test/ui/

test-navigation: ## Run navigation/aviator tests
	@echo "$(CYAN)Running navigation tests...$(RESET)"
	flutter test test/navigation/

# ============================================================================
# BUILD - Compilation & Dependencies
# ============================================================================

deps: ## Get all dependencies
	@echo "$(CYAN)Getting dependencies...$(RESET)"
	flutter pub get
	cd example && flutter pub get

deps-upgrade: ## Upgrade all dependencies
	@echo "$(CYAN)Upgrading dependencies...$(RESET)"
	flutter pub upgrade
	cd example && flutter pub upgrade

deps-outdated: ## Check for outdated dependencies
	@echo "$(CYAN)Checking for outdated packages...$(RESET)"
	flutter pub outdated
	@echo ""
	@echo "$(YELLOW)Example app:$(RESET)"
	cd example && flutter pub outdated

build-example: ## Build example app (debug)
	@echo "$(CYAN)Building example app...$(RESET)"
	cd example && flutter build apk --debug

build-example-release: ## Build example app (release)
	@echo "$(CYAN)Building example app (release)...$(RESET)"
	cd example && flutter build apk --release

# ============================================================================
# DEVELOPMENT - Quick Commands
# ============================================================================

run: ## Run the example app
	@echo "$(CYAN)Running example app...$(RESET)"
	cd example && flutter run

clean: ## Clean build artifacts
	@echo "$(CYAN)Cleaning build artifacts...$(RESET)"
	flutter clean
	cd example && flutter clean
	rm -rf coverage/

watch: ## Watch and run tests on file changes
	@echo "$(CYAN)Watching for changes...$(RESET)"
	flutter test --watch

# ============================================================================
# CI/CD - Continuous Integration
# ============================================================================

ci: format-check analyze test ## Run full CI pipeline (format check, analyze, test)
	@echo "$(GREEN)CI pipeline completed successfully!$(RESET)"

pre-commit: format analyze test ## Run pre-commit checks (format, analyze, test)
	@echo "$(GREEN)Pre-commit checks passed!$(RESET)"

# ============================================================================
# DOCUMENTATION & INFO
# ============================================================================

stats: ## Show project statistics
	@echo ""
	@echo "$(CYAN)Juice Framework - Project Statistics$(RESET)"
	@echo "======================================="
	@echo ""
	@echo "$(YELLOW)Dart Files:$(RESET)"
	@echo "  lib/           $$(find lib -name '*.dart' | wc -l | tr -d ' ') files"
	@echo "  test/          $$(find test -name '*.dart' | wc -l | tr -d ' ') files"
	@echo "  example/lib/   $$(find example/lib -name '*.dart' | wc -l | tr -d ' ') files"
	@echo "  example/test/  $$(find example/test -name '*.dart' | wc -l | tr -d ' ') files"
	@echo "  ─────────────────────────"
	@echo "  Total:         $$(find . -name '*.dart' -not -path './.dart_tool/*' | wc -l | tr -d ' ') files"
	@echo ""
	@echo "$(YELLOW)Lines of Code:$(RESET)"
	@echo "  lib/           $$(find lib -name '*.dart' -exec cat {} + | wc -l | tr -d ' ') lines"
	@echo "  test/          $$(find test -name '*.dart' -exec cat {} + | wc -l | tr -d ' ') lines"
	@echo "  example/       $$(find example -name '*.dart' -exec cat {} + | wc -l | tr -d ' ') lines"
	@echo ""

tree-lib: ## Show lib/ directory structure
	@echo "$(CYAN)Library Structure:$(RESET)"
	@tree lib/ -I '*.g.dart' 2>/dev/null || find lib -type f -name '*.dart' | sort

tree-example: ## Show example/ directory structure
	@echo "$(CYAN)Example App Structure:$(RESET)"
	@tree example/lib/ -I '*.g.dart' 2>/dev/null || find example/lib -type f -name '*.dart' | sort

version: ## Show package version
	@grep '^version:' pubspec.yaml

# ============================================================================
# ROLLUPS - Concatenated Dart Files for Upload
# ============================================================================

ROLLUPS_DIR := rollups

# Helper to concatenate files into a rollup (only if files exist)
define make_rollup
	@files="$(3)"; \
	if [ -n "$$files" ] && [ "$$(echo $$files | wc -w | tr -d ' ')" -gt 0 ]; then \
		echo "// ROLLUP: $(2)" > $(1); \
		echo "// Files: $$(echo $$files | wc -w | tr -d ' ')" >> $(1); \
		echo "// Generated: $$(date)" >> $(1); \
		echo "" >> $(1); \
		for f in $$files; do \
			echo "// ═══════════════════════════════════════════════════════════════" >> $(1); \
			echo "// FILE: $$f" >> $(1); \
			echo "// ═══════════════════════════════════════════════════════════════" >> $(1); \
			cat "$$f" >> $(1); \
			echo "" >> $(1); \
		done; \
		echo "  $(GREEN)✓$(RESET) $$(basename $(1))"; \
	fi
endef

rollups: rollups-clean ## Generate all rollup files for all packages
	@echo "$(CYAN)Generating rollups...$(RESET)"
	@mkdir -p $(ROLLUPS_DIR)
	@echo ""
	@echo "$(YELLOW)── packages/juice (core) ──$(RESET)"
	@# juice - BLoC Core
	$(call make_rollup,$(ROLLUPS_DIR)/juice_bloc.dart,juice - BLoC Core,$$(find packages/juice/lib/src/bloc -name '*.dart' 2>/dev/null | sort))
	@# juice - UI Components
	$(call make_rollup,$(ROLLUPS_DIR)/juice_ui.dart,juice - UI Components,$$(find packages/juice/lib/src/ui -name '*.dart' 2>/dev/null | sort))
	@# juice - Tests
	$(call make_rollup,$(ROLLUPS_DIR)/juice_tests.dart,juice - Tests,$$(find packages/juice/test -name '*.dart' 2>/dev/null | sort))
	@echo ""
	@echo "$(YELLOW)── packages/juice_storage ──$(RESET)"
	@# juice_storage - Library
	$(call make_rollup,$(ROLLUPS_DIR)/juice_storage_lib.dart,juice_storage - Library,$$(find packages/juice_storage/lib -name '*.dart' 2>/dev/null | sort))
	@# juice_storage - Tests
	$(call make_rollup,$(ROLLUPS_DIR)/juice_storage_tests.dart,juice_storage - Tests,$$(find packages/juice_storage/test -name '*.dart' 2>/dev/null | sort))
	@# juice_storage - Example
	$(call make_rollup,$(ROLLUPS_DIR)/juice_storage_example.dart,juice_storage - Example App,$$(find packages/juice_storage/example/lib -name '*.dart' 2>/dev/null | sort))
	@# juice_storage - Example Tests
	$(call make_rollup,$(ROLLUPS_DIR)/juice_storage_example_tests.dart,juice_storage - Example Tests,$$(find packages/juice_storage/example/test -name '*.dart' 2>/dev/null | sort))
	@echo ""
	@echo "$(YELLOW)── example (root demo app) ──$(RESET)"
	@# Root Example - Core (main, config, services)
	$(call make_rollup,$(ROLLUPS_DIR)/example_core.dart,Root Example - Core,example/lib/main.dart $$(find example/lib/config example/lib/services -name '*.dart' 2>/dev/null | sort))
	@# Root Example - BLoCs
	$(call make_rollup,$(ROLLUPS_DIR)/example_blocs.dart,Root Example - BLoCs,$$(find example/lib/blocs -name '*.dart' 2>/dev/null | sort))
	@# Root Example - Tests
	$(call make_rollup,$(ROLLUPS_DIR)/example_tests.dart,Root Example - Tests,$$(find example/test -name '*.dart' 2>/dev/null | sort))
	@echo ""
	@echo "$(GREEN)Generated $$(ls -1 $(ROLLUPS_DIR)/*.dart 2>/dev/null | wc -l | tr -d ' ') rollup files in $(ROLLUPS_DIR)/$(RESET)"
	@make --no-print-directory rollups-list

rollups-clean: ## Remove existing rollups
	@rm -rf $(ROLLUPS_DIR)

rollups-list: ## List all generated rollup files with sizes
	@echo ""
	@echo "$(CYAN)Rollup Files:$(RESET)"
	@echo ""
	@if [ -d "$(ROLLUPS_DIR)" ] && [ "$$(ls -A $(ROLLUPS_DIR)/*.dart 2>/dev/null)" ]; then \
		for f in $(ROLLUPS_DIR)/*.dart; do \
			lines=$$(wc -l < "$$f" | tr -d ' '); \
			files=$$(grep -c "^// FILE:" "$$f" || echo 0); \
			printf "  %6d lines  (%2d files)  %s\n" "$$lines" "$$files" "$$(basename $$f)"; \
		done; \
		echo ""; \
		echo "  ─────────────────────────────────"; \
		printf "  %6d lines  total\n" "$$(cat $(ROLLUPS_DIR)/*.dart | wc -l | tr -d ' ')"; \
	else \
		echo "  No rollups found. Run 'make rollups' first."; \
	fi
	@echo ""
