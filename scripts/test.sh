#!/bin/bash
set -euo pipefail

swift build ${SWIFT_BUILD_FLAGS:-}
bash Tests/error-contract.sh .build/debug/verbs
bash Tests/warden-smoke.sh .build/debug/warden .build/debug/verbs
