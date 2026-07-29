# SAR ADC 数字处理系统

本仓库维护 Split-Sampling SAR ADC 的数字后端处理逻辑，重点覆盖前台校准、SAR 码重构、SRM 残差估计，以及 FPGA/Vivado 验证入口。

当前工程基线为 **v3.11.0-physical-cdac-revalidation**。本版本以当前 RTL 为算法真值，从 `6+4+5+5` 物理分段CDAC、电容面积律失配、20次差分SAR判决、P/N递归前台校准、22次SRM、Q8重构到16-bit输出完成512芯片再验证，并发布27页中文学术/工业维护报告。ADCToolbox仅用于标准化指标计算，不替代本工程 `sar_calib_ctrl_serial.sv`、`srm_residue_estimator.sv` 和 `sar_reconstruction.sv`。

## 目录结构

```text
sar_adc_v3/
|-- rtl/                         # 权威 RTL 源文件
|-- Digital_process/             # Vivado 活动工程；srcs 下保持与 rtl/ 同步
|-- constraints/                 # 推荐约束入口与板级/debug 可选模板
|-- scripts/                     # Vivado 构建、XSIM 回归、lint/一致性检查脚本
|-- docs/                        # 架构、契约、验证、版本与评审文档
|   `-- paper/                   # SAR ADC 校准论文源文件与 PDF
|-- analysis/surrogate/          # Huang 2025 收敛代理分析
|-- analysis/calibration_effectiveness_20260729/
|                                 # 当前 RTL 片上校准行为级有效性验证
|-- analysis/full_sar_behavioral_20260729/
|                                 # 512 点完整 SAR 行为级闭环与报告
|-- analysis/physical_cdac_mismatch_20260729/
|                                 # 物理CDAC失配、当前校准与SRM正式再验证
|-- delivery/                    # 冻结交付包与行为级验证包
|-- archive/                     # 历史裁剪归档
|-- MOC.md                       # 内容索引
|-- README.md                    # 本文件
`-- LICENSE
```

生成物清理约定：

- Vivado/XSIM 输出、日志、`.Xil/`、`sim_work/`、`.cache/`、`.hw/`、`.runs/` 都视为可再生成文件。
- LaTeX 中间文件如 `*.aux`、`*.log`、`*.out` 不进入仓库。
- 代理分析输出目录 `analysis/surrogate/outputs/` 可由脚本重新生成。
- 完整行为模型的逐点检查点与运行日志可再生成，不进入仓库；聚合 CSV、JSON、图和代表性高分辨率数组作为验证证据保留。
- PDF 视觉 QA 渲染页缓存 `analysis/*/report/qa_pages*/` 可由 Poppler 重新生成。
- 本地参考文献缓存 `.tmp_literature/` 保留为本机资料缓存，不作为源码交付内容。

## 快速开始

### 一致性检查

```powershell
python scripts\check_repo_consistency.py
```

### XSIM 回归

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

### Vivado 综合目标

```powershell
.\scripts\build.ps1 -Target build_calib_core
.\scripts\build.ps1 -Target build_recon_core
.\scripts\build.ps1 -Target build_fpga_demo
.\scripts\build.ps1 -Target build_asic_skeleton
```

### 完整行为级 512 点验证

```powershell
$py = "C:\Users\Administrator\Desktop\ADCToolbox_EVAL_20260728\envs\upstream-main\Scripts\python.exe"

& $py -m pytest analysis\full_sar_behavioral_20260729\test_full_sar_model.py -q
& $py analysis\full_sar_behavioral_20260729\run_campaign.py --chips 512 --workers 6
```

运行支持逐芯片检查点和断点续跑；正式聚合结果位于
`analysis/full_sar_behavioral_20260729/outputs/`。

### 物理CDAC失配正式再验证

```powershell
& $py -m pytest `
  analysis\physical_cdac_mismatch_20260729\test_physical_cdac.py `
  analysis\physical_cdac_mismatch_20260729\test_revalidation.py -q
& $py analysis\physical_cdac_mismatch_20260729\run_revalidation.py `
  --chips 512 --sensitivity-chips 128 --amplitude-chips 128 --workers 6
```

正式证据位于 `analysis/physical_cdac_mismatch_20260729/outputs_revalidation/`。

### Vivado GUI 工程

```text
Digital_process/Digital_process.xpr
```

GUI 工程便于调试和查看工程状态；脚本入口仍是可复现构建的推荐入口。

## 核心模块

| 模块 | 位置 | 说明 |
| --- | --- | --- |
| `sar_calib_ctrl_serial` | `rtl/sar_calib_ctrl_serial.sv` | 前台电容权重校准控制器 |
| `sar_reconstruction` | `rtl/sar_reconstruction.sv` | 基于 Q8 权重的 20-bit raw code 到 signed 16-bit 重构 |
| `srm_residue_estimator` | `rtl/srm_residue_estimator.sv` | 22 次噪声比较器判决统计与残差 LUT 映射 |
| `sar_calib_fpga_top` | `rtl/sar_calib_fpga_top.sv` | FPGA 演示/综合 wrapper，不作为 ASIC 顶层 |
| `sar_adc_digital_top` | `rtl/sar_adc_digital_top.sv` | ASIC 数字集成 skeleton |

Vivado 工程中的镜像文件位于 `Digital_process/Digital_process.srcs/sources_1/new/`。维护时优先修改 `rtl/`，再同步到 Vivado 工程镜像。

## 验证基线

2026-07-29 物理CDAC失配与当前片上自校准再验证：

| 验证层 | 入口 | 结果 |
| --- | --- | --- |
| 理想16位算术门限 | `run_revalidation.py` | PASS；直接量化98.079 dB，精确物理残差98.079 dB，确定性SRM 98.045 dB，随机22次SRM中位97.145 dB |
| 512芯片物理失配 | `outputs_revalidation/summary.json` | PASS；当前校准满幅中位95.256 dB，回退中位93.577 dB，DNL max中位0.968 LSB，INL max中位0.993 LSB，缺码中位0 |
| 满幅余量tail | `CAL_HEADROOM_GUARD_SRM` | 分析候选；最差值55.619 -> 93.129 dB，512/512超过90 dB；尚未进入RTL |
| Python回归与回放 | `test_revalidation.py` | PASS；11 tests；8芯片双重回放7个CSV/JSON逐字节一致 |
| 详细PDF | `report_revalidation/physical_cdac_revalidation_cn.pdf` | PASS；27页；发布/字体/ToUnicode/逐页视觉/确定性重建门限全通过 |

2026-07-29 完整行为级闭环验证：

| 验证层 | 入口 | 结果 |
| --- | --- | --- |
| 512 点完整 SAR 行为模型 | `analysis/full_sar_behavioral_20260729/run_campaign.py` | PASS；512/512 完成；校准+SRM 的 SNDR 中位数 91.018 dB、SFDR 中位数 108.776 dBc、INL 峰峰值中位数 2.015 LSB |
| 高分辨率静态复核 | `analysis/full_sar_behavioral_20260729/outputs/highres_*.npz` | Best/Median/Worst 每码 8 点；最坏代表点 2 个缺码 |
| Python 单元/闭环测试 | `analysis/full_sar_behavioral_20260729/test_full_sar_model.py` | PASS；5 tests |
| PDF 发布检查 | `analysis/full_sar_behavioral_20260729/report/full_sar_behavioral_validation_cn.pdf` | PASS；32 页；最新 Skill 双门禁与两次确定性构建一致；SHA-256 `9F4B01E4E69AB5FE2E1230CCB57DEBF63A07ECB83540F1954D86A910D1E8D731` |

本轮结果是完整系统行为级证据，不是 AMS、PVT、PEX 或硅片签核。512 点中校准+SRM 路径缺码中位数为 0，但最坏值为 18；该尾部风险保留在报告和逐芯片 CSV 中。

2026-07-29 当前片上校准算法验证：

| 验证层 | 入口 | 结果 |
| --- | --- | --- |
| 行为级当前 RTL 等效模型 | `analysis/calibration_effectiveness_20260729/validate_current_calibration.py` | PASS；SNDR 中位数 36.214 dB -> 92.007 dB；权重 RMSE 147.9781 LSB -> 0.1908 LSB |
| Vivado XSIM RTL 回归 | `scripts/run_all_xsim.ps1` | PASS；4 个 testbench 全通过 |
| PDF 发布检查 | `analysis/calibration_effectiveness_20260729/report/current_calibration_validation_report_cn.pdf` | PASS；7 页；SHA-256 `AD3211EB6F7FB82D5266801FC015C1BAFB60218917849C4D9FCF2AFF4F2A8C70` |

当前校准验证交付包见 `delivery/current_calibration_validation_20260729/`。
完整行为级交付包见 `delivery/full_sar_behavioral_validation_20260729/`。

2026-05-18 工程闭合基线：

| Testbench | 目标 | 结果 |
| --- | --- | --- |
| `tb_sar_recon_binary_norm.sv` | `sar_reconstruction` | PASS, 49 checks, 0 failed |
| `tb_recon_q8_split_weights.sv` | `sar_reconstruction` + SRM | PASS, 17 checks, 0 failed |
| `tb_srm_residue_estimator.sv` | `srm_residue_estimator` | PASS, 17 checks, 0 failed |
| `tb_gain_comp_check_lsb.sv` | `sar_calib_ctrl_serial` | PASS, 5 Monte Carlo runs, worst residual 0.4937 LSB |

| 综合目标 | Top | 结果 | WNS |
| --- | --- | --- | --- |
| `build_calib_core` | `sar_calib_ctrl_serial` | PASS | 5.449 ns |
| `build_recon_core` | `sar_reconstruction` | PASS | 3.999 ns |
| `build_fpga_demo` | `sar_calib_fpga_top` | PASS | 5.441 ns |
| `build_asic_skeleton` | `sar_adc_digital_top` | PASS | 3.957 ns |

最新验证细节见 [docs/VERIFICATION.md](docs/VERIFICATION.md)。

## 文档入口

- [MOC.md](MOC.md): 仓库内容索引
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): 架构说明
- [docs/FIXED_POINT_CONTRACT.md](docs/FIXED_POINT_CONTRACT.md): Q8 定点契约
- [docs/MIXED_SIGNAL_TIMING_CONTRACT.md](docs/MIXED_SIGNAL_TIMING_CONTRACT.md): 混合信号时序契约
- [docs/VERIFICATION.md](docs/VERIFICATION.md): 验证状态与维护规则
- [docs/PROJECT_ORGANIZATION.md](docs/PROJECT_ORGANIZATION.md): 项目组织说明
- [docs/GIT_WORKTREE_AND_BRANCH_AUDIT_2026-07-29.md](docs/GIT_WORKTREE_AND_BRANCH_AUDIT_2026-07-29.md): Git worktree、临时目录与分支收敛审计
- [docs/HUANG2025_SURROGATE_MODEL_REVIEW_CN_2026-05-26.md](docs/HUANG2025_SURROGATE_MODEL_REVIEW_CN_2026-05-26.md): Huang 2025 代理模型接入评审
- [docs/paper/paper_sar_adc_calibration.tex](docs/paper/paper_sar_adc_calibration.tex): 论文源文件
- [docs/paper/paper_sar_adc_calibration.pdf](docs/paper/paper_sar_adc_calibration.pdf): 论文 PDF
- [analysis/calibration_effectiveness_20260729/README.md](analysis/calibration_effectiveness_20260729/README.md): 当前片上校准算法验证说明
- [analysis/calibration_effectiveness_20260729/report/current_calibration_validation_report_cn.pdf](analysis/calibration_effectiveness_20260729/report/current_calibration_validation_report_cn.pdf): 当前片上校准有效性验证报告
- [analysis/full_sar_behavioral_20260729/README.md](analysis/full_sar_behavioral_20260729/README.md): 完整 SAR 行为模型、运行口径与结果入口
- [analysis/full_sar_behavioral_20260729/report/full_sar_behavioral_validation_cn.pdf](analysis/full_sar_behavioral_20260729/report/full_sar_behavioral_validation_cn.pdf): 512 点完整行为级验证报告
- [analysis/physical_cdac_mismatch_20260729/README.md](analysis/physical_cdac_mismatch_20260729/README.md): 物理CDAC失配正式再验证入口
- [analysis/physical_cdac_mismatch_20260729/report_revalidation/physical_cdac_revalidation_cn.pdf](analysis/physical_cdac_mismatch_20260729/report_revalidation/physical_cdac_revalidation_cn.pdf): 27页详细中文再验证报告
- [delivery/current_calibration_validation_20260729/README.md](delivery/current_calibration_validation_20260729/README.md): 当前校准验证交付包入口
- [delivery/full_sar_behavioral_validation_20260729/README.md](delivery/full_sar_behavioral_validation_20260729/README.md): 完整行为级交付包入口

## 版本信息

- 版本号：`v3.11.0-physical-cdac-revalidation`
- 日期：2026-07-29
- 状态：Main-Unified Physical-CDAC Revalidation Baseline
- 工程闭合 tag：`v3.6.0-engineering-closure`

## 许可证

本项目使用 [MIT License](LICENSE)。

最后整理：2026-07-29
