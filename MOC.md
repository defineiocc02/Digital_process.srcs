# MOC

本文件是仓库内容索引，用来快速定位 SAR ADC 数字后端工程的源码、验证、文档、交付包和可再生成输出。

## 当前维护边界

- 权威源码：`rtl/`
- Vivado 活动工程：`Digital_process/`
- 推荐构建入口：`scripts/build.ps1`
- 推荐仿真入口：`scripts/run_all_xsim.ps1`
- 文档入口：`docs/` 与本文件
- 本地生成物：由 `.gitignore` 忽略，可清理后重新生成

## Core RTL

- `rtl/sar_calib_ctrl_serial.sv` - 串行前台校准控制器
- `rtl/sar_reconstruction.sv` - Q8 权重重构 datapath
- `rtl/srm_residue_estimator.sv` - SRM 残差估计器
- `rtl/sar_calib_fpga_top.sv` - FPGA 演示顶层
- `rtl/sar_adc_digital_top.sv` - ASIC 数字集成 skeleton

Vivado 工程镜像：

- `Digital_process/Digital_process.srcs/sources_1/new/sar_calib_ctrl_serial.sv`
- `Digital_process/Digital_process.srcs/sources_1/new/sar_reconstruction.sv`
- `Digital_process/Digital_process.srcs/sources_1/new/srm_residue_estimator.sv`
- `Digital_process/Digital_process.srcs/sources_1/new/sar_calib_fpga_top.sv`
- `Digital_process/Digital_process.srcs/sources_1/new/sar_adc_digital_top.sv`

## Testbench

- `Digital_process/Digital_process.srcs/sim_1/new/tb_sar_recon_binary_norm.sv` - binary-normalized 20-bit raw code 到 signed 16-bit 重构 smoke test
- `Digital_process/Digital_process.srcs/sim_1/new/tb_recon_q8_split_weights.sv` - Q8 split-cap 权重 bit-exact 验证
- `Digital_process/Digital_process.srcs/sim_1/new/tb_gain_comp_check_lsb.sv` - 校准残差 LSB 检查
- `Digital_process/Digital_process.srcs/sim_1/new/tb_srm_residue_estimator.sv` - SRM LUT 与对称性验证

## Project And Constraints

- `Digital_process/Digital_process.xpr` - Vivado 活动工程
- `Digital_process/Digital_process.srcs/constrs_1/new/sar_calib_fpga.xdc` - Vivado 工程内约束
- `constraints/core_synth.xdc` - 脚本综合默认约束
- `constraints/sar_calib_fpga_legacy_board_hint.xdc` - 板级 hint，需 opt-in
- `constraints/debug_ila_template.xdc` - ILA 模板，需 opt-in

## Scripts

- `scripts/build.ps1` - 推荐综合入口
- `scripts/build_vivado.tcl` - Vivado batch 构建脚本
- `scripts/run_all_xsim.ps1` - XSIM 全量回归入口
- `scripts/run_xsim.ps1` - 单 testbench XSIM 入口
- `scripts/run_core_synth_checks.ps1` - 核心综合检查
- `scripts/synth_one_top.tcl` - 单 top 综合脚本
- `scripts/check_repo_consistency.py` - 仓库一致性检查
- `scripts/lint_verilator.ps1`
- `scripts/lint_verilator.sh`

## Docs

- [docs/VERSION.md](docs/VERSION.md)
- [docs/CHANGELOG.md](docs/CHANGELOG.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)
- [docs/PROJECT_ORGANIZATION.md](docs/PROJECT_ORGANIZATION.md)
- [docs/VERIFICATION.md](docs/VERIFICATION.md)
- [docs/TB_INDUSTRIAL_VERIFICATION_GUIDE.md](docs/TB_INDUSTRIAL_VERIFICATION_GUIDE.md)
- [docs/FIXED_POINT_CONTRACT.md](docs/FIXED_POINT_CONTRACT.md)
- [docs/MIXED_SIGNAL_TIMING_CONTRACT.md](docs/MIXED_SIGNAL_TIMING_CONTRACT.md)
- [docs/ENGINEERING_CLOSURE_AUDIT_2026-05-18.md](docs/ENGINEERING_CLOSURE_AUDIT_2026-05-18.md)
- [docs/FPGA_ASIC_SIGNOFF_REVIEW_2026-05-18.md](docs/FPGA_ASIC_SIGNOFF_REVIEW_2026-05-18.md)
- [docs/REPRODUCTION_REPORT_2026-05-18.md](docs/REPRODUCTION_REPORT_2026-05-18.md)
- [docs/FINAL_REPRODUCTION_AND_VERIFICATION_REPORT_CN_2026-05-18.md](docs/FINAL_REPRODUCTION_AND_VERIFICATION_REPORT_CN_2026-05-18.md)
- [docs/TECHNICAL_ALGORITHM_GAP_ANALYSIS_CN_2026-05-18.md](docs/TECHNICAL_ALGORITHM_GAP_ANALYSIS_CN_2026-05-18.md)
- [docs/HUANG2025_SURROGATE_MODEL_REVIEW_CN_2026-05-26.md](docs/HUANG2025_SURROGATE_MODEL_REVIEW_CN_2026-05-26.md)

## Paper

- [docs/paper/paper_sar_adc_calibration.tex](docs/paper/paper_sar_adc_calibration.tex)
- [docs/paper/paper_sar_adc_calibration.pdf](docs/paper/paper_sar_adc_calibration.pdf)

LaTeX 中间文件按 `.gitignore` 规则清理，不作为仓库内容入口。

## Analysis Models

- [analysis/surrogate/README.md](analysis/surrogate/README.md)
- `analysis/surrogate/replicate_huang2025_calibration_convergence.py` - 量化 16-bit、paired Monte Carlo 收敛代理模型
- `analysis/surrogate/outputs/` - 生成的 CSV/JSON/PNG，已忽略，可重新生成
- [analysis/calibration_effectiveness_20260729/README.md](analysis/calibration_effectiveness_20260729/README.md) - 当前工程片上校准方案验证入口；算法权威为 `sar_calib_ctrl_serial.sv`
- `analysis/calibration_effectiveness_20260729/validate_current_calibration.py` - 当前 RTL 校准 FSM 的行为级等效模型与同决策流验证
- `analysis/calibration_effectiveness_20260729/outputs/summary.json` - 行为级验证摘要
- [analysis/calibration_effectiveness_20260729/report/current_calibration_validation_report_cn.pdf](analysis/calibration_effectiveness_20260729/report/current_calibration_validation_report_cn.pdf) - 当前片上校准有效性中文学术报告
- [analysis/full_sar_behavioral_20260729/README.md](analysis/full_sar_behavioral_20260729/README.md) - 512 点完整 SAR 行为级闭环入口
- `analysis/full_sar_behavioral_20260729/full_sar_model.py` - 采样、20 次差分 SAR、当前 RTL 前台校准、22 次 SRM 和 Q8 重构模型
- `analysis/full_sar_behavioral_20260729/run_campaign.py` - 512 点断点续跑、FFT、DNL/INL、统计聚合与绘图
- `analysis/full_sar_behavioral_20260729/outputs/summary.json` - 512/512 完成状态、配置、聚合指标与代表点
- `analysis/full_sar_behavioral_20260729/outputs/per_chip_decoder_metrics.csv` - 2048 条逐芯片/逐解码器指标
- [analysis/full_sar_behavioral_20260729/report/full_sar_behavioral_validation_cn.pdf](analysis/full_sar_behavioral_20260729/report/full_sar_behavioral_validation_cn.pdf) - 32 页中文学术/工业维护版完整行为级验证报告

## Delivery

- `delivery/sar_adc_v3_digital_core_2026-05-18/` - 冻结 RTL/TB/docs/scripts 交付包
- `delivery/sar_adc_v3_digital_core_2026-05-18/MANIFEST.md`
- `delivery/sar_adc_v3_digital_core_2026-05-18/RUNBOOK.md`
- `delivery/sar_adc_v3_digital_core_2026-05-18/SHA256SUMS.txt`
- `delivery/current_calibration_validation_20260729/` - 当前片上前台校准验证交付包
- `delivery/current_calibration_validation_20260729/README.md`
- `delivery/current_calibration_validation_20260729/MANIFEST.md`
- `delivery/current_calibration_validation_20260729/SHA256SUMS.txt`
- `delivery/current_calibration_validation_20260729/docs/current_calibration_validation_report_cn.pdf`
- `delivery/full_sar_behavioral_validation_20260729/` - 完整 SAR 行为模型、聚合证据、当前 RTL 真值快照和报告
- `delivery/full_sar_behavioral_validation_20260729/MANIFEST.md`
- `delivery/full_sar_behavioral_validation_20260729/SHA256SUMS.txt`
- `delivery/full_sar_behavioral_validation_20260729/report/full_sar_behavioral_validation_cn.pdf`
- [docs/GIT_WORKTREE_AND_BRANCH_AUDIT_2026-07-29.md](docs/GIT_WORKTREE_AND_BRANCH_AUDIT_2026-07-29.md) - Git worktree、Codex 临时目录和分支历史审计

交付包内误生成的 Vivado/XSIM 日志与 `sim_work/` 已按生成物规则清理。

## Archive

- [archive/README.md](archive/README.md)
- `archive/deleted-in-039c478/` - 首次裁剪归档，含 MATLAB 和历史 Vivado 工程
- `archive/deleted-in-110ef75/` - minimal-core 裁剪归档，含旧 top/control/decoder 文件
- Git tag：`archive/full-project-before-core-prune`
- `archive/report_versions/20260729_full_sar_behavioral_v1_simple/` - 被 32 页详细版替换的 9 页报告可恢复归档
- `archive/report_versions/20260729_full_sar_behavioral_v2_before_skill_refresh/` - 最新 PDF Skill 刷新前的 32 页报告与样式归档
- Previous core commit：`039c478`

## Ignored Local Outputs

以下内容视为本地可再生成输出：

- `.Xil/`
- `sim_work/`
- `Digital_process/Digital_process.cache/`
- `Digital_process/Digital_process.hw/`
- `Digital_process/Digital_process.runs/`
- `analysis/surrogate/__pycache__/`
- `analysis/surrogate/outputs/`
- `analysis/*/report/qa_pages*/`
- `*.jou`
- `*.log`
- LaTeX 中间文件，如 `*.aux`、`*.out`、`*.toc`

最后整理：2026-07-29
