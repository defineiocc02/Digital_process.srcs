# SAR ADC 数字处理系统

## 📋 项目简介

本工程实现了 **Split-Sampling SAR ADC 的数字后端处理系统**，包含三大核心功能：

- **校准 (Calibration)**：递归测量电容权重，实现高精度前台校准
- **重构 (Reconstruction)**：使用校准权重对 SAR 原始数据进行加权求和，输出 16 位数字码
- **SRM 残差估计 (SRM Residue Estimation)**：22 次噪声比较器判决统计 + LUT 映射，提供亚 LSB 残差修正

当前版本为 **v3.6.1 工程整洁度基线**：三核心 RTL 通过 XSIM 仿真，核心、FPGA demo 与 ASIC skeleton 均有明确 Vivado build target（Artix-7 xc7a35tfgg484-2, 100 MHz），约束层拆分完毕，CI/lint 基础设施就绪。

## 🏗️ 目录结构

```
sar_adc_v3/
├── rtl/                              # 📦 权威 RTL 源文件（5 文件）
│   ├── sar_calib_ctrl_serial.sv      #   校准控制器
│   ├── sar_reconstruction.sv         #   重构数据通路
│   ├── srm_residue_estimator.sv      #   SRM 残差估计器
│   ├── sar_calib_fpga_top.sv         #   FPGA 演示顶层
│   └── sar_adc_digital_top.sv        #   ASIC 数字集成顶层
├── Digital_process/                  # 🖥️ Vivado 活动工程
│   ├── Digital_process.xpr
│   └── Digital_process.srcs/
│       ├── sources_1/new/            #   RTL（与 rtl/ 同步）
│       ├── sim_1/new/                #   4 套 Testbench
│       └── constrs_1/new/            #   约束（历史参考）
├── constraints/                      # ⚙️ 权威约束文件
│   ├── core_synth.xdc                #   核心综合约束（默认）
│   ├── sar_calib_fpga_legacy_board_hint.xdc  # 板级 hint（需 opt-in）
│   └── debug_ila_template.xdc        #   ILA 模板（需 opt-in）
├── docs/                             # 📚 项目文档（14 文件）
│   ├── FIXED_POINT_CONTRACT.md       #   定点算术契约
│   ├── MIXED_SIGNAL_TIMING_CONTRACT.md  # 混合信号时序契约
│   ├── VERIFICATION.md               #   验证状态
│   ├── ENGINEERING_CLOSURE_AUDIT_2026-05-18.md  # 工程闭合审计报告
│   └── ...
├── scripts/                          # 🛠️ 构建与仿真脚本
│   ├── build.ps1 / build_vivado.tcl  #   权威综合入口
│   ├── run_all_xsim.ps1 / run_xsim.ps1  # XSIM 回归
│   ├── synth_one_top.tcl             #   旧版综合脚本（保留）
│   ├── check_repo_consistency.py     #   仓库一致性检查
│   └── lint_verilator.sh / .ps1      #   Verilator lint
├── delivery/                         # 📦 冻结交付包
│   └── sar_adc_v3_digital_core_2026-05-18/
├── archive/                          # 🗄️ 历史归档
│   ├── deleted-in-039c478/           #   首次裁剪归档（MATLAB、旧工程）
│   └── deleted-in-110ef75/           #   最小核心裁剪归档（旧 top/controller）
├── .github/                          # 🔧 CI / Copilot 配置
│   ├── workflows/rtl_lint.yml
│   └── copilot-instructions.md
├── MOC.md                            #   内容主列表
├── README.md                         #   本文件
└── LICENSE                           #   MIT 许可证
```

## 🚀 快速开始

### 1. 综合（推荐使用权威脚本，不依赖 .xpr 的 top 设置）

```powershell
.\scripts\build.ps1 -Target build_calib_core
.\scripts\build.ps1 -Target build_recon_core
.\scripts\build.ps1 -Target build_fpga_demo
.\scripts\build.ps1 -Target build_asic_skeleton
```

### 2. 运行仿真

```powershell
# 四套 TB 一键回归
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

### 3. Vivado GUI 工程（非权威入口）

```text
Digital_process/Digital_process.xpr
```

### 4. 轻量 CI / Lint

```bash
python3 scripts/check_repo_consistency.py
bash scripts/lint_verilator.sh
```

## 📦 核心模块说明

### 校准控制器 — `sar_calib_ctrl_serial.sv`

- **功能**：实现递归 "先测后设" (Measure-then-Set) 前台校准算法，使用低位已校准电容作为参考 DAC，通过二进制搜索测量高位电容实际权重
- **关键特性**：
  - 串行累加架构（v2.0），消除组合逻辑时序瓶颈
  - MSB 保护逻辑（Bit-Swapping），压缩共模范围
  - 差分测量 (P+N)/2，消除比较器 offset
  - ASIC 安全复位策略，复位期间自动加载理想参考权重
  - FSM safe default + 参数 guard（CAP_NUM=20 等）

### 重构引擎 — `sar_reconstruction.sv`

- **功能**：使用校准权重对 SAR raw_bits 进行加权求和，输出 16 位有符号数字码
- **关键特性**：
  - 两级流水线：4 组 × 5 bit 部分累加 → 全局累加 → 缩放/舍入/饱和
  - 40 位动态范围防止中间溢出
  - +0.5 LSB 舍入补偿（消除 Floor 截断系统偏差）
  - SRM 残差注入（在输出缩放前，保持 Q 格式一致）
  - 动态权重更新接口（来自校准控制器）

### SRM 残差估计器 — `srm_residue_estimator.sv`

- **功能**：统计 22 次噪声比较器判决，通过 normal-inverse CDF LUT 输出有符号残差修正值
- **关键特性**：
  - 22 个判决固定 LUT（sigma=0.5 LSB, Q8 格式）
  - 稀疏 decision_valid 脉冲接口，适配异步比较器 wrapper
  - 自动清零 + 单次采集 FSM
  - LUT 对称性已通过 TB 验证

### FPGA 演示顶层 — `sar_calib_fpga_top.sv`

- **功能**：FPGA 板级演示 wrapper，仅用于 build_fpga_demo target
- **关键特性**：
  - 适配 ACX720-V3 板级端口（clk / rst_n_btn / start_sw / done_led）
  - 确定性 comparator stub（综合闭合用，不做算法验证）
  - mark_debug 探针预留 ILA 接口
  - **不进 ASIC**

### ASIC 数字集成顶层 — `sar_adc_digital_top.sv`

- **功能**：ASIC 方向数字集成 skeleton，连接校准 + SRM + 重构
- **关键特性**：
  - 纯信号接口，无 FPGA button/LED/ILA
  - 校准权重写回 → reconstruction
  - SRM residue → reconstruction
  - 不含 SAR controller / mode arbitration / register bus（后续里程碑）

## 📊 技术参数

| 参数 | 值 | 说明 |
|------|-----|------|
| CAP_NUM | 20 | 电容总位数 |
| WEIGHT_WIDTH | 30 | 权重位宽（有符号, Q18.12） |
| OUTPUT_WIDTH | 16 | 输出数据位宽 |
| FRAC_BITS | 8 | 权重小数位数（Q8） |
| AVG_LOOPS | 32 | 校准平均次数（2 的幂） |
| COMP_WAIT_CYC | 16 | 比较器/DAC 建立等待周期 |
| MAX_CALIB_BIT | 5 | 免校准 LSB 段最高位 |
| REF_WEIGHT_LSB | 256 | Bit 0 参考权重（Q8 = 1.0） |
| SRM DECISION_COUNT | 22 | SRM 噪声判决次数 |
| 目标器件 | xc7a35tfgg484-2 | Artix-7 |
| 时钟频率 | 100 MHz / 10 ns | 核心综合约束 |

## ⚙️ 构建目标策略

| Target | Top Module | 用途 | 约束 |
|--------|-----------|------|------|
| `build_calib_core` | `sar_calib_ctrl_serial` | 校准核心独立综合 | core_synth.xdc |
| `build_recon_core` | `sar_reconstruction` | 重构核心独立综合 | core_synth.xdc |
| `build_fpga_demo` | `sar_calib_fpga_top` | FPGA 演示综合 | core_synth.xdc |
| `build_asic_skeleton` | `sar_adc_digital_top` | ASIC 数字集成 skeleton 综合 | core_synth.xdc |

板级约束和 ILA 模板**默认不启用**，通过环境变量 opt-in：

```powershell
$env:USE_BOARD_XDC = "1"
$env:USE_DEBUG_XDC = "1"
.\scripts\build.ps1 -Target build_fpga_demo
```

## ✅ 验证状态（2026-05-18）

| Testbench | Target | 结果 |
|-----------|--------|------|
| `tb_sar_recon_binary_norm.sv` | `sar_reconstruction` | PASS, 49 checks, 0 failed |
| `tb_recon_q8_split_weights.sv` | `sar_reconstruction` + SRM | PASS, 17 checks, 0 failed |
| `tb_srm_residue_estimator.sv` | `srm_residue_estimator` | PASS, 17 checks, 0 failed |
| `tb_gain_comp_check_lsb.sv` | `sar_calib_ctrl_serial` | PASS, 5 MC runs, 最差残差 0.4937 LSB |

| 综合 Target | 结果 | LUT | FF | WNS |
|------------|------|-----|-----|-----|
| `build_calib_core` | PASS | 511 | 821 | 5.450 ns |
| `build_recon_core` | PASS | 950 | 818 | 3.999 ns |
| `build_fpga_demo` | PASS | 462 | 821 | 5.441 ns |
| `build_asic_skeleton` | PASS | 1518 | 1661 | 3.957 ns |

## 📚 文档

### 核心契约
- [docs/FIXED_POINT_CONTRACT.md](docs/FIXED_POINT_CONTRACT.md) — Q8 定点算术契约
- [docs/MIXED_SIGNAL_TIMING_CONTRACT.md](docs/MIXED_SIGNAL_TIMING_CONTRACT.md) — 混合信号时序契约（comparator/SRM/reconstruction/reset/CDC 分类）

### 工程文档
- [docs/ENGINEERING_CLOSURE_AUDIT_2026-05-18.md](docs/ENGINEERING_CLOSURE_AUDIT_2026-05-18.md) — 工程闭合审计报告（8 commits, 42 files, +3933/-82）
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 架构设计说明
- [docs/VERIFICATION.md](docs/VERIFICATION.md) — 验证状态与维护规则
- [docs/TB_INDUSTRIAL_VERIFICATION_GUIDE.md](docs/TB_INDUSTRIAL_VERIFICATION_GUIDE.md) — TB 工业级验证指南
- [docs/VERSION.md](docs/VERSION.md) — 版本策略与恢复点

### 技术报告
- [docs/REPRODUCTION_REPORT_2026-05-18.md](docs/REPRODUCTION_REPORT_2026-05-18.md) — 算法复现报告
- [docs/FINAL_REPRODUCTION_AND_VERIFICATION_REPORT_CN_2026-05-18.md](docs/FINAL_REPRODUCTION_AND_VERIFICATION_REPORT_CN_2026-05-18.md) — 中文复现与验证终报
- [docs/TECHNICAL_ALGORITHM_GAP_ANALYSIS_CN_2026-05-18.md](docs/TECHNICAL_ALGORITHM_GAP_ANALYSIS_CN_2026-05-18.md) — 中文算法差距分析
- [docs/FPGA_ASIC_SIGNOFF_REVIEW_2026-05-18.md](docs/FPGA_ASIC_SIGNOFF_REVIEW_2026-05-18.md) — FPGA/ASIC 签核评审

### 交付包
- [delivery/sar_adc_v3_digital_core_2026-05-18/](delivery/sar_adc_v3_digital_core_2026-05-18/) — 冻结交付包（含 MANIFEST、RUNBOOK、SHA256SUMS）

## 📝 版本管理

### 当前版本
- **版本号**：v3.6.1-cleanliness
- **发布日期**：2026-05-18
- **状态**：Engineering Cleanliness Baseline
- **Tag**：`v3.6.0-engineering-closure`

### 版本历史

#### v3.6.0 (2026-05-18) — 工程闭合
- ✅ 7 个工程闭合 commit：TB scope 澄清、build target 统一、双 top skeleton、FSM safe default + 参数 guard、mixed-signal timing contract、XDC 拆分、CI/lint 基础设施
- ✅ 8 个提交共计 42 文件、+3933/-82 行
- ✅ 三 build target 全部 PASS，Synth 8-155 消除
- ✅ MIT LICENSE + GitHub Copilot 配置

#### v3.5.4 (2026-05-18) — 定点契约 + 四 TB 验证集
- ✅ 新增 FIXED_POINT_CONTRACT.md
- ✅ tb_sar_recon → tb_sar_recon_binary_norm（语义重命名）
- ✅ 新增 tb_recon_q8_split_weights（Q8 split-cap bit-exact 验证）

#### v3.5.3 (2026-05-18) — 算法差距分析
- ✅ 中文算法差距技术分析

#### v3.5.x (2026-05-15 ~ 2026-05-18) — 数字核心裁剪与交付
- ✅ 项目裁剪为核心 RTL + TB
- ✅ 复现 SAR ADC 数字算法（srm_residue_estimator）
- ✅ 交付包打包（MANIFEST / RUNBOOK / SHA256SUMS）
- ✅ 复现验证报告

#### v3.1.0 (2026-03-05) — 注释优化版
- ✅ Vivado 文件注释英文转换
- ✅ 防止 Vivado 打开文件乱码

#### v3.0.0 (2026-03-01) — 代码重组版
- ✅ 代码结构重组，按功能模块分类
- ✅ 规范化版本管理

#### v2.0.0 (2026-02-22) — 功能优化版
- ✅ 串行累加优化时序
- ✅ 增强 ASIC 兼容性

#### v1.0.0 (2026-02-15) — 初始版本
- ✅ 基本校准算法 + 重构引擎
- ✅ FPGA 板级验证

## 👥 作者

**Zhao Yi**
邮箱：717880671@qq.com
GitHub：[defineiocc02](https://github.com/defineiocc02)

## 📄 许可证

本项目采用 [MIT License](LICENSE)。

## 📅 时间戳规范

- **格式**：YYYY-MM-DD (ISO 8601)
- **时区**：CST (China Standard Time, UTC+8)
- **更新记录**：在文档末尾或版本历史中记录

---

*最后更新时间：2026-05-18*
