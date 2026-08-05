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
    "https://github.com/Fannovel16/comfyui_controlnet_aux.git"
    "https://github.com/rgthree/rgthree-comfy.git"
    "https://github.com/yolain/ComfyUI-Easy-Use.git"
)

DIFFUSION_MODELS=(
    "https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/Wan22Animate/Wan2_2-Animate-14B_fp8_scaled_e4m3fn_KJ_v2.safetensors"
)

CLIP_MODELS=(
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"
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
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank128_bf16.safetensors"
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Wan22_relight/WanAnimate_relight_lora_fp16.safetensors"
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

    echo "Installing ONNX Runtime GPU..."

    python -m pip uninstall -y onnxruntime onnxruntime-gpu || true

    python -m pip install \
        --no-cache-dir \
        --force-reinstall \
        "onnxruntime-gpu==1.20.2"

    echo "Configuring system linker cache for ONNX Runtime CUDA libraries..."

    python - <<'PY' > /etc/ld.so.conf.d/venv-nvidia-libs.conf
import site
import glob
import os

paths = []
for root in site.getsitepackages():
    paths += glob.glob(os.path.join(root, "nvidia", "*", "lib"))

seen = set()
for p in paths:
    if os.path.isdir(p) and p not in seen:
        seen.add(p)
        print(p)
PY

    echo "NVIDIA library paths added to linker config:"
    cat /etc/ld.so.conf.d/venv-nvidia-libs.conf

    ldconfig

    echo "Verifying ONNX Runtime GPU..."

    python - <<'PY'
import torch
import onnxruntime as ort

print("PyTorch:", torch.__version__)
print("PyTorch CUDA:", torch.version.cuda)
print("ONNX Runtime:", ort.__version__)
print("ONNX Runtime file:", ort.__file__)
print("ONNX providers:", ort.get_available_providers())

if not hasattr(ort, "InferenceSession"):
    raise RuntimeError("onnxruntime.InferenceSession is missing")

if "CUDAExecutionProvider" not in ort.get_available_providers():
    raise RuntimeError("CUDAExecutionProvider is not available")

print("ONNX Runtime GPU check passed.")
PY

    echo "Checking required CUDA/cuDNN libraries in linker cache..."
    ldconfig -p | grep -E 'libcublasLt.so.12|libcublas.so.12|libcudart.so.12|libcudnn.so.9|libcudnn_ops.so.9|libcudnn_cnn.so.9' || {
        echo -e "${RED}CRITICAL ERROR: Required CUDA/cuDNN libraries were not found by ldconfig.${NC}"
        exit 1
    }
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

echo "All set. Provisioning completed."
echo "ComfyUI is started by the Vast.ai supervisor on port 18188."
echo "Not starting a second ComfyUI process from this provisioning script."
