# Boundless Prover 指南
Boundless Prover 节点是一个参与 Boundless 去中心化证明市场的计算型证明系统。Prover 需要质押 USDC，竞标计算任务，使用 GPU 加速生成零知识证明，并在成功生成证明后获得奖励。

本指南涵盖了 Ubuntu 20.04/22.04 系统下的**自动化**和**手动**安装方法。

## 目录
- [Boundless Prover 市场](#boundless-prover-市场)
- [注意事项](#注意事项)
- [硬件与软件要求](#硬件与软件要求)
- [租用 GPU](#租用-gpu)
- [自动化安装](#自动化安装)
- [手动安装](#手动安装)
  - [依赖项](#依赖项)
  - [系统硬件检测](#系统硬件检测)
  - [配置 Prover](#配置-prover)
  - [运行 Prover](#运行-prover)
  - [运行 Bento](#运行-bento)
  - [配置网络](#配置网络)
  - [质押 USDC](#质押-usdc)
  - [运行 Broker](#运行-broker)
- [Bento（Prover）与 Broker 优化](#bento-prover--broker-优化)
  - [分段大小（Prover）](#分段大小prover)
  - [Bento 基准测试](#bento-基准测试)
  - [Broker 优化](#broker-优化)
  - [多 Broker](#多-broker)
- [安全更新或停止 Prover](#安全更新或停止-prover)
- [调试](#调试)

---

## Boundless Prover 市场
首先，你需要了解**Boundless Prover 市场**的实际运作方式，这样你才能明白你在做什么。

1. **请求提交**：开发者在 Boundless 上提交计算任务（订单），并提供 ETH/ERC-20 奖励
2. **Prover 质押 USDC**：Prover 必须在竞标订单前质押 `USDC`
3. **竞标流程**：Prover 发现订单并提交有竞争力的报价（`mcycle_price`）
4. **订单锁定**：获胜的 Prover 使用质押的 USDC 锁定订单，承诺在截止时间内完成证明
5. **生成证明**：Prover 使用 GPU 加速计算并提交证明
6. **奖励/惩罚**：有效证明获得奖励；无效/延迟证明将导致质押被罚没

---

## 注意事项
- Prover 目前处于测试阶段，虽然我承认本指南已经非常完善，但你在运行过程中可能仍会遇到一些问题，因此你可以等到官方激励测试网更稳定、指南更新后再参与，或者现在就开始尝试。
- 建议先从测试网开始，以免质押资金损失。
- 我会不断更新本 github 指南，所以请随时回来查看，并关注我的 [X](https://x.com/0xMoei) 获取最新动态。

---

## 硬件与软件要求
### 硬件
* CPU - 16 线程，单核加速性能较好（>3Ghz）
* 内存 - 32 GB
* 硬盘 - 100 GB NVME/SSD
* GPU
  * 最低要求：一块 8GB 显存的 GPU
  * 推荐配置：10 块 8GB 显存的 GPU
  * 推荐 GPU 型号为 4090、5090 和 L4。
> * 你可以先用单卡测试，后续根据配置调整，具体见后文。

### 系统
* 支持：Ubuntu 20.04/22.04
* 不支持：Ubuntu 24.04
* 如果你在 Windows 本地运行，请使用此 [指南](https://github.com/0xmoei/Install-Linux-on-Windows) 安装 Ubuntu 22 WSL

---

# 自动化安装
如需自动化安装和 Prover 管理，可使用此脚本自动处理所有依赖、配置、安装和 Prover 管理。

## 下载并运行安装脚本：
```bash
# 克隆仓库
git clone https://github.com/blockchain-src/boundless.git && cd boundless

# 运行安装脚本
chmod +x install_prover.sh && sudo ./install_prover.sh
```

* 安装过程可能较长，因为需要安装驱动和构建大文件，请耐心等待。

### 安装过程中：
* 脚本会自动检测你的 GPU 配置
* 你将被提示输入：
  * 网络选择（主网/测试网）
  * RPC URL：详见 [获取 RPC](#获取-rpc)
  * 私钥（输入时隐藏）
  * Broker 配置参数：参数详情见 [Broker 优化](#broker-优化)


### 安装后管理脚本：
安装完成后，运行或配置 Prover 需进入安装目录并运行管理脚本 `prover.sh`：

```bash
cd ~/boundless
./prover.sh
```
管理脚本菜单包括：
- **服务管理**：启动/停止 broker，查看日志，健康检查
- **配置管理**：[切换网络](#获取-rpc)，更新私钥，编辑 [broker 配置](#broker-优化)
- **质押管理**：质押 USDC，查询余额
- **性能测试**：用订单 ID 运行基准测试
- **监控**：实时 GPU 监控


### 修改 x-exec-agent-common & gpu-prove-agent 的 CPU/RAM
`prover.sh` 脚本管理所有 broker 配置（如 `broker.toml`），但如需优化并为 `compose.yml` 增加 RAM 和 CPU，请参考 [x-exec-agent-common](#修改-gpu_prove_agent-的-cpu/ram) 和 [gpu-prove-agent](#修改-gpu_prove_agent-的-cpu/ram) 部分
* 修改 `compose.yml` 后需重启 broker

### 注意
即使你使用自动化脚本安装，仍建议阅读**[手动安装](#手动安装)**和**[Bento（Prover）与 Broker 优化](#bento-prover--broker-优化)**部分，学习如何优化 Prover。

---

# Bento（Prover）与 Broker 优化
有许多优化因素可提升在 prover 竞赛中的胜率，详见 [官方 broker 指南](https://docs.beboundless.xyz/provers/broker) 或 [prover 指南](https://docs.beboundless.xyz/provers/performance-optimization)

## 提升预执行效率
* `compose.yml` 中的 `exec_agent` 服务负责订单的预执行（preflight），以评估 prover 是否能竞标。
* 并发预执行越多，锁定订单越快，竞争力越强。
  * 增加 `exec_agent` 数量可并发预执行更多订单。
  * 单个 `exec_agent` 增加 CPU/RAM 可提升预执行速度。
* 默认值为 `2`，可根据需要调整。
* 相关服务有：`x-exec-agent-common` 和 `exec_agent`
  * `x-exec-agent-common`：所有 `exec_agent` 服务的主设置，包括 CPU 和内存
  * `exec_agentX`：具体的 agent，X 为编号。增加 agent 只需编号递增。

`x-exec-agent-common` 示例：
```yml
x-exec-agent-common: &exec-agent-common
  <<: *agent-common
  mem_limit: 4G
  cpus: 2
  environment:
    <<: *base-environment
    RISC0_KECCAK_PO2: ${RISC0_KECCAK_PO2:-17}
  entrypoint: /app/agent -t exec --segment-po2 ${SEGMENT_SIZE:-21}
```
* 可增加 `cpus` 和 `mem_limit`

`exec_agent` 示例：
```yaml
  exec_agent0:
    <<: *exec-agent-common

  exec_agent1:
    <<: *exec-agent-common
```
* 增加 agent 只需多加几行，编号递增即可

## 提升 GPU 证明效率
* `compose.yml` 中的 `gpu_prove_agent` 服务负责利用 GPU 进行订单证明。
* 单卡情况下，可通过增加每个 GPU agent 的 CPU/RAM 提升性能。
* 默认 CPU/RAM 已足够，但如硬件配置较好可适当增加。
* 你会看到如下 `gpu_prove_agentX` 服务配置，可在此增加每个 GPU agent 的内存和 CPU。
   ```yml
     gpu_prove_agent0:
       <<: *agent-common
       runtime: nvidia
       mem_limit: 4G
       cpus: 4
       entrypoint: /app/agent -t prove
       deploy:
         resources:
           reservations:
             devices:
               - driver: nvidia
                 device_ids: ['0']
                 capabilities: [gpu]
   ```
* 虽然默认 CPU/RAM 已够用，但单卡可适当增加，但不要全部用满，需留部分资源给其他任务。

## Bento 基准测试
安装 psql：
```bash
apt update
apt install postgresql-client
psql --version
```

**1. 推荐：用订单 ID 模拟基准测试（确保 Bento 正在运行）：**
```bash
boundless proving benchmark --request-ids <IDS>
```
* 可在 [此处](https://explorer.beboundless.xyz/orders) 获取订单 ID
* 多个 ID 用逗号分隔
* 建议选择不同大小和程序的订单，偏向大订单以获得更具代表性的基准

* 如下图，prover 估算可处理约 430,000 cycles/s（约 430 khz）。
* 在 `broker.toml` 的 `peak_prove_khz` 中设置略低于推荐值（后文详解）

> 可用 `nvtop` 命令在新终端监控 GPU 利用率

**2. 使用 Harness Test 进行基准测试**
* 也可用 ITERATION_COUNT 基准测试 GPU：
```
RUST_LOG=info bento_cli -c <ITERATION_COUNT>
```
`<ITERATION_COUNT>` 为合成任务执行次数。建议从 `4096` 开始，性能较低可用 `2048` 或 `1024`，功能测试用 `32` 即可。

* 检查 harness test 的 `khz` 和 `cycles`
```
bash scripts/job_status.sh JOB_ID
```
* `JOB_ID` 为测试时提示的编号。
* 得到的 `hz` 除以 1000 即为 `khz`，以及已证明的 `cycles`。
* 若报错 `not_found`，说明未创建 `.env.broker`，脚本用 `.env.broker` 的 `SEGMENT_SIZE` 查询分段大小。可用 `cp .env.broker-template .env.broker` 修复。

---

## Broker 优化

* Broker 是 prover 的一个容器，负责链上交互、订单锁定、设置质押竞价等。
* `broker.toml` 配置 broker 如何链上交互并与其他 prover 竞争。

复制模板为主配置文件：
```bash
cp broker-template.toml broker.toml
```

编辑 broker.toml：
```bash
nano broker.toml
```
* 官方 `broker.toml` 示例见 [此处](https://github.com/boundless-xyz/boundless/blob/main/broker-template.toml)

### 提高锁定率
Broker 运行后，在 GPU 证明前，需与其他 prover 竞争锁定订单。优化方法如下：

1. 降低 `mcycle_price`，让 Broker 以更低价格竞标证明。
* 订单被检测到后，broker 会预执行估算所需 `cycles`。如图，prover 证明了数百万/数千 cycles 的订单。
* `mcycle_price` 即每百万 cycles 的报价。最终价格 = `mcycle_price` x `cycles`
* 设置更低的 `mcycle_price`，可提升中标概率。

* 可在 [explorer](https://explorer.beboundless.xyz/orders/0xc2db89b2bd434ceac6c74fbc0b2ad3a280e66db024d22ad3) 查看其他 prover 的 `mcycle_price`，在订单详情页查找 `ETH per Megacycle`

2. 提高 `lockin_priority_gas`，消耗更多 gas 以抢先竞标。需先去掉 `#` 注释并设置 gas，单位为 Gwei。

### `broker.toml` 其他设置
详见 [官方文档](https://docs.beboundless.xyz/provers/broker#settings-in-brokertoml)
* `peak_prove_khz`：证明后端每秒最大 cycles 数（kHz）。
  * 可根据前述 [Bento 基准测试](https://github.com/0xmoei/boundless/tree/main#benchmarking-bento) 设置

* `max_concurrent_proofs`：可同时锁定的订单数。增加此值可锁定更多订单，但若无法在截止时间内完成证明，质押将被罚没。
  * 达到上限后，系统会暂停新订单，等待现有证明完成。
  * 默认值为 `2`，具体取决于 GPU 和配置，建议测试后调整。

* `min_deadline`：竞标请求时订单剩余最少秒数。
  * 订单有截止时间，若 prover 无法在此时间内完成证明将被罚没。
  * 设置最小截止时间后，prover 不会接受低于该时间的订单。
  * 如下图，订单在截止后才完成，prover 因延迟被罚没。

---

## 多 Broker
可用单个 Bento 客户端同时运行多个 broker，在不同网络生成证明。
* 你的配置可能与我的不同，可请 AI 聊天协助修改。以下为我的配置示例：
* 需修改的文件有：`compose.yml`、`broker.toml`、`.env` 文件（如 `.env.base-sepolia`）

### 修改 `compose.yml`

**步骤 1：添加 `broker2` 服务**：

在 services 部分，现有 `broker` 服务后添加 `broker2`。其配置与原 `broker` 类似，但使用不同的数据库和配置文件。
* 需修改的内容：
 * 名称改为 `broker2`
 * `source: ./broker2.toml`
 * `broker2-data:/db/`
 * `--db-url` 改为 `'sqlite:///db/broker2.db'`

**步骤 2：多 broker 环境变量（.env 文件）**：

原本用 `.env` 文件（如 `.env.base`）设置网络，现在需在 `compose.yml` 中为每个 broker（如 `broker`、`broker1`、`broker3`）指定对应的 `.env` 文件。
* 在每个 broker 服务的 `volumes` 后添加：
```
    env_file:
      - .env.base
```

**步骤 3：添加 `broker2-data` 卷**：
* 在 `compose.yml` 末尾的 `volumes` 部分添加新卷：

例如，支持 Base 和 ETH Sepolia 两个网络的 `broker`、`broker2` 服务配置如下：

```yaml
  broker:
    restart: always
    depends_on:
      - rest_api
      - gpu_prove_agent0
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
    env_file:
      - .env.base
    environment:
      RUST_LOG: ${RUST_LOG:-info,broker=debug,boundless_market=debug}
    entrypoint: /app/broker --db-url 'sqlite:///db/broker.db' --set-verifier-address ${SET_VERIFIER_ADDRESS} --boundless-market-address ${BOUNDLESS_MARKET_ADDRESS} --config-file /app/broker.toml --bento-api-url http://localhost:8081
    ulimits:
      nofile:
        soft: 65535
        hard: 65535

  broker2:
    restart: always
    depends_on:
      - rest_api
      - gpu_prove_agent0
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
        source: ./broker2.toml
        target: /app/broker.toml
      - broker2-data:/db/
    network_mode: host
    env_file:
      - .env.eth-sepolia
    environment:
      RUST_LOG: ${RUST_LOG:-info,broker=debug,boundless_market=debug}
    entrypoint: /app/broker --db-url 'sqlite:///db/broker2.db' --set-verifier-address ${SET_VERIFIER_ADDRESS} --boundless-market-address ${BOUNDLESS_MARKET_ADDRESS} --config-file /app/broker.toml --bento-api-url http://localhost:8081
    ulimits:
      nofile:
        soft: 65535
        hard: 65535

volumes:
  redis-data:
  postgres-data:
  minio-data:
  grafana-data:
  broker-data:
  broker2-data:
```

### 修改 `broker.toml`
每个 broker 实例需单独的 `broker.toml` 文件（如 `broker.toml`、`broker2.toml` 等）

为第二个 broker 创建新配置文件：
```bash
# 从现有 broker 配置复制
cp broker.toml broker2.toml
 
# 或用模板新建
cp broker-template.toml broker2.toml
```
然后根据每个网络修改配置，注意：

* `peak_prove_khz` 在所有 broker 间共享。
  * 例如基准测试为 `500kHz`，则各配置总和不得超过 `500kHz`。
  * 如：`broker.toml`: `peak_prove_khz = 250`，`broker2.toml`: `peak_prove_khz = 250`

* `max_concurrent_preflights` 限制 broker 可同时运行的定价任务数。所有 broker 的总和不得超过 `compose.yml` 中 `exec_agent` 服务数。
  * 如有两个 `exec_agent`（`exec_agent0` 和 `exec_agent1`），则所有 broker 的 `max_concurrent_preflights` 总和不得超过 2。

* `max_concurrent_proofs`
  * 与 `peak_prove_khz` 不同，`max_concurrent_proofs` 为每个 broker 独立设置，控制单个 broker 可同时处理的证明任务数。
  * 如仅有一块 GPU，通常只能同时处理一个证明，建议 `max_concurrent_proofs = 1`

 * `lockin_priority_gas`：请根据各网络设置合适的 gwei

---

# 安全更新或停止 Prover
### 1. 检查锁定订单
通过 `broker` 日志或 [prover 的 indexer 页面](https://explorer.beboundless.xyz/provers/) 确认 broker 没有未完成的锁定订单，否则停止或更新时可能被罚没质押。

* 如需临时不接受新订单，可将 `max_concurrent_proofs` 设为 `0`，待所有锁定订单完成后再停止节点。

### 2. 停止 broker 并可选清理数据库
```bash
# 可选，如不升级节点仓库可跳过
just broker clean
 
# 或仅停止 broker，不清理数据卷
just broker down
```

### 3. 更新到新版本
最新 tag 见 [releases](https://github.com/boundless-xyz/boundless/releases)
```bash
git checkout <new_version_tag>
# 例如：git checkout v0.10.0
```

### 4. 启动新版本 broker
```bash
just broker
```

---

### 网络配置方法二：.env 文件
**推荐**使用方法一，跳过此步直接看[质押 USDC](#质押-usdc)。如需方法二，详见此处

* 官方配置的三份 `.env` 文件分别对应各网络（`.env.base`、`.env.base-sepolia`、`.env.eth-sepolia`）。

### Base 主网
* 此处以 `.env.base` 为例，其他网络请修改对应文件。
* 目前 Base 主网订单需求较低，可通过修改 `.env.base-sepolia` 或 `.env.eth-sepolia` 参与 Base Sepolia 或 ETH Sepolia。

* 配置 `.env.base` 文件：
```bash
nano .env.base
```
添加如下变量：
* `export RPC_URL=""`：
  * RPC 地址需加双引号
* `export PRIVATE_KEY=`：填写你的 EVM 钱包私钥

* 注入 `.env.base` 到 prover：
```bash
source .env.base
```
* 每次关闭终端或启动 prover 前，需重新注入网络配置。

### 可选：自定义环境 `.env.broker`
`.env.broker` 与前述 `.env` 文件类似，但可配置更多选项。使用时需参考 [部署页面](https://docs.beboundless.xyz/developers/smart-contracts/deployments) 替换各网络合约地址。
* 建议不用，因切换网络时直接更换上述 `.env` 文件更方便。

* 创建 `.env.broker`：
```bash
cp .env.broker-template .env.broker
```

* 配置 `.env.broker` 文件：
```bash
nano .env.broker
```
添加如下变量：
* `export RPC_URL=""`：Base 网络 rpc url，建议用第三方服务如 Alchemy
  * RPC 地址需加双引号
* `export PRIVATE_KEY=`：填写你的 EVM 钱包私钥
* 其余变量见 [此处](https://docs.beboundless.xyz/developers/smart-contracts/deployments)：
  * `export BOUNDLESS_MARKET_ADDRESS=`
  * `export SET_VERIFIER_ADDRESS=`
  * `export VERIFIER_ADDRESS=`（需手动添加）
  * `export ORDER_STREAM_URL=`
 
* 注入 `.env.broker` 到 prover：
```
source .env.broker
```
  * 每次关闭终端后，需重新注入网络配置。

---

# 调试
## 错误：Too many open files (os error 24)
构建 `just broker` 过程中可能遇到 `Too many open files (os error 24)` 错误。

### 解决方法：
```
nano /etc/security/limits.conf
```
* 添加：
```
* soft nofile 65535
* hard nofile 65535
```

```
nano /lib/systemd/system/docker.service
```
* 在 `[Service]` 部分添加或修改：
```
LimitNOFILE=65535
```

```
systemctl daemon-reload
systemctl restart docker
```

* 重启终端，重新注入网络配置，再运行 `just broker`


## Prover [explorer](https://explorer.beboundless.xyz/) 上出现大量 `Locked` 订单
* 多为 RPC 问题，请检查日志。
* 可在 `broker.toml` 文件中将 `txn_timeout = 45`，增加交易确认超时时间。






