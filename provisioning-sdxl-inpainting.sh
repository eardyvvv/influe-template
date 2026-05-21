#!/bin/bash
set -e
source /venv/main/bin/activate

RED='\033[0;31m'
NC='\033[0m'

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

NODES_SUCCESS=0
MODELS_SUCCESS=0

NODES=(
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch"
    "https://github.com/WASasquatch/was-node-suite-comfyui"
)

CHECKPOINT_MODELS=(
    "https://huggingface.co/andro-flock/LUSTIFY-SDXL-NSFW-checkpoint-v2-0-INPAINTING/resolve/main/lustifySDXLNSFW_v20-inpainting.safetensors"
)

function provisioning_start() {
    echo "Starting provisioning..."
    provisioning_clone_comfyui
    provisioning_install_base_reqs

    echo "Downloading and installing custom nodes..."
    provisioning_get_nodes

    echo "Downloading checkpoint models..."
    provisioning_get_files "${COMFYUI_DIR}/models/checkpoints" "${CHECKPOINT_MODELS[@]}"

    local NODES_TOTAL=${#NODES[@]}
    local MODELS_TOTAL=${#CHECKPOINT_MODELS[@]}

    echo "========================================="
    echo "          PROVISIONING SUMMARY           "
    echo "========================================="
    echo -e " Nodes:  $NODES_SUCCESS out of $NODES_TOTAL successfully loaded."
    echo -e " Models: $MODELS_SUCCESS out of $MODELS_TOTAL successfully loaded."
    echo "========================================="

    echo "Provisioning completed."
}

function provisioning_clone_comfyui() {
    local COMFYUI_REPO="https://github.com/Comfy-Org/ComfyUI.git"
    local COMFYUI_VERSION="v0.21.1"
    local COMFYUI_COMMIT="26515acd23fa291a8f5ab53c5997258598de0701"

    if [[ ! -d "${COMFYUI_DIR}/.git" ]]; then
        git clone --no-checkout "${COMFYUI_REPO}" "${COMFYUI_DIR}"
    fi

    cd "${COMFYUI_DIR}"
    git fetch --force "${COMFYUI_REPO}" "refs/tags/${COMFYUI_VERSION}:refs/tags/${COMFYUI_VERSION}"

    local ACTUAL_COMMIT
    ACTUAL_COMMIT="$(git rev-list -n 1 "${COMFYUI_VERSION}")"
    if [[ "${ACTUAL_COMMIT}" != "${COMFYUI_COMMIT}" ]]; then
        echo -e "${RED}CRITICAL ERROR: Expected ComfyUI ${COMFYUI_VERSION} at ${COMFYUI_COMMIT}, got ${ACTUAL_COMMIT}.${NC}"
        exit 1
    fi

    git checkout --detach "${COMFYUI_COMMIT}"
}

function provisioning_install_base_reqs() {
    if [[ -f requirements.txt ]]; then
        pip install --no-cache-dir -r requirements.txt
    fi
}

function provisioning_get_nodes() {
    mkdir -p "${COMFYUI_DIR}/custom_nodes"
    cd "${COMFYUI_DIR}/custom_nodes"

    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        dir="${dir%.git}"
        path="./${dir}"

        local NODE_OK=0

        if [[ -d "$path" ]]; then
            if (cd "$path" && git pull --ff-only 2>/dev/null || { git fetch && git reset --hard origin/main; }); then
                NODE_OK=1
            else
                echo -e "${RED}CRITICAL ERROR: Failed to update node $dir. Exiting.${NC}"
                exit 1
            fi
        else
            local MAX_RETRIES=10
            local ATTEMPT=0
            local SUCCESS=0
            while [[ $ATTEMPT -lt $MAX_RETRIES ]]; do
                if git clone "$repo" "$path" --recursive; then
                    SUCCESS=1
                    break
                fi
                ATTEMPT=$((ATTEMPT + 1))
                echo -e "${RED}Retry $ATTEMPT/$MAX_RETRIES for $dir in 5 seconds...${NC}"
                sleep 5
            done
            if [[ $SUCCESS -eq 0 ]]; then
                echo -e "${RED}CRITICAL ERROR: Failed to clone node $dir after $MAX_RETRIES attempts. Exiting.${NC}"
                exit 1
            else
                NODE_OK=1
            fi
        fi

        if [[ $NODE_OK -eq 1 ]]; then
            NODES_SUCCESS=$((NODES_SUCCESS + 1))
        fi

        requirements="${path}/requirements.txt"
        if [[ -f "$requirements" ]]; then
            pip install --no-cache-dir -r "$requirements" || { echo -e "${RED}CRITICAL ERROR: Failed to install requirements for $dir. Exiting.${NC}"; exit 1; }
        fi
    done
}

function provisioning_get_files() {
    if [[ $# -lt 2 ]]; then return; fi
    local dir="$1"
    shift
    local files=("$@")

    mkdir -p "$dir"

    for url in "${files[@]}"; do
        if wget -nc --content-disposition --show-progress -e dotbytes=4M -P "$dir" "$url"; then
            MODELS_SUCCESS=$((MODELS_SUCCESS + 1))
        else
            echo -e "${RED}CRITICAL ERROR: Failed to download $url. Exiting.${NC}"
            exit 1
        fi
    done
}

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi

echo "Flushing file system cache to free up RAM..."
sync
sudo sysctl -w vm.drop_caches=3 2>/dev/null || echo "Note: Cache drop skipped, sync completed."

echo "All set. Starting ComfyUI..."
cd "${COMFYUI_DIR}"
python main.py --listen 0.0.0.0 --port 8188
