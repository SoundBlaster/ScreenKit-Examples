PROJECT_NAME := ScreenKitExamples
PROJECT := $(PROJECT_NAME).xcodeproj
SIMULATOR_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro

.PHONY: test test-screenkitlab test-tonato

test: test-screenkitlab test-tonato

test-screenkitlab:
	xcodebuild -quiet -skipMacroValidation -project $(PROJECT) -scheme ScreenKitLab -destination '$(SIMULATOR_DESTINATION)' test

test-tonato:
	xcodebuild -quiet -skipMacroValidation -project $(PROJECT) -scheme ToNaTo -destination '$(SIMULATOR_DESTINATION)' test
