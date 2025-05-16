# Use multi-stage build with caching optimizations
FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04 AS base

# ------------------------------------------------------------
# Consolidated environment variables
# ------------------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8

# ------------------------------------------------------------
# System packages + Python 3.12 venv
# ------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv python3.12-dev \
        python3-pip \
        curl ffmpeg ninja-build git git-lfs wget vim \
        libgl1 libglib2.0-0 build-essential gcc && \
    ln -sf /usr/bin/python3.12 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip && \
    python3.12 -m venv /opt/venv && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/venv/bin:$PATH"


# ------------------------------------------------------------
# PyTorch (CUDA 12.8) & core tooling (no pip cache mounts)
# ------------------------------------------------------------
# 2) Install PyTorch (CUDA 12.8) & freeze torch versions to constraints file
RUN pip install --upgrade pip && \
    pip install --pre torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/nightly/cu128 && \
    # Save exact installed torch versions
    pip freeze | grep -E "^(torch|torchvision|torchaudio)" > /tmp/torch-constraint.txt && \
    # Install core tooling
    pip install packaging setuptools wheel pyyaml gdown triton runpod opencv-python

# 3) Clone ComfyUI
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /ComfyUI

# 4) Install ComfyUI requirements using torch constraint file
RUN cd /ComfyUI && \
    pip install -r requirements.txt --constraint /tmp/torch-constraint.txt

# ------------------------------------------------------------
# Final stage
# ------------------------------------------------------------
# ------------------------------------------------------------
# Final stage
# ------------------------------------------------------------
FROM base AS final
ENV PATH="/opt/venv/bin:$PATH"

RUN mkdir -p /models/checkpoints /models/text_encoders /models/vae /models/upscale_models

# Split diffusion model downloads to avoid 50GB+ layers
RUN wget -P /models/checkpoints https://huggingface.co/Lightricks/LTX-Video/resolve/main/ltxv-13b-0.9.7-distilled.safetensors

# Split text encoders
RUN wget -P /models/text_encoders https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors

# Upscalers
RUN wget -P /models/upscale_models https://huggingface.co/Lightricks/LTX-Video/resolve/main/ltxv-spatial-upscaler-0.9.7.safetensors
RUN wget -P /models/upscale_models https://huggingface.co/Lightricks/LTX-Video/resolve/main/ltxv-temporal-upscaler-0.9.7.safetensors


RUN pip install opencv-python

RUN git clone https://github.com/Hearmeman24/upscalers.git /tmp/upscalers \
    && cp /tmp/upscalers/4xLSDIR.pth /4xLSDIR.pth \
    && rm -rf /tmp/upscalers


RUN echo "torch==2.8.0.dev20250511+cu128" > /torch-constraint.txt && \
    echo "torchaudio==2.6.0.dev20250511+cu128" >> /torch-constraint.txt && \
    echo "torchsde==0.2.6" >> /torch-constraint.txt && \
    echo "torchvision==0.22.0.dev20250511+cu128" >> /torch-constraint.txt

# Clone and install all your custom nodes
RUN for repo in \
    https://github.com/kijai/ComfyUI-KJNodes.git \
    https://github.com/Comfy-Org/ComfyUI-Manager.git \
    https://github.com/nonnonstop/comfyui-faster-loading.git \
    https://github.com/rgthree/rgthree-comfy.git \
    https://github.com/Lightricks/ComfyUI-LTXVideo.git \
    https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git \
    https://github.com/cubiq/ComfyUI_essentials.git \
    https://github.com/kijai/ComfyUI-WanVideoWrapper.git \
    https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git \
    https://github.com/chrisgoringe/cg-use-everywhere.git \
    https://github.com/tsogzark/ComfyUI-load-image-from-url.git; \
  do \
    cd /ComfyUI/custom_nodes; \
    repo_dir=$(basename "$repo" .git); \
    git clone "$repo"; \
    if [ -f "/ComfyUI/custom_nodes/$repo_dir/requirements.txt" ]; then \
      pip install -r "/ComfyUI/custom_nodes/$repo_dir/requirements.txt" --constraint /torch-constraint.txt; \
    fi; \
    if [ -f "/ComfyUI/custom_nodes/$repo_dir/install.py" ]; then \
      python "/ComfyUI/custom_nodes/$repo_dir/install.py"; \
    fi; \
  done


RUN pip install --no-cache-dir \
    https://raw.githubusercontent.com/Hearmeman24/upscalers/master/sageattention-2.1.1-cp312-cp312-linux_x86_64.whl

RUN pip install --no-cache-dir discord.py==2.5.2 \
                              python-dotenv==1.1.0 \
                              Requests==2.32.3 \
                              websocket_client==1.8.0 \
                              "httpx[http2]"

RUN mkdir -p /ComfyUI/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/film/

RUN wget -O /ComfyUI/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/film/film_net_fp32.pt \
    https://d1s3da0dcaf6kx.cloudfront.net/film_net_fp32.pt

# Entrypointtt
COPY src/start_script.sh /start_script.sh
RUN chmod +x /start_script.sh
EXPOSE 8888
CMD ["/start_script.sh"]
