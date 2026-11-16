#!/bin/sh
# Xcode Cloud runs this right after cloning. DabbleMe.xcodeproj is gitignored (project.yml is the
# source of truth), so it has to be generated before Xcode Cloud can build anything.
set -e

export HOMEBREW_NO_AUTO_UPDATE=1
command -v xcodegen >/dev/null || brew install xcodegen

cd "$(dirname "$0")/.."
xcodegen generate
