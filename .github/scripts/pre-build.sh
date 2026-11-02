#!/bin/bash
# App-specific steps run by ios-testflight.yml before the project is generated.
# Keep the App Store Connect name in step with the app's name (never fails the build).
python3 "$GITHUB_WORKSPACE/.github/scripts/set_app_name.py" || true
