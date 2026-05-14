# Requirements

## Scope

本仓库只维护 16-bit split-sampling SAR ADC 数字后端的核心工程。

## Must Keep

- Vivado 工程可打开。
- RTL 顶层、校准、重构、SAR 控制、Flash 译码、虚拟 AFE 模型齐全。
- 系统级和关键模块级 testbench 齐全。
- 约束文件保留。
- 版本说明和恢复标签清晰。

## Must Avoid

- 重复 RTL/TB 备份进入主线。
- 旧工程源码和活动工程混放。
- Vivado 生成物进入 Git。
- 大二进制快照、PDF 参考资料和未引用脚本污染核心代码库。
