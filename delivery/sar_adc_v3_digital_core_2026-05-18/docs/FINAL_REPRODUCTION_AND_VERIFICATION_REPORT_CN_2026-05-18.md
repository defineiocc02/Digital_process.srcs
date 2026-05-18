# SAR ADC V3 数字算法复现与完整验证报告

日期：2026-05-18

版本目标：`v3.5.1-cn-report`

仓库路径：`D:\ReedZhao\Document\ADC_Digital_PROCESS\proc_vivado\sar_adc_v3`

## 1. 报告结论

本项目当前已经整理为一个最小数字核心代码库，活动代码只保留三类核心逻辑：

1. 前景电容权重校准：`sar_calib_ctrl_serial.sv`
2. 校准权重数字重构：`sar_reconstruction.sv`
3. SRM 统计残差数字估计：`srm_residue_estimator.sv`

本轮完成了以下工作：

- 检查并统一活动代码注释风格：RTL/TB/scripts/constraints 侧以英文注释为主；中文说明集中放入报告。
- 标准化三套 testbench：输出分节、表格化、显式 PASS/FAIL、失败时 `$fatal`，便于 CI 或批处理判断。
- 新增一键复跑脚本：`scripts/run_all_xsim.ps1` 和 `scripts/run_core_synth_checks.ps1`。
- 使用 Vivado 2018.3 完整运行 `xvlog -> xelab -> xsim` 三套仿真。
- 使用 Vivado 2018.3 对三个 RTL top 做 standalone 综合与 100 MHz post-synth timing 检查。
- 建立冻结交付包：`delivery/sar_adc_v3_digital_core_2026-05-18/`，并生成 `SHA256SUMS.txt`。

最终结果：

| 项目 | 结果 | 说明 |
| --- | --- | --- |
| `tb_sar_recon` | PASS | 48 checks，0 failed |
| `tb_srm_residue_estimator` | PASS | 17 checks，0 failed |
| `tb_gain_comp_check_lsb` | PASS | 10 checks，0 failed，最坏残差 `0.4937 LSB` |
| `sar_reconstruction` 综合 | PASS | 100 MHz WNS `3.999 ns` |
| `srm_residue_estimator` 综合 | PASS | 100 MHz WNS `7.480 ns` |
| `sar_calib_ctrl_serial` 综合 | PASS | 100 MHz WNS `5.450 ns` |

结论上，本仓库已经完成 Huang split-sampling SAR ADC 论文/博士论文中“数字可复现边界”的代码实现、仿真验证和 FPGA standalone 综合检查。需要注意的是，这仍不是完整 FPGA bitstream signoff 或 ASIC tapeout signoff，因为真实上板/流片还需要 top-level wrapper、真实 I/O 约束、CDC/RDC、STA、DFT、模拟边界验证和物理实现签核。

## 2. 文献与算法来源

参考材料为用户提供的两篇本地 PDF：

- `D:/Academic/Zotero/files/07_在读/0849 - Huang 等 - 2025 - A 5-MSs 16-bit low-noise and low-power split sampling SAR ADC with eased driving burden.pdf`
- `D:/Academic/Zotero/files/03_ADC各领域文献/031_高精度SAR_ADC领域/0764 - Huang - 2024 - Advanced clock multiplier and SAR ADC design techniques for high-resolution signal chain systems.pdf`

我用本地 PDF 文本抽取工具核对了关键词和相关段落，重点关注：

- split sampling SAR ADC 架构；
- 20-bit DAC 用于 16-bit 分辨率并保留冗余；
- 低 6 bit LSB section 被复用为校准参考；
- calibration logic 控制 DAC bottom-plate switches 做 bit-weight measurement；
- SAR conversion 后增加 SRM phase；
- SRM 通过额外 comparator/latch decisions 估计残差；
- 文中实现点使用 22 extra comparator decisions；
- SRM 降低前置放大器噪声与量化噪声，并提升 bit-weight calibration accuracy。

本项目复现的是数字算法边界，不复现晶体管级采样网络、autozero 前置放大器、flash ADC、latch 噪声物理电路或实际 DAC 开关电荷注入。这些模拟现象在 testbench 中以行为模型和决策流方式输入数字模块。

## 3. 作者算法基本原理

### 3.1 Split Sampling 的角色

作者提出的 split sampling 结构把采样操作和 DAC bit-cycling 的负担分开。大采样电容负责低噪声采样，小 DAC 负责快速 SAR bit-cycling。这样可以同时缓解输入驱动负担、采样噪声、DAC 功耗和转换速度之间的矛盾。

对本仓库而言，split sampling 的模拟采样网络不是 RTL 目标。RTL 只接收已经完成 SAR 判决后的 `raw_bits`，并负责：

- 使用校准后的 bit weights 做数字重构；
- 使用 SRM 估计得到的 residue correction 修正最终输出；
- 使用校准控制器生成 bit weight 测量序列。

### 3.2 电容 bit-weight 自校准

高精度 SAR ADC 的主要数字问题是 DAC 电容失配会造成 bit weight 偏差，进而造成 INL/DNL/SFDR 退化。作者设计中 20-bit DAC 支撑 16-bit 分辨率，冗余 bit 给校准和误差吸收留出空间。

校准基本思路：

1. 低 6 bit 被视为可信参考段。
2. 从第 7 个权重开始递归测量更高 bit。
3. 测量某个 target bit 时，用已知较低 bit 的组合逼近该 target bit 的等效权重。
4. 分别执行正向和反向测量，利用 `(P + N) / 2` 思想抵消 comparator/preamplifier offset。
5. 对重复测量结果做平均，降低随机噪声影响。
6. 对最高两个 bit 增加 protection switching，限制 top-plate swing，避免超出模拟前端可承受范围。

本项目中这部分由 `sar_calib_ctrl_serial.sv` 实现。

### 3.3 SRM 统计残差测量

SAR conversion 结束后，DAC top plate 上还存在 residual voltage。作者的 SRM 思想是在 DAC 状态保持不变的情况下，让 latch/comparator 继续做若干次 noisy decisions。由于 comparator noise 会把固定残差映射成统计意义上的 0/1 概率，数字端可以通过统计 1 的个数反推出残差方向和大小。

本项目实现点：

- `DECISION_COUNT = 22`，对应作者实现中的 22 extra decisions。
- `ones_count` 范围为 0 到 22。
- LUT 使用有限计数平滑概率 `(count + 0.5) / 23`，避免端点无穷大。
- 输出 `residue_q` 使用与重构权重一致的 signed fixed-point domain，默认 Q8。
- `sar_reconstruction` 在最终移位/舍入前注入该 residue correction。

### 3.4 数字重构

数字重构的目标是把 SAR raw decision bits 变成最终 signed 16-bit ADC code。理想情况下，每一位对应一个 binary weighted capacitor；实际情况下，每一位应使用校准得到的真实 weight。

本项目重构链路：

1. 对每个 `raw_bits[i]`，如果 bit 为 1 则加 `weight_ram[i]`，否则减 `weight_ram[i]`。
2. 先做 4 组 partial sums，再做 global sum，降低单周期长加法链压力。
3. 差分归一化：`sum_stage2 >>> 1`。
4. 注入 SRM residue：`+ srm_residue`。
5. 加 `0.5 LSB` rounding compensation。
6. 算术右移 `FRAC_BITS`。
7. 饱和到 signed 16-bit 范围。

## 4. 代码实现情况

### 4.1 RTL 文件

| 文件 | 当前职责 | 是否改动核心逻辑 |
| --- | --- | --- |
| `sar_calib_ctrl_serial.sv` | 前景 bit-weight 校准 FSM、P/N offset cancellation、serial accumulation、weight write-back | 本轮未改核心逻辑 |
| `sar_reconstruction.sv` | 权重 RAM、两级求和流水、SRM residue 注入、round/saturation | 本轮未改核心逻辑 |
| `srm_residue_estimator.sv` | 22-decision counter、ones_count、normal-inverse LUT residue 输出 | 本轮未改核心逻辑 |

本轮主要遵守用户“核心逻辑别改”的要求，没有修改上述 RTL 的算法行为。唯一代码侧非 TB 修改是约束文件注释转英文，不影响综合逻辑。

### 4.2 Testbench 文件

| 文件 | 目标 RTL | 本轮整理内容 |
| --- | --- | --- |
| `tb_sar_recon.sv` | `sar_reconstruction` | 增加统一 `record_check`、清晰分节、线性扫描表格、权重写入敏感性、流水吞吐、SRM 注入检查 |
| `tb_srm_residue_estimator.sv` | `srm_residue_estimator` | 增加表格化 count/LUT 检查、done pulse 检查、symmetry 检查、失败 `$fatal` |
| `tb_gain_comp_check_lsb.sv` | `sar_calib_ctrl_serial` | Monte Carlo 校准平台整理为工程化输出，显式记录 offset/noise/mismatch、gain compensation 和 residual error |

TB 的核心目标从“能跑”提升为“可维护、可批处理签核”：

- 每个检查点都有清晰 PASS/FAIL；
- 失败会通过 `$fatal` 让 Vivado batch 返回失败；
- 关键数值以表格形式输出；
- summary 明确打印 `OVERALL RESULT : PASS`；
- 适合后续被 CI 或脚本解析。

### 4.3 脚本文件

| 文件 | 用途 |
| --- | --- |
| `scripts/run_xsim.ps1` | 单个 TB 的 `xvlog/xelab/xsim` batch wrapper |
| `scripts/run_all_xsim.ps1` | 一键运行三套活动 TB |
| `scripts/run_core_synth_checks.ps1` | 一键综合三个 RTL top |
| `scripts/synth_one_top.tcl` | Vivado standalone synthesis Tcl，生成 utilization/timing/checkpoint |

脚本均使用英文注释/英文变量名，报告与说明文档使用中文或中英混排。

## 5. 本轮具体编辑记录

### 5.1 注释语言检查

执行检查：

```powershell
rg -n "[\p{Han}]" Digital_process\Digital_process.srcs\sources_1\new `
  Digital_process\Digital_process.srcs\sim_1\new `
  scripts `
  delivery\sar_adc_v3_digital_core_2026-05-18\rtl `
  delivery\sar_adc_v3_digital_core_2026-05-18\tb `
  delivery\sar_adc_v3_digital_core_2026-05-18\scripts
```

结果：活动 RTL/TB/scripts 和交付包代码侧未检出中文注释。约束文件原有中文说明已改为英文说明。

### 5.2 TB 整理

`tb_sar_recon.sv`：

- 整理 header，明确 Verification Scope 和 Pass Criteria。
- 统一 reset、sample driving、result waiting、weight loading 等 task。
- 修正 Vivado 2018.3 对 `%+5d` 和三目字符串格式化兼容性不佳导致的输出混乱问题。
- 增加 SRM residue `+256/-256` 对应输出 `+1/-1 code` 的固定点合同检查。

`tb_srm_residue_estimator.sv`：

- 改为 production-style TB。
- 显式检查 `done` pulse、`ones_count` 和 `residue_q`。
- 检查 LUT 端点和中心对称性。

`tb_gain_comp_check_lsb.sv`：

- 将 Monte Carlo 校准结果整理为按 run 输出。
- 明确模拟 manufacturing mismatch、comparator offset、random noise。
- 用 MSB gain factor 做系统增益补偿，再检查 bit 6 到 bit 19 的 residual error。

### 5.3 文档与交付包

新增/更新：

- `docs/FINAL_REPRODUCTION_AND_VERIFICATION_REPORT_CN_2026-05-18.md`
- `docs/FPGA_ASIC_SIGNOFF_REVIEW_2026-05-18.md`
- `docs/VERIFICATION.md`
- `docs/VERSION.md`
- `docs/CHANGELOG.md`
- `MOC.md`
- `README.md`
- `delivery/sar_adc_v3_digital_core_2026-05-18/`

交付包内容包括：

- `rtl/`：三份核心 RTL；
- `tb/`：三份工程化 TB；
- `docs/`：报告、版本、架构、验证说明；
- `scripts/`：仿真/综合脚本；
- `constraints/`：legacy board XDC hint；
- `vivado/`：参考 XPR；
- `SHA256SUMS.txt`：完整性校验。

### 5.4 脚本调试记录

新增 `scripts/run_all_xsim.ps1` 后，第一次复跑时发现一个 PowerShell
数组参数展开问题：外层用 `powershell -File scripts\run_xsim.ps1 -Files
$files` 调用时，`-Files` 数组的第二个路径会被误解释为 `Snapshot`
参数，导致 `xelab -s` 后接收到 testbench 文件路径而不是 snapshot 名称。

处理方式：

- 保留 `scripts/run_xsim.ps1` 作为单 TB runner；
- 将 `scripts/run_all_xsim.ps1` 改为在同一 PowerShell 进程内用 `& $Runner`
  调用，直接传递 string array；
- 修复后重新运行完整 XSIM，三套 TB 全部 PASS。

这条记录写入报告是为了便于后续维护者理解为什么 runner 脚本采用“同进程调用”而不是再次启动 `powershell -File`。

## 6. 完整检测、运行、编译记录

### 6.1 Vivado 环境

使用 Vivado 2018.3：

```text
D:\Academic\Vivado2018\Vivado\2018.3\bin
```

使用工具：

- `xvlog.bat`
- `xelab.bat`
- `xsim.bat`
- `vivado.bat -mode batch`

用户提供的 `vvgl.exe` 是 Vivado GUI/launcher 相关入口，不适合作为常规仿真 CLI。本项目使用 Vivado 官方 batch simulator flow。

### 6.2 XSIM 一键复跑命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

该脚本等效执行三组流程：

1. `xvlog -sv <rtl> <tb>`
2. `xelab <tb_top> -debug typical -s <snapshot>`
3. `xsim <snapshot> -runall`

输出日志位置：

- `sim_work/tb_sar_recon/xsim.log`
- `sim_work/tb_srm_residue_estimator/xsim.log`
- `sim_work/tb_gain_comp_check_lsb/xsim.log`

### 6.3 XSIM 结果

`tb_sar_recon`：

| 检查项 | 结果 |
| --- | --- |
| ideal linearity sweep | PASS |
| calibration weight write sensitivity | PASS |
| pipeline throughput | PASS |
| SRM residue injection | PASS |
| checks total | 48 |
| checks failed | 0 |

`tb_srm_residue_estimator`：

| 检查项 | 结果 |
| --- | --- |
| count 0 -> -258 | PASS |
| count 1 -> -194 | PASS |
| count 11 -> 0 | PASS |
| count 21 -> +194 | PASS |
| count 22 -> +258 | PASS |
| LUT symmetry | PASS |
| checks total | 17 |
| checks failed | 0 |

`tb_gain_comp_check_lsb`：

| Run | Max residual error |
| --- | ---: |
| 0 | `0.3864 LSB` |
| 1 | `0.3797 LSB` |
| 2 | `0.3425 LSB` |
| 3 | `0.2807 LSB` |
| 4 | `0.4937 LSB` |

判据：每个 Monte Carlo run 的 max residual error 必须 `< 0.5 LSB`。

结论：全部 PASS，最坏 run 为 `0.4937 LSB`，贴近但仍低于门限。该结果说明当前数字校准模型能在这组 offset/noise/mismatch 条件下压住 residual bit-weight error；若用于论文级统计或 tapeout 风险评估，建议扩展到更多随机种子与 PVT/噪声角。

### 6.4 综合编译命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_core_synth_checks.ps1
```

目标器件：

```text
xc7a35tfgg484-2
```

脚本行为：

- 对每个 RTL top 创建 in-memory Vivado project；
- `read_verilog -sv` 读入单个 RTL；
- `synth_design -top <top> -part xc7a35tfgg484-2`；
- 如果存在 `clk` 端口，创建 100 MHz clock；
- 运行 `check_timing`；
- 生成 utilization report、timing summary、DCP checkpoint。

输出位置：

- `sim_work/synth/sar_reconstruction/`
- `sim_work/synth/srm_residue_estimator/`
- `sim_work/synth/sar_calib_ctrl_serial/`

### 6.5 综合结果

| Top | LUT | FF | BRAM | DSP | WNS @100 MHz | 结论 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `sar_reconstruction` | 950 | 818 | 0 | 0 | `3.999 ns` | PASS |
| `srm_residue_estimator` | 26 | 22 | 0 | 0 | `7.480 ns` | PASS |
| `sar_calib_ctrl_serial` | 511 | 821 | 0 | 0 | `5.450 ns` | PASS |

Vivado synthesis reported 0 errors and 0 critical warnings for all three top。

普通 warning/INFO 解读：

- `Common 17-741`：本机 Tcl store 无写权限，Vivado fallback 到安装目录；这是环境权限警告，不是 RTL 功能问题。
- `Netlist ... not ideal for floorplanning`：standalone top 被 flatten 后原语较多，若要 floorplan，可保留 hierarchy；不影响当前功能综合。
- sparse ROM/RAM mapping 信息：小型寄存器阵列/LUT 没有映射成 BRAM，符合当前规模。
- `case statement is not full and has no default`：校准 FSM 的 sequential case 由 state transition 控制覆盖，Vivado 没有产生 latch/multidrive 错误；若进入 ASIC signoff，建议 lint/formal 中明确处理非法状态恢复。

### 6.6 Package-local 编译检查

交付包内也提供独立综合脚本：

```powershell
cd delivery\sar_adc_v3_digital_core_2026-05-18
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_package_synth_checks.ps1
```

该检查已通过，证明 `delivery/` 内复制的 RTL 快照不依赖原 Vivado project state，也能 standalone 综合。

## 7. FPGA 可落地情况

当前结果说明三份核心 RTL 在 Artix-7 `xc7a35tfgg484-2` 上可以综合，并且在 standalone 100 MHz 约束下 post-synth timing 有余量。

但是 FPGA 上板还缺以下内容：

1. 完整 top wrapper：连接 SAR sequencer、comparator interface、calibration controller、SRM estimator、reconstruction output。
2. 真实 XDC：当前 `sar_calib_fpga.xdc` 是 legacy board hint，端口名仍偏向旧 wrapper，例如 `rst_n_btn/start_sw/done_led`，不能直接当最终 core signoff constraints。
3. 输入/输出 delay：standalone synthesis 只约束了内部 clock，没有约束 ADC/comparator 外设边界。
4. CDC/RDC：`comp_out`、按钮、外部 start 信号必须定义同步、settling 或 debouncing 规则。
5. ILA/debug：legacy XDC 中的 ILA debug core 只适合 bring-up，不应混入最终最小核心约束。

因此，当前 FPGA 结论是“核心 RTL 可综合且单元时序良好”，不是“完整 bitstream 已签核”。

## 8. ASIC/流片可能情况与风险

ASIC 方向上，当前 RTL 是一个可继续推进的数字原型，但不能直接称为 tapeout-ready。

必须补齐：

- Lint：检查 SystemVerilog 语法、宽度、signed cast、unpacked array、enum FSM、函数综合兼容性。
- CDC/RDC：尤其 comparator/latch decision 到数字时钟域、async reset release。
- DFT：scan insertion、test mode、reset/clock 控制、可测性覆盖率。
- STA：多 PVT corner、OCV/AOCV、clock uncertainty、IO timing、false/multicycle path。
- Gate-level simulation：含 SDF 回标。
- Formal equivalence：RTL 与 gate netlist 等价。
- Power intent：UPF/CPF、clock gating、isolation/retention，如果芯片有多电源域。
- Mixed-signal verification：comparator offset/noise、DAC settling、split-sampling charge injection、autozero residue 等必须与数字 testbench 假设对齐。

特别注意：

- `tb_gain_comp_check_lsb` 的最坏 residual error `0.4937 LSB` 离 `0.5 LSB` 门限很近，工程上建议扩大 Monte Carlo seed 数量，并用模拟仿真给出真实 offset/noise 分布。
- `sar_calib_ctrl_serial` 的 `comp_out` 目前只做一级寄存，若 comparator decision 与 `clk` 异步，真实芯片中需要同步策略或严格的 timing contract。
- 异步低有效 reset 对 FPGA 很常见，但 ASIC 需要结合 reset tree、scan、RDC 策略评审。

## 9. 版本与 Git 归档

当前已有上一轮归档提交：

```text
9769e90 chore: package verified digital core
```

本轮将新增中文详版报告、仿真一键脚本、英文约束注释和更新后的交付包校验清单，并再次 Git 提交归档。

GitHub 状态：

- 当前本地仓库没有配置 `origin` remote。
- 因此目前只能确认本地 Git 提交存在，尚未 push 到 GitHub。
- 如需提交 GitHub，需要先配置远端地址，然后执行 push。

## 10. 维护建议

1. 所有 RTL/TB/scripts 注释继续以英文为主；中文分析、复现实验和学术解释放在 `docs/*CN*.md` 报告中。
2. 活动 Vivado project 只保留三份核心 RTL 和三份 TB，避免重新引入重复 wrapper、旧模型和 MATLAB 试验脚本。
3. 每次修改 RTL 行为后必须执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_core_synth_checks.ps1
```

4. 每次生成交付包后必须更新 `SHA256SUMS.txt`。
5. 若要进入 FPGA bitstream 或 ASIC tapeout，先建立独立 integration 分支，不要在最小算法核心分支上混入板级调试碎片。

## 11. 最终判断

本仓库已经完成用户要求的核心代码保护、TB 工程化、完整仿真、完整综合编译、算法复现说明、交付包和 Git 归档流程。当前最可靠的表述是：

> 本项目已完整复现 Huang split-sampling SAR ADC 中可由数字 RTL 表达的校准、SRM 残差估计和数字重构算法边界；三套 testbench 均通过 Vivado XSIM，三份 RTL 均通过 Vivado standalone synthesis。下一阶段若面向 FPGA 上板或 ASIC 流片，需要补充系统集成和物理签核流程。

## 12. 追加交付记录：工业级 TB 注释与交付包清晰度

应用户继续要求，本轮在不改动核心 RTL 算法逻辑的前提下，对三份 active testbench 进行了工业维护层面的注释增强：

- `tb_sar_recon.sv`：补充 Design Intent、Interface Assumptions、Testbench Architecture、driver/scoreboard 注释，以及 SRM Q8 residue 注入检查说明。
- `tb_srm_residue_estimator.sv`：补充 SRM 22-decision 到 signed Q8 LUT 的验证边界、start/decision/done 握手假设、golden LUT 维护说明。
- `tb_gain_comp_check_lsb.sv`：补充 Monte Carlo 行为 analog model、capacitor mismatch、comparator offset/noise、writeback monitor、gain compensation 和 residual error scoring 注释。
- 三份 TB 均加入 `default_nettype none`，用于暴露未来维护中可能误写出的隐式 net。
- 新增 `docs/TB_INDUSTRIAL_VERIFICATION_GUIDE.md`，集中说明 TB 覆盖、失败策略、注释规范和后续维护检查单。
- 已同步到 `delivery/sar_adc_v3_digital_core_2026-05-18/tb/` 与包内 `docs/`。

追加验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
```

结果：

- `tb_sar_recon`：PASS，`48` checks，`0` failed。
- `tb_srm_residue_estimator`：PASS，`17` checks，`0` failed。
- `tb_gain_comp_check_lsb`：PASS，`10` checks，`0` failed，worst residual error `0.4937 LSB`。
- 总结：`XSIM OVERALL RESULT : PASS`。
- 交付包入口 `delivery/sar_adc_v3_digital_core_2026-05-18/scripts/run_all_xsim.ps1` 也已运行通过，确认包内 `rtl/` 与 `tb/` 可以脱离 Vivado project 源目录独立复现。

该追加工作只增强 TB 可读性、可审计性和交付包维护性；未改变核心 RTL 算法行为。
