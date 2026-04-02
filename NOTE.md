智能融合感知终端显示系统
所有显著的版本更新都会记录在本文件中，遵循 Keep a Changelog 规范，项目版本号遵循 语义化版本。

📌 版本更新记录

[v2.2] - 2026-04-02
#### optimized
- 收紧移远模块识别：E01 现在优先按 Quectel 特征匹配，不再用过宽的 Wireless/Communication 模糊词。
- 强化设备就绪判断：E02 不再只看 pcie1 名字是否出现，还会排除 unavailable、unmanaged。
- E03/E04/E05 改成分层判断：连接未激活，只报 E03，连接已激活但没 IP，只报 E04，有 IP 但默认路由异常，只报 E05
- 日志轮转改成运行期生效：现在每次写日志前都会检查大小，不再只在脚本启动时轮转一次。
- 预检查加心跳日志：超过 PRECHECK_TIMEOUT_SEC 后不会静默卡住，会按 PRECHECK_HEARTBEAT_SEC 周期继续打印 WAIT。

[v2.1] - 2026-04-02
#### optimized
- 优化错误码：支持E01、E02预检查错误码打印；新增连接未激活”状态E03；
- 日志打印输出格式优化：改为状态码+原因，提高易读性；

[v2.0] - 2026-04-01
#### optimized
-  precheck阶段逻辑合并到runtime阶段；
-  去掉跨服务依赖，改成脚本自己等待和重试；
-  ExecStartPre=/bin/sleep 1 已去掉，改成脚本内显式等待；
-  Restart=no 已改成 Restart=on-failure；