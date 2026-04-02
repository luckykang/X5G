智能融合感知终端显示系统
所有显著的版本更新都会记录在本文件中，遵循 Keep a Changelog 规范，项目版本号遵循 语义化版本。

📌 版本更新记录

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