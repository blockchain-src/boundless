# 步骤指南：修改 GPU 数量
所提供的 [compose.yml](https://github.com/0xmoei/boundless/blob/main/compose.yml) 文件默认配置为使用 4 块 GPU，每块 GPU 分配给一个 `gpu_prove_agent` 服务（`gpu_prove_agent0` 到 `gpu_prove_agent3`）。

要调整 GPU 的数量（无论是增加还是减少），你需要修改 `gpu_prove_agent` 服务的定义，并更新 `broker` 服务中的 `depends_on` 列表。

本指南将详细说明需要更改的具体部分。

## 确定目标 GPU 数量
* 决定你想要使用的 GPU 数量（例如，将 4 块改为 3 块，或将 4 块改为 5 块）。
* 使用 `nvidia-smi -L` 命令确认主机上可用的 GPU 设备 ID。

## 修改 compose.yml 文件
* 用文本编辑器打开 `compose.yml` 文件。
* 找到 `gpu_prove_agentX` 服务（定义 `gpu_prove_agent0` 到 `gpu_prove_agent3` 的部分）以及 broker 服务的 `depends_on` 列表。

## 方案一：增加 GPU（如果你有超过 4 块 GPU）
### 1- 复制一个 `gpu_prove_agent` 服务定义：
* 复制现有的服务块，例如 `gpu_prove_agent3`：
```
  gpu_prove_agent3:
    <<: *agent-common
    mem_limit: 4G
    cpus: 4
    entrypoint: /app/agent -t prove
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ['3']
              capabilities: [gpu]
```
* 将其重命名为下一个顺序号（例如，第五块 GPU 命名为 `gpu_prove_agent4`）。
* 更新 `device_ids` 字段为新的 GPU ID（例如，将 `'3'` 改为 `'4'`）。
* `gpu_prove_agent4` 的示例：
```
  gpu_prove_agent4:
    <<: *agent-common
    mem_limit: 4G
    cpus: 4
    entrypoint: /app/agent -t prove
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ['4']
              capabilities: [gpu]
```

### 2- 更新 `x-broker-common` 服务的 `depends_on` 列表：
找到 `x-broker-common` 服务：
```yaml
x-broker-common: &broker-common
  restart: always
  depends_on:
    - rest_api
    - gpu_prove_agent0
    - gpu_prove_agent1
    - gpu_prove_agent2
    - gpu_prove_agent3
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
  network_mode: host
```

* 在 `depends_on` 列表中添加新服务名（如 `gpu_prove_agent4`）：
```yaml
  depends_on:
    - rest_api
    - gpu_prove_agent0
    - gpu_prove_agent1
    - gpu_prove_agent2
    - gpu_prove_agent3
    - gpu_prove_agent4
    - exec_agent0
    - exec_agent1
    - aux_agent
    - snark_agent
    - redis
    - postgres
```


## 方案二：减少 GPU（如果你有少于 4 块 GPU）
### 1- 删除一个 `gpu_prove_agent` 服务定义：
* 删除不再需要的服务块（如 `gpu_prove_agent3`）：
```yaml
  gpu_prove_agent3:
    <<: *agent-common
    mem_limit: 4G
    cpus: 4
    entrypoint: /app/agent -t prove
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ['3']
              capabilities: [gpu]
```

### 2- 更新 broker 服务的 `depends_on` 列表：
* 在 `x-broker-common` 服务的 `depends_on` 列表中，删除对应的服务名（如 `gpu_prove_agent3`）：
```yaml
  depends_on:
    - rest_api
    - gpu_prove_agent0
    - gpu_prove_agent1
    - gpu_prove_agent2
    - exec_agent0
    - exec_agent1
    - aux_agent
    - snark_agent
    - redis
    - postgres
```


