#!/bin/bash
set -euo pipefail
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"
python3 Scripts/verify_release.py
