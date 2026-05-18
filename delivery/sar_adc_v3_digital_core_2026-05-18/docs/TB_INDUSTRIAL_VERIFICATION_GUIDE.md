# TB Industrial Verification Guide

日期：2026-05-18

本文档说明当前交付包中三份核心 Testbench 的工业级维护要求。代码内注释以英文为主，本文档用中文解释审阅、运行和后续维护方法。

## 交付范围

| Testbench | DUT | 主要目的 |
| --- | --- | --- |
| `tb_sar_recon.sv` | `sar_reconstruction` | 验证校准权重重构、权重写入响应、流水 valid 传递、SRM 残差注入 |
| `tb_srm_residue_estimator.sv` | `srm_residue_estimator` | 验证 22 次 SRM comparator decision 到 signed Q8 residue 的 LUT 映射 |
| `tb_gain_comp_check_lsb.sv` | `sar_calib_ctrl_serial` | 用 Monte Carlo 行为模型验证前台递归校准、噪声/offset 鲁棒性和 gain compensation |

## 注释规范

每份 TB 需要保持以下英文注释结构：

- 文件头：包含 target、purpose、tool scope、language、design intent、verification scope、interface assumptions、testbench architecture、pass criteria。
- 参数区：说明参数与 RTL 默认值或复现报告的对应关系。
- DUT interface：区分 clock/reset、控制握手、数据端口、写回端口。
- Driver/monitor/scoreboard：说明任务或 always block 在验证结构中的角色。
- Golden model：说明 golden LUT、理想权重或行为模型的来源和适用边界。
- Failure policy：所有检查必须通过统一 checker 记录，失败时调用 `$fatal`，保证批处理仿真返回失败状态。

## 工业维护约束

- 不允许把核心算法判断分散在多个临时 `$display` 中；新增检查必须走 `record_check`。
- 不允许让 TB 在失败后继续运行并打印 PASS；所有 fail path 必须立即 `$fatal`。
- 不允许依赖 waveform 才能判断 PASS/FAIL；文本 transcript 必须能独立说明结果。
- 新增随机或 Monte Carlo 场景必须固定 seed，保证失败可复现。
- 修改 RTL 行为后必须同步更新 `docs/VERIFICATION.md` 的 latest run 区域和最终复现报告中的结果表。
- 交付包 `delivery/sar_adc_v3_digital_core_2026-05-18/` 中的 TB 必须与 active Vivado 工程 TB 保持一致。

## 当前覆盖解释

### `tb_sar_recon.sv`

- 使用 `generate_ideal_bits` 构造归一化输入到 raw SAR decision 的理想映射。
- 使用 `load_ideal_weights` 写入可审计的单调权重表，避免把校准复杂性混入重构单元测试。
- `test_linearity` 检查 20 个输入点，误差容限为 `+/-1 code`。
- `test_weight_update` 验证 MSB 权重写入确实影响输出，防止权重端口失效。
- `test_pipeline_throughput` 验证连续 sample valid 不丢失。
- `test_srm_residue_injection` 验证 signed Q8 residue 对最终输出产生预期的一码修正。

### `tb_srm_residue_estimator.sv`

- 本地 golden LUT 明确列出 0 到 22 个 ones_count 对应的 signed Q8 residue。
- 覆盖负边界、近负边界、中点、近正边界、正边界。
- 检查 `done`、`ones_count`、`residue_q` 三个外部可见结果。
- 额外检查 LUT 关于中点的对称性，防止 LUT 录入或符号方向错误。

### `tb_gain_comp_check_lsb.sv`

- 行为 analog model 使用 real-valued capacitor weights，单位为 Q8。
- `manufacture_chip` 注入确定性 capacitor mismatch。
- comparator model 注入固定 offset 和逐周期 Gaussian noise。
- writeback monitor 捕获 DUT 输出的 calibrated weights。
- `analyze_run` 使用 MSB anchor 做 gain compensation，并对 bit 6 到 bit 19 检查 residual error。
- 当前 pass limit 为 `0.5 LSB`，用于复现论文算法边界的数字校准效果，不等价于最终 silicon signoff。

## 运行命令

从工程根目录运行完整 XSIM 回归：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

从交付包根目录运行同一套完整 XSIM 回归：

```powershell
cd delivery\sar_adc_v3_digital_core_2026-05-18
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

从交付包根目录运行包内综合检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_package_synth_checks.ps1
```

从工程根目录运行 active RTL 综合检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_core_synth_checks.ps1
```

## 后续修改检查单

修改任何 RTL/TB 后，至少完成以下检查：

- `git diff --check`
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1`
- 若 RTL 逻辑变化，运行 `scripts\run_core_synth_checks.ps1`
- 同步 `delivery/` 包内 RTL/TB/docs/scripts
- 更新 `SHA256SUMS.txt`
- 更新 `docs/CHANGELOG.md` 与 `docs/VERSION.md`
