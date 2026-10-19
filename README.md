# Digital_process.srcs

![状态](https://img.shields.io/badge/%E7%8A%B6%E6%80%81-RTL_%E5%86%BB%E7%BB%93-bf8700?style=flat-square) ![类型](https://img.shields.io/badge/%E7%B1%BB%E5%9E%8B-RTL_%E9%AA%8C%E8%AF%81-6e7781?style=flat-square) ![技术栈](https://img.shields.io/badge/%E6%8A%80%E6%9C%AF%E6%A0%88-SystemVerilog-6e7781?style=flat-square) ![许可](https://img.shields.io/badge/%E8%AE%B8%E5%8F%AF-%E6%9C%AA%E6%8C%87%E5%AE%9A-6e7781?style=flat-square) [![RTL Lint](https://github.com/defineiocc02/Digital_process.srcs/actions/workflows/rtl_lint.yml/badge.svg)](https://github.com/defineiocc02/Digital_process.srcs/actions/workflows/rtl_lint.yml)  [![Numerical metric controls](https://github.com/defineiocc02/Digital_process.srcs/actions/workflows/numerical-metrics.yml/badge.svg)](https://github.com/defineiocc02/Digital_process.srcs/actions/workflows/numerical-metrics.yml)  [![License](https://img.shields.io/github/license/defineiocc02/Digital_process.srcs)](LICENSE)

> Split-Sampling SAR ADC 的数字后端：前台电容权重校准、SRM 残差估计、Q8 重构，SystemVerilog 实现。

## 这是什么

本仓库实现 Split-Sampling SAR ADC 的数字处理边界：把 20 位差分 SAR 原始判决位流，经校准权重加权求和、SRM 残差修正后还原为 signed 16-bit 输出码。三个可综合模块分别是 P/N 递归前台校准控制器、22 次比较判决的 SRM 残差估计器、Q8 权重重构引擎；配套 Python 行为模型用于 512 chip 的失配与噪声实验。目标是可核对的算法与 RTL 等价性，不包含模拟前端，也不是流片签核工程。

## 当前状态

| 项 | 值 |
|---|---|
| 阶段 | 数字算法核验证完成，RTL 冻结于原位；ASIC 集成与流片前工作未开始 |
| 最近验证 | 2026-10-02 频谱口径修复后独立重跑：完整行为模型 512 chip 与物理 CDAC 主矩阵（512 chip / 7 失配点 / 5 幅度点），[CI 全绿](https://github.com/defineiocc02/Digital_process.srcs/actions/runs/37002707969) |
| 关键指标 | 完整含噪行为模型 CAL+SRM：SNDR 中位 **91.018 dB**（512 chip）；物理 CDAC 零转换噪声主矩阵满幅：SNDR 中位 **95.256 dB**、SNR 中位 **95.383 dB**；理想 16-bit 量化对照 SNR **98.079781 dB** / SNDR **98.079113 dB**。全部为模型条件，非硅片 |
| 结论边界 | 有证据：三个核心 RTL 可综合、4 个 testbench 在 Vivado 2018.3 XSIM 全通过、上述数值可复跑。无证据：AMS/PVT/PEX、ASIC STA、DFT、GDS、硅片 |

当前数字见 [docs/REVALIDATION_20261002.md](docs/REVALIDATION_20261002.md)；2026-07-29 冻结的 PDF/JSON 保留原字节，其频谱数字受 [docs/METRIC_ERRATUM_20261002.md](docs/METRIC_ERRATUM_20261002.md) 约束，不得直接当作当前指标引用。

## 快速开始

### 依赖

- Vivado 2018.3（工程文件由 v2018.3 生成，`scripts/run_all_xsim.ps1` 默认指向 `Vivado/2018.3/bin`）
- Python 3.12
- `numpy==2.1.3`、`pytest==8.3.5`（与 CI 一致）；行为级实验另装 [requirements.txt](analysis/full_sar_behavioral_20260729/requirements.txt)
- verilator + python3（lint 与一致性检查，CI 在 ubuntu-latest 上执行）
- `scripts/*.ps1` 与 `build.ps1` 为 Windows PowerShell 入口，综合与 XSIM 需在 Windows 上跑

### 运行

```bash
python3 scripts/check_repo_consistency.py
bash scripts/lint_verilator.sh
python3 -m pip install numpy==2.1.3 pytest==8.3.5
python3 -m pytest analysis/test_coherent_metrics.py -q
python3 analysis/full_sar_behavioral_20260729/run_campaign.py --quick --chips 4 --workers 2 --no-resume --outdir campaign-recheck
```

综合与 RTL 仿真（Windows）：

```powershell
.\scripts\build.ps1 -Target build_calib_core
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_all_xsim.ps1
```

`build.ps1` 的可用 target 为 `build_calib_core`、`build_recon_core`、`build_fpga_demo`、`build_asic_skeleton`。

### 验证

- 一致性检查最后一行打印 `PASS: repository consistency check completed`；缺文件、残留 `tb_sar_recon.sv`、`core_synth.xdc` 混入板级或 ILA 约束都会报错退出。
- `lint_verilator.sh` 退出码为 0，即 5 个 RTL 文件 lint 通过。
- `pytest analysis/test_coherent_metrics.py` 全通过，覆盖谐波/非谐波、直流、Nyquist、奇偶记录与谐波别名。
- `run_campaign.py` 在 `--outdir` 下写出 `summary.json` 与逐 chip CSV；`main_completed_chips` 等于 `--chips` 即完整。

## 目录结构

```text
rtl/                         权威 RTL 源文件（5 个模块）
Digital_process/             Vivado 活动工程（.xpr 与 sources_1/sim_1 镜像）
constraints/                 综合约束 core_synth.xdc 与可选板级/ILA 模板
scripts/                     Vivado 构建、XSIM 回归、lint、仓库一致性检查
docs/                        架构、定点契约、时序契约、验证与版本文档；paper/ 为论文源
analysis/                    行为模型、物理 CDAC、校准有效性、流片前评审与证据
delivery/                    冻结的交付快照，内含与 docs/、analysis/ 同名的副本，不再修改
archive/                     历史裁剪归档，按删除 commit 命名，不参与构建
MOC.md                       仓库内容索引
```

## 设计与用法

### 模块划分

| 模块 | 文件 | 职责 | 关键参数 |
|---|---|---|---|
| `sar_calib_ctrl_serial` | `rtl/sar_calib_ctrl_serial.sv` | 前台递归校准：以低位已校准电容作参考 DAC，正负两相二分测量高位实际权重，取平均后写回 | `CAP_NUM=20`、`COMP_WAIT_CYC=16`、`AVG_LOOPS=32`、`MAX_CALIB_BIT=5` |
| `srm_residue_estimator` | `rtl/srm_residue_estimator.sv` | 统计 22 次噪声比较器判决，把「1」的个数经正态反函数 LUT 映射为 signed 残差修正 | `DECISION_COUNT=22`、`RESIDUE_WIDTH=30` |
| `sar_reconstruction` | `rtl/sar_reconstruction.sv` | Q8 权重有符号加权求和、差分归一、叠加 SRM 残差、四舍五入并饱和到 16-bit | `FRAC_BITS=8`、`OUTPUT_WIDTH=16`、`INIT_WEIGHT_LSB=256` |
| `sar_calib_fpga_top` | `rtl/sar_calib_fpga_top.sv` | 板级演示 wrapper（按键/复位/指示灯）；比较器输入接确定性 stub，不能用于算法验证 | — |
| `sar_adc_digital_top` | `rtl/sar_adc_digital_top.sv` | ASIC 数字集成 skeleton，串联校准、SRM 与重构；无模式仲裁与 AFE 时序 | — |

`rtl/` 是唯一权威源。`Digital_process/Digital_process.srcs/sources_1/new/` 是 Vivado 工程按路径引用的镜像，`scripts/build_vivado.tcl` 与 `scripts/lint_verilator.sh` 都以 `rtl/` 为准；两者内容必须逐字节一致，改一处要同步另一处。

### 时钟域

- 三个核心模块共用一个时钟 `clk`，复位为异步低有效 `rst_n`，无跨时钟域路径与 CDC 结构。
- 模块间只通过单周期脉冲握手：校准用 `start_calib` / `calib_done`，SRM 用 `start` / `busy` / `done`，重构用 `data_valid_in` / `data_valid_out`。
- `rst_n` 释放后校准控制器把 Bit 0–5 的理想权重装入 Shadow RAM，因此未校准时的重构输出仍有定义。
- 校准是串行累加：每个目标位的权重累加需要 `CAP_NUM` 拍（`S_PHASE_P_CALC` / `S_PHASE_N_CALC`），单次比较等待 `COMP_WAIT_CYC` 拍，每个相位平均 `AVG_LOOPS` 次；`calib_mode_en` 在校准期间保持高。
- 重构为两级流水（4×5 分组部分和 → 全局求和 → 归一/舍入/饱和），`data_valid_in` 到 `data_valid_out` 固定 3 拍延迟。

### 接口

`sar_adc_digital_top` 的端口分组：

| 组 | 信号 | 方向/位宽 | 说明 |
|---|---|---|---|
| 全局 | `clk`、`rst_n` | in | 单时钟，异步低有效复位 |
| 校准控制 | `start_calib`、`calib_comp_out` | in | 启动脉冲与校准期比较器输出 |
| 校准输出 | `calib_done`、`calib_mode_en`、`dac_p_force[19:0]`、`dac_n_force[19:0]` | out | 完成标志、状态指示、P/N 侧 DAC 强制码（抽象控制，非真实 PHY 时序） |
| 重构输入 | `data_valid_in`、`raw_bits[19:0]` | in | 一次转换完成脉冲与 20 位原始判决 |
| SRM 输入 | `srm_start`、`srm_decision_valid`、`srm_decision_bit` | in | 启动脉冲与逐次判决 |
| SRM 输出 | `srm_busy`、`srm_done`、`srm_decision_index[4:0]`、`srm_ones_count[4:0]` | out | 采集状态与计数（上限 22） |
| 数据输出 | `adc_dout[15:0]`、`data_valid_out` | out | signed 16-bit 输出码与有效标志 |

权重写回总线 `w_wr_en` / `w_wr_addr[4:0]` / `w_wr_data[29:0]` 是校准到重构的内部通路，`sar_adc_digital_top` 未引出。

### 位宽约定

- `CAP_NUM=20`：`raw_bits[19:0]`，Bit 0–5 为免校准可信 LSB 段（`MAX_CALIB_BIT=5`），对应 6+4+5+5 物理分段 CDAC 的 20 次判决。
- 权重统一为 signed 30-bit Q22.8：`WEIGHT_WIDTH=30`、`FRAC_BITS=8`，`256` 等于 1 个输出码 LSB；`INIT_WEIGHT_LSB=256` 是 Bit 0 的理想权重。
- 重构累加器为 signed 40-bit；输入侧按 `bit ? +W : -W` 作双侧求和，再算术右移 1 位完成差分归一。
- 输出为 signed 16-bit，饱和到 `+32767 / -32768`；舍入加 `2^(FRAC_BITS-1)` 补偿 floor 截断带来的 -0.5 LSB 系统性偏置。
- `srm_residue` 与权重同一 Q8 单位，在归一之后、输出移位之前注入；`+256` 表示未饱和时 +1 个输出码 LSB。
- RTL 内有参数守卫：`CAP_NUM=20`、`WEIGHT_WIDTH≥30`、`OUTPUT_WIDTH=16`、`FRAC_BITS=8` 以外的配置直接 `$error`，4×5 分组流水只对 20 位成立。

## 已知限制

- 只有数字边界：`dac_p_force` / `dac_n_force` 是抽象强制码，没有 VCM/SET/RSTT/CLKAZ/READYN 等实际 PHY 序列，也没有与异步 SAR 的 EOC/code 原子锁存时序。
- `sar_adc_digital_top` 自述为 skeleton：无 normal/calibration/SRM 模式仲裁；`srm_residue_q` 无 transaction ID、freshness 与 `srm_done` 门控，连续转换时旧残差可能被套用到新 raw code。
- 512 chip 物理 CDAC 结论建立在模型假设上（6+4+5+5 分段、8 fF 单位电容、面积律失配），没有 PDK 失配卡、全电路 PVT、PEX 或真实 ADC 接入。
- 满幅下 CAL_CURRENT_SRM 的 SNDR ≥90 dB 只有 504/512，尾部失败样本保留在逐 chip CSV；`CAL_HEADROOM_GUARD_SRM` 的 512/512 是后处理分析结果，未进入 RTL。
- 2026-07-29 冻结的交付 PDF 与旧 summary 保留历史口径，其 SNR/SNDR 存在已确认矛盾，只能作为历史记录引用。
- 无 ASIC 库、SDC/MMMC、CDC/RDC、LEC、DFT 证据，也无 routed layout；见 [流片前总评审](analysis/full_flow_tapeout_review_20260830/SAR16B_RTL_TO_SILICON_MASTER_REVIEW_CN.md)。

## 相关仓库

暂无直接关联的仓库。

## 许可

[MIT License](LICENSE)，Copyright 2026 Zhao Yi。
