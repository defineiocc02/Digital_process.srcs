# 目录规范

## 规范原则

1. 主工程路径不轻易移动：`Digital_process/Digital_process.xpr` 保持原位。
2. 仓库顶层只放入口文件、文档目录、活动工程目录、MATLAB 工具目录和归档目录。
3. Vivado 生成物不进入 Git：`.runs/.sim/.cache/.hw/.ip_user_files` 都由 `.gitignore` 过滤。
4. 历史工程不与活动工程混放，统一进入 `archive/legacy_vivado_projects/`。
5. 大二进制快照只用于人工恢复，不作为源码评审对象。

## 当前目录职责

| 目录 | 职责 |
| --- | --- |
| `Digital_process/` | 当前活动 Vivado 工程 |
| `docs/` | 新整理的工程化文档 |
| `matlab/` | MATLAB 分析、LUT 和噪声脚本 |
| `archive/` | 历史工程与二进制快照 |

## 活动源码边界

活动 RTL 只认 `Digital_process/Digital_process.srcs/sources_1/new/`。旧工程中的同名文件只能作为参考，不应直接改了以后认为主工程已更新。

## 归档策略

- `archive/legacy_vivado_projects/` 保存旧的 `sar_adc_project` 和 `Verifiy` 工程。
- `archive/binary_snapshots/` 保存原始 `.rar` 快照。
- 归档文件默认不作为主线维护对象。

## 提交策略

建议每次提交包含一个清晰目的：

- `docs:` 文档或 MOC 更新。
- `rtl:` RTL 行为或结构调整。
- `tb:` testbench 调整。
- `chore:` 目录、忽略规则、归档和工程维护。

Vivado 生成物即使本地存在，也不应加入提交。
