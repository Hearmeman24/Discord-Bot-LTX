#!/usr/bin/env bash
set -euo pipefail

# Decide which branch to clone
if [ "${IS_DEV:-false}" = "true" ]; then
  BRANCH="dev"
else
  BRANCH="master"
fi

# Check if directory exists and remove it or update it
if [ -d "ComfyUI-Bot-Wan-Template" ]; then
  echo "📂 Directory already exists. Removing it first..."
  rm -rf Discord-Bot-LTX
fi

echo "📥 Cloning branch '$BRANCH' of Discord-Bot-LTX…"
git clone --branch "$BRANCH" https://github.com/Hearmeman24/Discord-Bot-LTX.git

echo "📂 Moving start.sh into place…"
mv Discord-Bot-LTX/src/start.sh /

echo "▶️ Running start.sh"
bash /start.sh