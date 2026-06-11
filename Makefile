PACKAGES := packages/app

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
	@for package in $(PACKAGES); do swift build --package-path "$$package" || exit 1; done

.PHONY: test
test:
	@for package in $(PACKAGES); do swift test --package-path "$$package" || exit 1; done

.PHONY: check
check: lint build test

.PHONY: install
install:
	@for package in $(PACKAGES); do "$$package/scripts/install-app.sh" || exit 1; done
