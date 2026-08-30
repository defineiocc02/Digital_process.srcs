# REVIEW_01：SAR ADC RTL 到门级就绪独立审查

**角色**：Independent Reviewer 1，mixed-signal SAR ADC tapeout audit
**日期**：2026-08-30
**根目录**：D:/ReedZhao/Document/ADC_Digital_PROCESS/proc_vivado/sar_adc_v3
**边界**：维护版 RTL 到 gate-level readiness，并核对其与 VM SAR_16B_5M 模拟顶层的集成可行性。
**限制**：本轮只读检查仓库和已有 VM 证据；本文件是本轮唯一写入的 checkpoint artifact；未修改 RTL、TB、原理图或流程脚本。

## 1. 执行摘要

当前项目可以生成独立数字模块的 FPGA 综合网表，但还不能作为 SAR_16B_5M 的完整 ASIC/AMS 集成版本进入 GDS 或流片签核。

工程结论：

> 算法核可作为 integration baseline；系统集成尚未达到 netlist signoff，GDS、流片和硅后测试均未闭合。

主要断点：

1. VM 顶层当前使用的 raw-bit 位片和 valid 定义不正确；
2. VM 正常 SAR 是 READYN 驱动的异步自定时链，当前重构 RTL 假设自由运行同步时钟；
3. 校准核没有对应真实 CDAC 的 calibration PHY sequencer、VCM/SET/RSTT 仲裁和 comparator-done 握手；
4. 尚无 ASIC SDC、CDC/RDC signoff、形式等价、DFT/MBIST、GLS/SDF、PEX/GDS 或 silicon ATE 证据。

### 1.1 状态总表

| 领域 | 状态 | 判断 |
|---|---|---|
| 需求与 fixed-point contract | PARTIAL | 有 Q8 文档，但位序、EOC、SRM 事务边界未闭合 |
| 维护版 SystemVerilog RTL | PARTIAL | 三个算法核可综合；不是完整 ADC digital top |
| 单元级 XSIM | VERIFIED | 摘要记录四个 TB 均 0 failed |
| 代码级 lint/CI | PARTIAL | 有入口；本轮无新的 lint transcript/waiver |
| CDC/RDC/reset | GAP | 没有工具报告，异步接口尚未设计闭合 |
| RTL 综合 | VERIFIED | Vivado 摘要为 0 errors、0 critical warnings |
| STA/约束 | PARTIAL | 单一 100 MHz clock；27/71 ports unconstrained |
| RTL-to-gate equivalence | GAP | 未发现 LEC/Formality/Conformal 证据 |
| GLS/SDF | GAP | 未发现 gate netlist、SDF 或 GLS regression |
| DFT/scan/MBIST/power intent | GAP | 未发现 scan、ATPG、MBIST、UPF/CPF |
| Cadence AMS 集成 | PARTIAL | 有层次和 Maestro 证据，但数字实例 ignored、接口悬空、历史运行有 error |
| GDS/PEX/DRC/LVS | NOT_CHECKED | active tree 无 physical-flow 工件，VM 其他路径未扩展 |
| 硅后测试/ATE | NOT_CHECKED | 未提供芯片、封装、ATE 或实验室数据 |

## 2. 三轮独立审查

### Pass 1：需求、RTL、接口合同

- 三个算法核的参数和接口可读，Q8 定义在 docs/FIXED_POINT_CONTRACT.md 中；PARTIAL。
- 校准控制器从 bit 6 到 bit 19 递归校准，P/N 测量、32 次平均和 bit18/19 protection 可定位；VERIFIED as RTL intent。
- sar_adc_digital_top 明确是 skeleton，未实现完整 SAR controller、mode arbitration 和 AFE 时序；VERIFIED gap。
- SRM RTL 固定 22 个有效判决，而 VM 正常转换导出的 BITP<20:0> 只有 21 个锁存位；VERIFIED mismatch。

### Pass 2：验证、综合、门级就绪

- 四个 XSIM 单元测试摘要均为 0 failed；VERIFIED for stated TB scope。
- 校准 TB 为 MC_RUNS=5，使用行为级 comparator stub，不是 512-chip 或 AMS signoff；PARTIAL。
- Vivado 摘要为 sar_adc_digital_top、xc7a35tfgg484-2、100 MHz 假设，WNS +3.957 ns；27 输入和 71 输出未约束；PARTIAL, not STA signoff。
- 未发现 SDC、CDC/RDC、LEC、SDF、scan/ATPG/MBIST 或 power-intent 工件；GAP。

### Pass 3：VM AMS、论文边界、可发表性

- VM 层次包含分段 CDAC、比较器、Flash、异步 SAR logic、VCM/sampling 控制和旧 sar_reconstruction 实例；VERIFIED。
- VM sar_reconstruction 实例为 I94，nlAction=ignore，w_wr_*、reset、输出无有效闭环；VERIFIED blocker。
- Maestro 为 30 us、5 MS/s，理论约 150 笔转换，不满足 512 个有效解码点；history log 记录多个 simulation error；VERIFIED no AMS signoff。
- 论文已有的 split-sampling、LSB reference、SRM 降噪不能原样作为本项目创新点；需新增可测量的电路/数字协同机制和 silicon evidence；PARTIAL。

## 3. 检查路径、证据和命令

### 3.1 路径

- canonical RTL：rtl/sar_calib_ctrl_serial.sv、rtl/sar_reconstruction.sv、rtl/srm_residue_estimator.sv、rtl/sar_adc_digital_top.sv、rtl/sar_calib_fpga_top.sv
- Vivado source：Digital_process/Digital_process.srcs/sources_1/new/
- Vivado TB：Digital_process/Digital_process.srcs/sim_1/new/
- flow：scripts/run_all_xsim.ps1、scripts/run_core_synth_checks.ps1、scripts/build_vivado.tcl、scripts/synth_one_top.tcl
- constraints：constraints/core_synth.xdc、constraints/sar_calib_fpga_legacy_board_hint.xdc、constraints/debug_ila_template.xdc
- contracts：docs/REQUIREMENTS.md、docs/FIXED_POINT_CONTRACT.md、docs/MIXED_SIGNAL_TIMING_CONTRACT.md、docs/VERIFICATION.md、docs/VERSION.md
- VM evidence：analysis/vm_sar16b_compatibility_20260830/checkpoint_sar16b_hierarchy.json、checkpoint_sar16b_maestro.json、checkpoint_sar16b_history_logs.json、compatibility_matrix.csv、local_rtl_validation_summary.json

### 3.2 命令

    git status --short
    git branch --show-current
    git log -5 --oneline --decorate
    rg --files
    Get-FileHash rtl\*.sv -Algorithm SHA256
    Get-FileHash Digital_process\Digital_process.srcs\sources_1\new\*.sv -Algorithm SHA256
    python scripts\check_repo_consistency.py
    rg -n "TODO|FIXME|assert|assume|cover|formal|equiv|scan|mbist|sdf|gds|cdc|rdc" rtl Digital_process scripts constraints docs
    rg -n "MC_RUNS|AVG_LOOPS|record_check|\$fatal" Digital_process\Digital_process.srcs\sim_1\new

已有摘要的 XSIM 入口为：

    $env:PROCESSOR_ARCHITECTURE='AMD64'
    powershell -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1

本轮没有重新启动会写入 sim_work 的长时间综合或 VM 仿真；历史摘要仅作为证据，不被提升为本轮重新运行结果。

当前 git 分支为 main，HEAD/origin/main 为 a2ee34e。canonical rtl/ 与 Vivado sources_1/new/ 中四个主要 RTL 的 SHA-256 当前相同；这证明当前快照一致，但 xpr 仍维护独立 source list，未来仍有分叉风险。

## 4. RTL 审查

### 4.1 sar_reconstruction.sv

功能是 Q8 signed weighted reconstruction：20 路 raw bit 经 differential sum、/2、SRM 注入、rounding、16-bit saturation 输出。

VERIFIED as RTL intent：

- 40-bit accumulator 和四组 5-entry partial sum；
- guard 锁定 CAP_NUM=20、WEIGHT_WIDTH>=30、OUTPUT_WIDTH=16、FRAC_BITS=8；
- weight write-back 和 SRM residue 具有独立数字验证接口；
- reset 后低 6 位加载理想参考权重。

P1 风险：

1. weight_ram[6..19] reset 为零，没有 weights_ready 或 normal-conversion inhibit；校准未完成时收到 data_valid_in 会产生无效输出。
2. srm_residue 没有和 raw_bits/data_valid_in 成对的 transaction tag 或 residue-valid，可能出现旧 residue 用于新 code。
3. always_ff 中使用 blocking intermediate assignment；应有 lint waiver 或改为组合 next-value 加 sequential output。
4. +0.5 后算术右移对负值不是对称 round-half-away-from-zero，必须固定为明确 contract。

### 4.2 sar_calib_ctrl_serial.sv

功能是 bit6 到 bit19 的前台递归权重校准，包括 P/N 测量、serial accumulation、32 次平均、write-back 和 bit18/19 protection。

VERIFIED as RTL intent：

- AVG_LOOPS 有 power-of-two guard；
- shadow_weights 支持递归参考；
- P/N offset cancellation 意图清楚；
- COMP_WAIT_CYC、serial accumulation 和 illegal-state default 可定位。

不能直接用于 VM：

- dac_p_force/dac_n_force 是抽象 20-bit force vector，不是 VM 两个 CDAC_SWITCH_DRIVER_NEW 所需的 BITP/BITN/SET/VCM/RSTT 完整控制；
- RTL 要求 comp_out 满足 clk setup/hold，VM comparator 通过 READYN 推动异步 SAR；
- 没有 sample/hold、VCM restore、auto-zero、evaluate 和 timeout protocol；
- 没有保证 calibration 与 normal SAR 对模拟控制线的唯一所有权；
- calib_done 只表示 digital FSM 完成，不表示模拟端回到安全 VCM 或结果已跨域。

对静态、可重复的 effective CDAC weight mismatch，算法方向可用；对真实 VM，必须增加 calibration PHY sequencer 和 mode arbiter。

### 4.3 srm_residue_estimator.sv

VERIFIED：

- start 后累计 exactly DECISION_COUNT 个 decision_valid；
- 22-entry count-to-residue LUT 的边界和对称性有 TB 检查；
- LUT 以 (count+0.5)/23 的有限端点 inverse-normal 近似生成，FRAC_BITS=8 被 guard 固定。

P1 集成问题：

- DECISION_COUNT=22 是 LUT 合格边界，不是通用参数；
- VM 的 21 个 BITP<20:0> 不能直接当 22 个 SRM samples；
- VM 没有 residue hold、重复 evaluate、22-cycle decision_valid 和 completion handshake；
- LUT 不证明模拟 residue-to-probability、comparator noise 或 SRM timing。

### 4.4 两个 top

sar_adc_digital_top 是综合结构 skeleton，不是 tapeout top，缺少 asynchronous code capture、exclusive ownership、VCM/reset handoff、comparator done/timeout、CDC、scan/DFT、ASIC SDC 和 power intent。

sar_calib_fpga_top 的 comp_out_stub=1'b0 只用于 build closure，不能验证校准、AFE 或论文 mixed-signal 结论。

## 5. VM SAR_16B_5M 集成审查

### 5.1 位序和 P0 错误

导出的实际映射为：

| 事件 | 锁存结果 | 是否驱动物理 CDAC |
|---|---|---|
| SET<0> | BITP/N<20>，Flash bit | 是，CDAC bit 20 |
| SET<1> | BITP/N<19>，Flash bit | 是，CDAC bit 19 |
| SET<2>...SET<19> | BITP/N<18>...BITP/N<1> | 是，CDAC bit 18...1 |
| SET<20> | BITP/N<0>，附加判决 | 否，不是 CDAC LSB |

正确 capture 应为：

    raw_bits[19:0] = BITP[20:1]
    raw_bits[19]   = BITP[20]
    raw_bits[0]    = BITP[1]

VM I94 当前为 raw_bits<19:0>=BITP<19:0>，data_valid_in=BITP<20>。这会丢失最高 CDAC bit、把非 CDAC 的 BITP<0> 当 LSB，并把 Flash data 当 valid level。这是 P0 integration blocker。

### 5.2 I94 无数字闭环

VM evidence 记录：

- I94 是旧接口版本，缺少当前 RTL 的 srm_residue；
- nlAction=ignore；
- rst_n、w_wr_en、w_wr_addr、w_wr_data 和输出没有有效闭环；
- 旧 weight RAM 依赖 write-back，不能从悬空总线得到有效权重。

因此“原理图存在 SystemVerilog instance”不能计为数字重构已集成。

### 5.3 异步时序

VM conversion period 约 200 ns（5 MS/s），包含 CLKS、CLKSTOP、CLK_nt、CLKDAC_top、CLKAZ、RSTT、CLK0/CLK00 等阶段；TAZ 约 19.6 ns。READYN 回送 SAR logic CCLK，由 ready event 推动 SET<0:20>。

adapter 必须定义 sampling/hold、VCM 预充、CDAC reset、auto-zero/evaluate、DAC settle、comparator regeneration、READYN handshake 和 code hold/clear。COMP_WAIT_CYC=16 只能是数字等待，不能替代跨 PVT 的模拟 settling proof。

## 6. 验证和门级就绪

### 6.1 已有证据

local_rtl_validation_summary.json 记录：

| TB/top | checks | failed | 状态 |
|---|---:|---:|---|
| tb_sar_recon_binary_norm | 49 | 0 | VERIFIED，binary-normalized smoke |
| tb_recon_q8_split_weights | 17 | 0 | VERIFIED，Q8 split-weight contract |
| tb_srm_residue_estimator | 17 | 0 | VERIFIED，22-count LUT/counter |
| tb_gain_comp_check_lsb | 10 | 0 | VERIFIED，5-run behavior calibration |

合计为 100 checks。部分历史文字写成 93，这是 P2 文档一致性问题。

摘要还记录 Vivado 2018.3 synthesis 0 errors、0 critical warnings、3 warnings；xc7a35tfgg484-2；single 100 MHz assumption；WNS +3.957 ns、TNS 0；27 unconstrained inputs、71 unconstrained outputs；校准 TB 最差残差 0.4937 LSB，MC_RUNS=5。

### 6.2 不能证明的内容

XSIM unit PASS 不能证明真实 BITP 位序；synthesis PASS 不能证明 PVT/ASIC timing；0.4937 LSB 不能证明真实 comparator/CDAC/VCM/reference；22-entry LUT PASS 不能证明 VM 有 22 次物理 SRM decisions；Python 512-chip campaign 不能替代 AMS、PEX 或 silicon。

缺少 asynchronous EOC capture、mode collision、late/early/timeout/metastability、simultaneous write、stale residue、X/Z、gate reset 和 512 个连续有效 code 的 TB。

## 7. CDC、RDC、reset、power、DFT

文档把 core 定义为单一 clk domain，并要求外部预处理非同步输入；VM 已明确是 asynchronous SAR，不能继续依赖外部假设。

必须新增：

- async EOC 到 dig_clk 的 pulse/toggle/handshake synchronizer；
- BITP<20:1> 与 EOC 的 bundled-data capture；
- READYN/comp_out 的 event capture；
- calibration request/done 和 SRM done 的 CDC/RDC；
- reset deassertion synchronizer 及 analog/digital reset ordering。

**状态：CDC/RDC GAP。** 没有报告、约束、waiver 或 assertion proof。

RTL active-low asynchronous reset，尚未形成完整 reset controller。必须证明 RAM 上电值、无伪 calib_done、无旧 code 伪输出、VCM/CDAC reset 前 ownership 安全及 scan/functional/brownout reset 优先级。

**状态：reset PARTIAL。**

当前没有 UPF/CPF、isolation、retention、level-shifter 或 power-state 定义。VM 同时使用 1.8 V digital、3.3 V switch/reference 和约 1.65 V VCM。

**状态：power intent GAP。**

没有 scan enable、test mode、MBIST、ATPG observation 或 compression interface，权重 RAM/shadow RAM 和 FSM 没有 test access。

**状态：DFT GAP。**

## 8. 综合、STA、等价、GLS

### 8.1 综合

**VERIFIED（限定范围）**：四个构建目标有入口；已有摘要报告 sar_adc_digital_top 综合 0 errors、0 critical warnings。仅证明指定 FPGA part 可综合，不代表 ASIC library 的面积、功耗、时序或可测性。

### 8.2 STA

constraints/core_synth.xdc 只有：

    create_clock -name clk -period 10.000 [get_ports clk]

没有 input/output delay、generated clock、clock uncertainty、false-path、multicycle、max transition、max capacitance 或 reset/scan mode constraints。27/71 unconstrained ports 表明不是 endpoint-complete STA。

**状态：PARTIAL，P1。**

ASIC SDC 必须覆盖 functional/scan/calibration/SRM modes、async event classification、generated clocks、recovery/removal、slew/load/fanout 和多电压 crossing，并达到 zero unconstrained endpoints。

### 8.3 Equivalence/GLS

未发现 LEC/Formality/Conformal 脚本、mapping file 或报告。必须覆盖 reset、illegal state、weight write、SRM boundary、X semantics 和 memory initialization policy。

未发现 gate netlist、SDF、GLS TB 或 annotated timing log。必须覆盖 normal capture、calibration writeback、SRM decisions、reset、back-to-back conversion、late comparator/EOC 和 valid latency，并在 min/typ/max 下运行。

**状态：equivalence GAP；GLS/SDF GAP。**

## 9. GDS、流片、硅后边界

active tree 未找到 liberty、LEF/DEF、SDC、UPF、SPEF/SDF、GDS/OASIS、DRC/LVS/PEX 等 ASIC physical-flow 工件。因此：

- 数字 RTL 到 FPGA netlist：可以到达；
- 完整 RTL 到 ASIC gate netlist：尚未到达；
- gate netlist 到 GDS：当前无法签核；
- GDS 到 tapeout：NOT_CHECKED；
- silicon ATE/lab test：NOT_CHECKED。

GDS 交接至少需要 post-route STA with SPEF、DRC/LVS/antenna/EM/IR、extracted AMS critical-net review、final netlist/SDF/LEF/DEF/GDS checksums、scan/test-mode signoff 和 final ECO manifest。

## 10. 与 Huang 2025 的联系和差异

### 联系

- split-sampling SAR 的 20 路高分辨率 decision/reconstruction；
- 低位 reference section 辅助高位权重估计；
- P/N 或差分测量降低 comparator offset；
- 多次 noisy decisions 估计 residue 并注入数字重构；
- 16-bit 输出和校准 effective weights。

### 差异

| 论文/真实电路 | 当前 RTL/模型 | 结论 |
|---|---|---|
| split-sampling、VCM handoff、CDAC switching | 抽象 force vector 和 signed raw bits | 数字接口近似 |
| LSB reference switching sequence | 已知权重加 noise 的 FSM/stub | 非 transistor-level reproduction |
| comparator timing/offset cancellation | comp_out 按 clk setup/hold 输入 | 需要 PHY/handshake |
| 真实 22 次 SRM probability experiment | 22-entry digital counter/LUT | 数字 LUT 验证，模拟 sequence 未闭合 |
| normal noise/settling/reference/dynamic effects | 多数被关闭或抽象 | 不能比较绝对 SNDR |
| measured 5 MS/s silicon | FPGA synthesis/behavioral/XSIM | 不能作为实测结果 |

## 11. TCAS/JSSC 候选创新点

以下仅为候选，不是新颖性结论。论文已有 split-sampling、LSB-assisted calibration、SRM 降噪不能原样作为本项目创新点。

1. **异步 SAR 到同步重构的无损 code-capture/CDC**：READYN、自定时 BITP<20:1> 原子锁存、独立数字 pipeline，并有 PVT/GLS/AMS/silicon 证据。
2. **面向 split-CDAC 的低开销 calibration PHY**：复用真实 switch driver，同时保持 VCM/auto-zero/normal conversion 安全，并有 timeout/protection。
3. **transaction-aware Q8 weight + SRM datapath**：calibration result、22-decision residue 和同一 raw code 严格绑定。
4. **bit18/19 protection 与 calibration range 的协同设计**：需要新理论推导、共模/误差/面积/时间权衡和 silicon 数据。
5. 512-chip physical-CDAC verification 可提升可信度，但不应单独包装成 JSSC 电路创新。

当前不足以支持创新声明：没有同条件 silicon/AMS 对比、calibration energy/time/area/power 交叉结果、5 MS/s 连续 512 点闭环、prior-art ledger，也没有证明 SRM on/off 差异来自正确物理噪声机制。

## 12. 各交接阶段通过条件

| Gate | 交接 | Pass criteria | 当前 |
|---|---|---|---|
| G0 | requirements/config freeze | 单一 source-of-truth；位序/单位/EOC/SRM 数量定版；hash 一致 | PARTIAL |
| G1 | RTL unit verification | 四 TB 通过；补 reset、X/Z、back-to-back、transaction pairing；lint 无未豁免 error | PARTIAL |
| G2 | VM digital adapter | BITP<20:1> capture、独立 EOC、独立 dig_clk、无 ownership 冲突 | GAP |
| G3 | calibration PHY | VCM/SET/RSTT/auto-zero/evaluate/READYN handshake，PVT/timeout 通过 | GAP |
| G4 | SRM closure | 证明/重建 22 次物理 decisions，residue/raw code 同 transaction，SRM-off 无额外降级 | GAP |
| G5 | ASIC synthesis/STA | 目标库、SDC、zero unconstrained endpoints、recovery/removal/slew/load clean | PARTIAL |
| G6 | CDC/RDC/reset/power | clean 或 waiver；reset release、level-shifter、UPF 完成 | GAP |
| G7 | RTL-to-gate | LEC/Formality/Conformal PASS，含 reset/memory/X policy | GAP |
| G8 | GLS/SDF | min/typ/max GLS 通过，mapping/latency/reset/async EOC 全通过 | GAP |
| G9 | DFT | scan/ATPG/MBIST/coverage/test-mode signoff | GAP |
| G10 | AMS/PEX | 当前 CDAC netlist、PVT/MC/PEX、512 valid samples、FFT/INL/DNL、无 errors | GAP |
| G11 | GDS/tapeout | DRC/LVS/PEX/STA/IR/EM/antenna clean，manifest/checksum/ECO closure | NOT_CHECKED |
| G12 | Silicon | ATE/lab raw data、校准、SRM on/off、性能和失效分析可复现 | NOT_CHECKED |

## 13. P0/P1/P2

### P0：阻止当前 AMS/netlist 集成

1. 错误 raw-bit slice 和 valid：必须使用 BITP<20:1>，不能使用 BITP<19:0>，不能用 BITP<20> 作为 valid。
2. 异步 comparator/SAR CLK 直接驱动同步 reconstruction：必须独立 dig_clk、EOC capture 和 CDC。
3. 旧 I94 为 nlAction=ignore 且 write/reset/output 悬空：必须重新生成当前 SV view、symbol、config 和顶层连线。
4. 缺 calibration PHY/mode arbiter：force vectors 不能直接接 VM switch driver，必须保证模拟控制线唯一所有权。
5. CDAC P 侧 net22...net28 单端支路和 N 侧重复状 ladder 必须通过当前 Spectre netlist/原理图逐端点解释。

### P1：阻止 gate-level/tapeout signoff

1. SRM 22 decisions 与 VM 21 normal latch bits 不匹配，缺真实 residue sequence。
2. ASIC SDC 缺失，27/71 unconstrained ports。
3. CDC/RDC、reset release、power intent、多电压 level-shifter 未签核。
4. 没有 RTL-to-gate equivalence、GLS/SDF、scan/ATPG/MBIST。
5. weight readiness、residue transaction pairing、calibration_done 语义未硬化。
6. xpr、canonical rtl/ 和 delivery copies 虽当前 hash 相同，但缺少防分叉的单一生成/校验机制。

### P2：发布质量

1. 历史 TB 总检查数 93 与当前 49+17+17+10=100 不一致。
2. 校准 TB MC_RUNS=5 适合 smoke test，不足以支持 yield。
3. 参数 guard 已锁定 qualified configuration，文档应避免描述为通用 IP。
4. always_ff 中 blocking arithmetic 应有 lint waiver 或结构化重写。
5. xpr 将 sar_reconstruction/srm_residue_estimator 标记为 AutoDisabled，GUI build 与脚本 build 可能语义不同。

## 14. 推荐闭环顺序

1. 冻结位序、EOC、code hold、Q8、SRM 数量、reset 和 ownership contract。
2. 核实 CDAC_MAIN_20b 当前 Spectre netlist，重新提取 effective weights。
3. 实现 sar16b_code_capture_adapter：BITP<20:1> + async EOC + bundled-data CDC。
4. 实现 sar16b_calib_phy_sequencer 和 normal/calibration/SRM mode arbiter。
5. 先做无噪声、SRM-off、连续 512 点 normal conversion，证明理想 16-bit code/FFT 不下降。
6. 再加入 static mismatch，比较 nominal、calibrated、oracle。
7. 再加入 comparator/reference/settling/VCM/SRM noise，验证 SRM on/off 因果关系。
8. 完成 ASIC SDC、CDC/RDC、reset/power intent、LEC、GLS/SDF、DFT。
9. AMS/PEX 重跑至少 512 个有效 decoded samples，固化 raw waveform、code、FFT、INL/DNL 和 run log。
10. 最后讨论 GDS/tapeout 和 TCAS/JSSC 结果包装。

## 15. Final disposition

**当前 RTL 是否能到达 netlist？**
能。独立模块和 skeleton top 已有 Vivado 综合证据，但这是 FPGA/单时钟、部分约束的 netlist readiness。

**当前 RTL 是否能直接用于 VM SAR_16B_5M？**
不能。必须先修正 BITP<20:1>/EOC、异步到同步 CDC、旧实例 ignored、calibration PHY 和 SRM sequence。

**当前 RTL 是否已到达 GDS/流片？**
没有。ASIC physical flow、DFT、power intent、equivalence、GLS/SDF、PEX、DRC/LVS、GDS 和 silicon evidence 均未闭合或本轮未检查。

**Reviewer 1 disposition：NO-GO for tapeout integration；GO for adapter implementation and pre-signoff closure。**
