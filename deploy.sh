#!/usr/bin/env bash
# deploy.sh — push latest changes from GitHub fork to the Pi and restart the service.
#
# Usage (from your Mac after pushing to origin):
#   ./deploy.sh
#   ./deploy.sh ntableman@192.168.50.183   # override host
#
# Prerequisites:
#   - Changes are already committed and pushed to origin (your GitHub fork).
#   - SSH access to the Pi (password or key-based).
set -euo pipefail

PI_HOST="${1:-ntableman@192.168.50.183}"
REPO_DIR="~/rpi-rgb-led-matrix"

echo "==> Deploying to ${PI_HOST}"

ssh "${PI_HOST}" bash -s << 'REMOTE'
set -euo pipefail

REPO_DIR="${HOME}/rpi-rgb-led-matrix"

echo "--- Pulling latest changes ---"
cd "${REPO_DIR}"
git pull origin master

echo "--- Building library ---"
make -j$(nproc)

echo "--- Installing Python bindings ---"
sudo make install-python

echo "--- Restarting service ---"
sudo systemctl restart rgb-panel
sleep 2

echo "--- Service status ---"
systemctl status rgb-panel --no-pager

echo ""
echo "==> Deploy complete."
REMOTE
