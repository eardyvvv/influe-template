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
    "https://github.com/kijai/ComfyUI-WanVideoWrapper.git"
    "https://github.com/kijai/ComfyUI-KJNodes.git"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
    "https://github.com/kijai/ComfyUI-segment-anything-2.git"
    "https://github.com/sipherxyz/comfyui-art-venture.git"
    "https://github.com/kijai/ComfyUI-WanAnimatePreprocess.git"
    "https://github.com/eardyvvv/comfyui-api-panel.git"
    "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
)

DIFFUSION_MODELS=(
    "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/Wan22Animate/Wan2_2-Animate-14B_fp8_scaled_e4m3fn_KJ_v2.safetensors"
)

CLIP_MODELS=(
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp16.safetensors"
)

CLIP_VISION=(
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"
)

VAE_MODELS=(
    "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors"
)

DETECTION_MODELS=(
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_data.bin"
    "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_model.onnx"
    "https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx"
)

LORAS=(
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_T2V_14B_cfg_step_distill_v2_lora_rank32_bf16.safetensors"
    "https://civitai.com/api/download/models/2066914?type=Model&format=SafeTensor"
)

function provisioning_start() {
    echo "Starting provisioning..."
    provisioning_clone_comfyui
    provisioning_install_base_reqs
    
    echo "Downloading and installing custom nodes..."
    provisioning_get_nodes

    echo "Downloading models..."
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip"               "${CLIP_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/clip_vision"        "${CLIP_VISION[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae"                "${VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/detection"          "${DETECTION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/loras"              "${LORAS[@]}"
    
    local NODES_TOTAL=${#NODES[@]}
    local MODELS_TOTAL=$((${#DIFFUSION_MODELS[@]} + ${#CLIP_MODELS[@]} + ${#CLIP_VISION[@]} + ${#VAE_MODELS[@]} + ${#DETECTION_MODELS[@]} + ${#LORAS[@]}))
    
    echo "========================================="
    echo "          PROVISIONING SUMMARY           "
    echo "========================================="
    echo -e " Nodes:  $NODES_SUCCESS out of $NODES_TOTAL successfully loaded."
    echo -e " Models: $MODELS_SUCCESS out of $MODELS_TOTAL successfully loaded."
    echo "========================================="
    
    echo "Provisioning completed."
}

function provisioning_clone_comfyui() {
    if [[ ! -d "${COMFYUI_DIR}" ]]; then
        git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFYUI_DIR}"
    fi
    cd "${COMFYUI_DIR}"
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