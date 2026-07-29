# 撤回说明

本目录保存一次直接对 effective reconstruction weights 注入失配的压力测试。

该测试采用 bit0 至 bit5 为 `0.15% rms`、bit6 至 bit19 为 `3% rms` 的人工权重扰动。该参数来自历史 SystemVerilog regression TB，并非用户指定条件、论文参数、PDK 电容模型或物理 CDAC Monte Carlo 结果。

因此：

- 本目录仅作为可追溯的历史压力测试归档；
- 其中结果不得作为项目正式失配能力结论；
- 正式实验位于 `analysis/physical_cdac_mismatch_20260729/`；
- 正式实验先扰动物理 bit capacitors、bridge capacitors 和 parasitics，再通过分段 CDAC 电容矩阵求解 effective weights。
