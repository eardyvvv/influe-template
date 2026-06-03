#!/bin/bash
set -e
source /venv/main/bin/activate

RED='\033[0;31m'
NC='\033[0m'

WORKSPACE=${WORKSPACE:-/workspace}
COMFYUI_DIR="${WORKSPACE}/ComfyUI"

AITK_DIR="${WORKSPACE}/ai-toolkit"
AITK_PORT_INTERNAL=18675

NODES_SUCCESS=0
MODELS_SUCCESS=0


NODES=(
    "https://github.com/kijai/ComfyUI-KJNodes.git"
    "https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
    "https://github.com/kijai/ComfyUI-Florence2.git"
)

DIFFUSION_MODELS=(
    "https://huggingface.co/silveroxides/FLUX.2-dev-fp8_scaled/resolve/main/flux-2-klein-9b-fp8mixed.safetensors"
)

TEXT_ENCODERS=(
    "https://huggingface.co/Comfy-Org/vae-text-encorder-for-flux-klein-9b/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors"
)

function provisioning_start() {
    echo "Starting provisioning..."
    provisioning_clone_comfyui
    provisioning_install_base_reqs

    echo "Downloading and installing custom nodes..."
    provisioning_get_nodes

    echo "Downloading models..."
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/text_encoders"     "${TEXT_ENCODERS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae"               "${VAE_MODELS[@]}"

    echo "Downloading Florence-2 captioner..."
    provisioning_get_file_as \
        "${COMFYUI_DIR}/models/LLM/Florence-2-SD3-Captioner/model.safetensors" \
        "https://huggingface.co/gokaygokay/Florence-2-SD3-Captioner/resolve/main/model.safetensors"

    echo "Installing AI-Toolkit..."
    provisioning_install_aitoolkit

    local NODES_TOTAL=${#NODES[@]}
    local MODELS_TOTAL=$((${#DIFFUSION_MODELS[@]} + ${#TEXT_ENCODERS[@]} + ${#VAE_MODELS[@]} + 1))

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

    if [[ ${#NODES[@]} -gt 0 ]]; then
        pip install --no-cache-dir --force-reinstall onnxruntime-gpu
    fi
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

function provisioning_get_file_as() {
    local out="$1"
    local url="$2"

    mkdir -p "$(dirname "$out")"

    if [[ -f "$out" ]]; then
        echo "Already present: $out"
        MODELS_SUCCESS=$((MODELS_SUCCESS + 1))
        return
    fi

    if wget --show-progress -e dotbytes=4M -O "$out" "$url"; then
        MODELS_SUCCESS=$((MODELS_SUCCESS + 1))
    else
        rm -f "$out"
        echo -e "${RED}CRITICAL ERROR: Failed to download $url. Exiting.${NC}"
        exit 1
    fi
}

function provisioning_install_aitoolkit() {
    if ! command -v node >/dev/null 2>&1 || [ "$(node -v | cut -d. -f1 | tr -d 'v')" -lt 20 ]; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
    fi

    if [[ ! -d "${AITK_DIR}/.git" ]]; then
        git clone https://github.com/ostris/ai-toolkit.git "${AITK_DIR}"
    fi
    cd "${AITK_DIR}"
    git submodule update --init --recursive

    if [[ ! -d "${AITK_DIR}/venv" ]]; then
        python3 -m venv "${AITK_DIR}/venv"
    fi
    (
        source "${AITK_DIR}/venv/bin/activate"
        pip install --no-cache-dir torch==2.9.1 torchvision==0.24.1 torchaudio==2.9.1 \
            --index-url https://download.pytorch.org/whl/cu128
        pip install --no-cache-dir -r requirements.txt
    )

    cd "${AITK_DIR}/ui"
    npm install
    npm run update_db
    npm run build
}

function provisioning_start_aitoolkit() {
    echo "Starting AI-Toolkit UI on internal port ${AITK_PORT_INTERNAL}..."
    (
        source "${AITK_DIR}/venv/bin/activate"
        cd "${AITK_DIR}/ui"
        export AI_TOOLKIT_AUTH="${AITK_AUTH}"
        export NODE_ENV=production
        exec npx next start --port "${AITK_PORT_INTERNAL}"
    ) > "${WORKSPACE}/aitoolkit.log" 2>&1 &
}

if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi

echo "Flushing file system cache to free up RAM..."
sync
sudo sysctl -w vm.drop_caches=3 2>/dev/null || echo "Note: Cache drop skipped, sync completed."

provisioning_start_aitoolkit

echo "All set. Starting ComfyUI..."
cd "${COMFYUI_DIR}"
python main.py --listen 0.0.0.0 --port 8188