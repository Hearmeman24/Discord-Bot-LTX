#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

set -eo pipefail
set +u

echo "🔧 Installing LTXVideo packages..."
pip install -r /ComfyUI/custom_nodes/ComfyUI-LTXVideo/requirements.txt &
LTX_PID=$!

if [[ -z "$is_multi_gpu" || "$is_multi_gpu" != "false" ]]; then
if [[ "${IS_DEV,,}" =~ ^(true|1|t|yes)$ ]]; then
    API_URL="https://comfyui-job-api-dev.fly.dev"  # Replace with your development API URL
    echo "Using development API endpoint"
else
    API_URL="https://comfyui-job-api-prod.fly.dev"  # Replace with your production API URL
    echo "Using production API endpoint"
fi

URL="http://127.0.0.1:8188"

# Function to report pod status
  report_status() {
    local status=$1
    local details=$2

    echo "Reporting status: $details"

    curl -X POST "${API_URL}/pods/$RUNPOD_POD_ID/status" \
      -H "Content-Type: application/json" \
      -H "x-api-key: ${API_KEY}" \
      -d "{\"initialized\": $status, \"details\": \"$details\"}" \
      --silent

    echo "Status reported: $status - $details"
}
report_status false "Starting initialization"
# Set the network volume path
# Determine the network volume based on environment
# Check if /workspace exists
if [ -d "/workspace" ]; then
    NETWORK_VOLUME="/workspace"
# If not, check if /runpod-volume exists
elif [ -d "/runpod-volume" ]; then
    NETWORK_VOLUME="/runpod-volume"
# Fallback to root if neither directory exists
else
    echo "Warning: Neither /workspace nor /runpod-volume exists, falling back to root directory"
    NETWORK_VOLUME="/"
fi


echo "Using NETWORK_VOLUME: $NETWORK_VOLUME"
FLAG_FILE="$NETWORK_VOLUME/.comfyui_initialized"
COMFYUI_DIR="$NETWORK_VOLUME/ComfyUI"
if [ "${IS_DEV:-false}" = "true" ]; then
    REPO_DIR="$NETWORK_VOLUME/comfyui-discord-bot-dev"
    BRANCH="dev"
  else
    REPO_DIR="$NETWORK_VOLUME/comfyui-discord-bot-master"
    BRANCH="master"
fi


sync_bot_repo() {
  echo "Syncing bot repo (branch: $BRANCH)..."
  if [ ! -d "$REPO_DIR" ]; then
    echo "Cloning '$BRANCH' into $REPO_DIR"
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone --branch "$BRANCH" \
      "https://${GITHUB_PAT}@github.com/Hearmeman24/comfyui-discord-bot.git" \
      "$REPO_DIR"
    echo "Clone complete"

    echo "Installing Python deps..."
    cd "$REPO_DIR"
    # Add pip requirements installation here if needed
    cd /
  else
    echo "Updating existing repo in $REPO_DIR"
    cd "$REPO_DIR"

    # Clean up any Python cache files
    find . -name "*.pyc" -delete 2>/dev/null || true
    find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

    # Then proceed with git operations
    git fetch origin
    git checkout "$BRANCH"

    # Try pull, if it fails do hard reset
    git pull origin "$BRANCH" || {
      echo "Pull failed, using force reset"
      git fetch origin "$BRANCH"
      git reset --hard "origin/$BRANCH"
    }
    cd /
  fi
}

if [ -f "$FLAG_FILE" ] || [ "$new_config" = "true" ]; then
  echo "FLAG FILE FOUND"
  rm -rf "$NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-Manager" || echo "Remove operation failed, continuing..."
  sync_bot_repo

  wait $LTX_PID
  LTX_STATUS=$?
  echo "✅ LTXNodes install complete"

  echo "▶️  Starting ComfyUI"
  # group both the main and fallback commands so they share the same log
  mkdir -p "$NETWORK_VOLUME/${RUNPOD_POD_ID}"
  nohup bash -c "python3 \"$NETWORK_VOLUME\"/ComfyUI/main.py --listen --use-sage-attention --extra-model-paths-config '/Discord-Bot-LTX/extra_model_paths.yaml' 2>&1 | tee \"$NETWORK_VOLUME\"/comfyui_\"$RUNPOD_POD_ID\"_nohup.log" &

  until curl --silent --fail "$URL" --output /dev/null; do
      echo "🔄  Still waiting…"
      sleep 2
  done

  if [ $LTX_STATUS -ne 0 ]; then
    echo "❌ LTXNodes install failed."
    exit 1
  fi

  echo "ComfyUI is UP Starting worker"
  nohup bash -c "python3 \"$REPO_DIR\"/worker.py 2>&1 | tee \"$NETWORK_VOLUME\"/\"$RUNPOD_POD_ID\"/worker.log" &

  report_status true "Pod fully initialized and ready for processing"
  echo "Initialization complete! Pod is ready to process jobs."

  # Wait on background jobs forever
  wait

else
  echo "NO FLAG FILE FOUND – starting initial setup"
fi

sync_bot_repo
# Set the target directory
CUSTOM_NODES_DIR="$NETWORK_VOLUME/ComfyUI/custom_nodes"

if [ ! -d "$COMFYUI_DIR" ]; then
    mv /ComfyUI "$COMFYUI_DIR"
else
    echo "Directory already exists, skipping move."
fi

echo "Downloading CivitAI download script to /usr/local/bin"
git clone "https://github.com/Hearmeman24/CivitAI_Downloader.git" || { echo "Git clone failed"; exit 1; }
mv CivitAI_Downloader/download.py "/usr/local/bin/" || { echo "Move failed"; exit 1; }
chmod +x "/usr/local/bin/download.py" || { echo "Chmod failed"; exit 1; }
rm -rf CivitAI_Downloader  # Clean up the cloned repo
pip install huggingface_hub
pip install onnxruntime-gpu



if [ "$enable_optimizations" == "true" ]; then
echo "Downloading Triton"
pip install triton
fi

# Determine which branch to use


# Change to the directory
cd "$CUSTOM_NODES_DIR" || exit 1

# Function to download a model using huggingface-cli
download_model() {
  local destination_dir="$1"
  local destination_file="$2"
  local repo_id="$3"
  local file_path="$4"

  mkdir -p "$destination_dir"

  if [ ! -f "$destination_dir/$destination_file" ]; then
    echo "Downloading $destination_file..."

    # First, download to a temporary directory
    local temp_dir=$(mktemp -d)
    huggingface-cli download "$repo_id" "$file_path" --local-dir "$temp_dir" --resume-download

    # Find the downloaded file in the temp directory (may be in subdirectories)
    local downloaded_file=$(find "$temp_dir" -type f -name "$(basename "$file_path")")

    # Move it to the destination directory with the correct name
    if [ -n "$downloaded_file" ]; then
      mv "$downloaded_file" "$destination_dir/$destination_file"
      echo "Successfully downloaded to $destination_dir/$destination_file"
    else
      echo "Error: File not found after download"
    fi

    # Clean up temporary directory
    rm -rf "$temp_dir"
  else
    echo "$destination_file already exists, skipping download."
  fi
}

# Workspace as main working directory
echo "cd $NETWORK_VOLUME" >> ~/.bashrc
echo "cd $NETWORK_VOLUME" >> ~/.bash_profile


mkdir -p "$NETWORK_VOLUME/${RUNPOD_POD_ID}"
nohup bash -c "python3 \"$NETWORK_VOLUME\"/ComfyUI/main.py --listen 2>&1 | tee \"$NETWORK_VOLUME\"/comfyui_\"$RUNPOD_POD_ID\"_nohup.log" &
COMFY_PID=$!

until curl --silent --fail "$URL" --output /dev/null; do
    echo "🔄  Still waiting…"
    sleep 2
done

echo "ComfyUI is UP Starting worker"
nohup bash -c "python3 \"$REPO_DIR\"/worker.py 2>&1 | tee \"$NETWORK_VOLUME\"/\"$RUNPOD_POD_ID\"/worker.log" &
WORKER_PID=$!

report_status true "Pod fully initialized and ready for processing"
echo "Initialization complete! Pod is ready to process jobs."
# Wait for both processes
wait $COMFY_PID $WORKER_PID
fi
wait