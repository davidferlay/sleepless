# Entry points used the same way locally and in CI.
SWIFT := /usr/bin/swift
APP := build/Sleepless.app
VERSION ?= 0.0.0

.PHONY: build test test-integration coverage format lint app validate smoke e2e package icon install-hooks clean

build:
	$(SWIFT) build

test:
	$(SWIFT) test --filter SleeplessCoreTests

test-integration:
	$(SWIFT) test --filter SleeplessIntegrationTests

coverage:
	$(SWIFT) test --filter SleeplessCoreTests --enable-code-coverage
	Scripts/coverage-summary.sh

format:
	$(SWIFT) format format --in-place --recursive Package.swift Sources Tests Scripts/make-icon.swift

lint:
	Scripts/lint.sh

app:
	Scripts/build-app.sh

validate:
	Scripts/validate-bundle.sh $(APP)

smoke:
	Scripts/smoke-test.sh $(APP)

e2e:
	Scripts/e2e-playback.sh $(APP)

package:
	Scripts/package.sh $(VERSION)

icon:
	$(SWIFT) Scripts/make-icon.swift Resources/AppIcon.icns

install-hooks:
	/usr/bin/git config core.hooksPath .githooks

clean:
	/bin/rm -rf .build build
