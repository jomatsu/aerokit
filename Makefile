SWIFT_SOURCES := $(shell find Sources Tests -name '*.swift' 2>/dev/null)

.PHONY: bootstrap
bootstrap:
	brew bundle

.PHONY: format
format:
	@command -v swiftformat >/dev/null || { echo "swiftformat is missing. Run: make bootstrap"; exit 1; }
	swiftformat .

.PHONY: lint
lint:
	@command -v swiftformat >/dev/null || { echo "swiftformat is missing. Run: make bootstrap"; exit 1; }
	@command -v swiftlint >/dev/null || { echo "swiftlint is missing. Run: make bootstrap"; exit 1; }
	swiftformat --lint .
	swiftlint lint --strict

.PHONY: build
build:
	swift build

.PHONY: test
test:
	swift test

.PHONY: check
check: lint build test

.PHONY: install
install:
	scripts/install-app.sh
