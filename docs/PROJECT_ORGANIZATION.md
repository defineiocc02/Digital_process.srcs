# Project Organization

当前仓库采用核心工程版结构，只保留能支撑 Vivado 打开、RTL 开发和基本仿真的文件。

## 保留规则

- 保留活动 Vivado 工程：`Digital_process/Digital_process.xpr`
- 保留活动 RTL：`Digital_process/Digital_process.srcs/sources_1/new/`
- 保留活动 testbench：`Digital_process/Digital_process.srcs/sim_1/new/`
- 保留活动约束：`Digital_process/Digital_process.srcs/constrs_1/new/`
- 保留顶层文档：`README.md`、`MOC.md`、`docs/`

## 删除规则

- 不保留重复 RTL/TB 备份目录。
- 不保留旧 Vivado 工程目录。
- 不保留 Vivado 生成目录：`.runs`、`.sim`、`.cache`、`.hw`。
- 不保留大二进制和参考 PDF。
- 不保留未被核心工程引用的 MATLAB 辅助脚本。

## 归档方式

使用 Git 历史和标签归档。当前核心化前的完整整理版标签为：

```bash
git checkout archive/full-project-before-core-prune
```

这样主线目录保持轻量，历史资料仍可追溯。
