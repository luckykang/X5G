# X5G

X5G 是一个基于 `systemd` 的 5G 激活与巡检脚本，当前版本为单脚本、单服务部署：

- 脚本：[5g_runtime.sh](5g_runtime.sh)
- 服务：[5g-runtime.service](5g-runtime.service)

脚本启动后会按以下顺序运行：

1. 等待 `NetworkManager` 就绪
2. 检测 5G 硬件是否存在
3. 检测设备 `pcie1` 是否就绪
4. 调用 `nmcli` 激活目标连接
5. 周期性检查连接、IP 和默认路由
6. 检测到异常后进入快速重试

## 运行环境

- Linux 系统
- 已启用 `systemd`
- 已安装并启用 `NetworkManager`
- 系统具备 `nmcli`、`ip`、`lsusb`、`lspci`
- 使用移远（Quectel）5G 模组，且系统已正确识别
- 对应设备名与连接名已确认

## 参数配置说明

以下参数定义在 [`5g_runtime.sh`](5g_runtime.sh) 顶部，可按现场环境调整。

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `LOG_FILE` | `/mnt/sda/logs/5g.log` | 业务日志文件路径 |
| `MAX_LOG_SIZE` | `5242880` | 单个日志文件最大大小，单位字节，默认 5 MB |
  # 配置参数
| `CONN_NAME` | `有线连接 4` | `nmcli` 中要激活的连接名称 |
| `DEVICE_NAME` | `pcie1` | 5G 网卡设备名 |
  # 预检查阶段
| `PRECHECK_INTERVAL_SEC` | `5` | 启动预检查轮询间隔，单位秒 |
| `PRECHECK_TIMEOUT_SEC` | `600` | 预检查超时时间，单位秒 |
| `PRECHECK_HEARTBEAT_SEC` | `60` | 预检查超时后的心跳日志输出间隔，单位秒 |
  # 运行阶段
| `STABLE_CHECK_SEC` | `300` | 稳态巡检周期，单位秒 |
| `FAST_RETRY_SEC` | `10` | 激活失败后的快速重试间隔，单位秒 |
| `MAX_FAIL_TIMES` | `5` | 单轮快速重试最大次数 |
| `REBOOT_ON_FAIL` | `0` | 激活失败处理开关，`1` 表示失败后重启系统，`0` 表示只记录告警不重启 |

### 参数调整建议

- 如果设备枚举较慢，可适当增大 `PRECHECK_TIMEOUT_SEC`
- 如果希望预检查卡住时少打一点日志，可适当增大 `PRECHECK_HEARTBEAT_SEC`
- 如果掉线后希望更快恢复，可适当减小 `FAST_RETRY_SEC`
- 如果现场网络波动较大，可适当增大 `MAX_FAIL_TIMES`
- 如果不希望设备异常导致整机重启，保持 `REBOOT_ON_FAIL=0`
- 如果连接名称不是 `有线连接 4`，必须先修改 `CONN_NAME`
- 如果实际网卡名称不是 `pcie1`，必须先修改 `DEVICE_NAME`


## 用户使用手册

### 1. 文件部署

将脚本和服务文件分别部署到目标机器：

```bash
sudo cp 5g_runtime.sh /usr/local/bin/5g_runtime.sh
sudo cp 5g-runtime.service /etc/systemd/system/5g-runtime.service
```

### 2. 修改参数

根据现场环境修改脚本配置：

```bash
sudo vim /usr/local/bin/5g_runtime.sh
```

重点确认以下两项：

- `CONN_NAME` 是否与 `nmcli con show` 中的连接名一致
- `DEVICE_NAME` 是否与 `nmcli device status` 中的设备名一致

### 3. 授权与加载服务

```bash
sudo chmod +x /usr/local/bin/5g_runtime.sh
sudo systemctl daemon-reload
sudo systemctl enable 5g-runtime.service
```

### 4. 启动服务

```bash
sudo systemctl restart 5g-runtime.service
```

首次部署后，也可以直接执行：

```bash
sudo systemctl start 5g-runtime.service
```

### 5. 查看服务状态

```bash
sudo systemctl status 5g-runtime.service
```

### 6. 查看运行日志

查看业务日志：

```bash
tail -f /mnt/sda/logs/5g.log
```

查看 systemd 日志：

```bash
sudo journalctl -u 5g-runtime.service -f
```

### 7. 停止、启动、重启

```bash
sudo systemctl stop 5g-runtime.service
sudo systemctl start 5g-runtime.service
sudo systemctl restart 5g-runtime.service
```

### 8. 禁用开机自启

```bash
sudo systemctl disable 5g-runtime.service
```

## 运行逻辑说明

### 启动预检查

启动后脚本先输出：

- `==============================================================`
- `5G Precheck`
- `==============================================================`
- `项目        | 状态   | WARN | 说明`
- `------------+--------+------+------------------------------`
- `NetworkMgr | OK     | -    | NetworkManager 已就绪`
- `5G 硬件    | OK     | -    | 5G 硬件已就绪`
- `设备 pcie1 | OK     | -    | 5G 硬件与设备 pcie1 已就绪`

只有三项都通过后，才会进入激活阶段。

预检查超过 `PRECHECK_TIMEOUT_SEC` 后不会退出，而是输出带状态码的 `WAIT` 行，并按 `PRECHECK_HEARTBEAT_SEC` 周期继续打印心跳日志。

### 激活阶段

脚本会输出：

- `==============================================================`
- `5G Runtime Check`
- `==============================================================`
- `REBOOT_ON_FAIL=...  MAX_FAIL_TIMES=...`
- `轮次 | 激活连接 | IP/SIM | 路由/链路 | WARN      | 原因 | IP`
- `-----+----------+--------+-----------+-----------+--------------------+---------------`

之后调用 `nmcli con up "$CONN_NAME"` 尝试拉起连接。

### 稳态巡检

连接成功后，每隔 `STABLE_CHECK_SEC` 秒检测一次：

- 连接是否仍然激活
- 设备是否拿到 IPv4 地址
- 默认路由是否仍然走 `DEVICE_NAME`

发现异常后进入快速重试。

运行阶段按分层逻辑判断异常：

- 连接未激活时，只报 `E03`
- 连接已激活但未获取 IP 时，报 `E04`
- 已获取 IP 但默认路由异常时，报 `E05`

## 日志说明

日志格式如下：

```text
2026-04-02 10:31:16 [START] ==============================================================
2026-04-02 10:31:16 [START] 5G Precheck
2026-04-02 10:31:16 [START] ==============================================================
2026-04-02 10:31:16 [CHECK] 项目        | 状态   | WARN | 说明
2026-04-02 10:31:16 [CHECK] ------------+--------+------+------------------------------
2026-04-02 10:31:16 [CHECK] NetworkMgr | OK     | -    | NetworkManager 已就绪
2026-04-02 10:31:16 [CHECK] 5G 硬件    | OK     | -    | 5G 硬件已就绪
2026-04-02 10:31:16 [CHECK] 设备 pcie1 | OK     | -    | 5G 硬件与设备 pcie1 已就绪
2026-04-02 10:31:16 [START] ==============================================================
2026-04-02 10:31:16 [START] 5G Runtime Check
2026-04-02 10:31:16 [START] ==============================================================
2026-04-02 10:31:16 [START] REBOOT_ON_FAIL=0  MAX_FAIL_TIMES=5
2026-04-02 10:31:16 [CHECK] 轮次 | 激活连接 | IP/SIM | 路由/链路 | WARN      | 原因               | IP
2026-04-02 10:31:16 [CHECK] -----+----------+--------+-----------+-----------+--------------------+---------------
2026-04-02 10:31:16 [CHECK] 1    | OK       | WAIT   | WAIT      | E04       | 未获取IP             | -
2026-04-02 10:31:31 [CHECK] 2    | OK       | OK     | OK        | -         | -                  | 10.67.244.1
```

各字段含义：

- 时间戳：日志产生时间
- `START`：阶段开始
- `CHECK`：检查或重试过程
- `DONE`：阶段成功
- `WARN`：异常但未退出
- `ERROR`：触发重启前的错误
- `原因`：`WARN` 中状态码对应的人类可读说明

### `WARN` 字段说明

当前版本的告警码定义如下：

- `E00`：`NetworkManager` 未就绪
- `E01`：未检测到 5G 硬件
- `E02`：未检测到设备 `pcie1`
- `E03`：目标连接未激活
- `E04`：未获取到 IPv4 地址
- `E05`：默认路由未走 `DEVICE_NAME`

说明：

- 预检查阶段主要关注 `E00`、`E01`、`E02`
- 运行阶段主要关注 `E03`、`E04`、`E05`
- `E03`、`E04`、`E05` 按连接状态分层判断，不再把派生问题一起报出来
- 如果 `WARN` 为 `-`，表示本轮检查未发现异常

## 常见排查

### 1. 服务启动了，但一直无法激活

检查连接名是否正确：

```bash
nmcli con show
```

检查设备名是否正确：

```bash
nmcli device status
```

### 2. 预检查阶段卡住

检查 `NetworkManager` 是否正常：

```bash
systemctl status NetworkManager
```

检查 5G 硬件是否被系统识别：

```bash
lsusb
lspci
```

### 3. 日志文件过大

脚本启动时会按 `MAX_LOG_SIZE` 自动轮转日志。若需要手工清理：

```bash
sudo rm /mnt/sda/logs/5g.log
```

## 建议操作流程

1. 先执行 `nmcli con show` 和 `nmcli device status`
2. 确认 `CONN_NAME` 与 `DEVICE_NAME`
3. 修改 [`5g_runtime.sh`](5g_runtime.sh)
4. 执行 `daemon-reload` 和 `restart`
5. 通过 `tail -f` 或 `journalctl -f` 观察日志
