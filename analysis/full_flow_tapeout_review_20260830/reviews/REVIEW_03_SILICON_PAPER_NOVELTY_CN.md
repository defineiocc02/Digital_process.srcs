# REVIEW 03：硅片验证、生产测试与论文创新边界审查

审查日期：2026-08-30
审查角色：Independent Reviewer 3
审查范围：RTL、行为级模型、VM 中的 SAR_16B_5M 电路族、流片前签核边界、晶圆/封装/ATE/实验室硅片验证方案，以及与 Huang 等论文的关系和可辩护创新点。
审查方式：只读检查仓库报告、脚本、JSON/CSV/图形证据、RTL/约束入口，并读取本地两篇参考文献。此次不修改 RTL、不修改原理图、不重新运行模拟实验。

## 1. 执行摘要

### 1.1 最终判断

本项目目前可以被定义为：

> 一个已经建立了较完整数字算法验证基线的 Split-Sampling SAR ADC 数字后端工程，但尚未形成从 RTL、ASIC 网表、版图/GDS、封装、ATE 到实验室硅片数据的可签核证据链。

对流片和论文而言，当前状态为 **RED/YELLOW**：

| 领域 | 判定 | 依据 |
| --- | --- | --- |
| RTL 单元与综合 | GREEN，限定范围内 | Vivado XSIM、综合和已有报告均有证据 |
| 行为级 SAR/校准/SRM | YELLOW | 有 512 芯片模型和物理 CDAC 模型，但仍非晶体管级等效 |
| VM 顶层数字集成 | RED | 当前重构实例被忽略，bit slice、valid、时钟域和权重接口均未闭合 |
| ASIC 前端到 GDS | NOT PROVEN | 仓库没有可审查的最终 gate netlist、SDC、CTS、PEX、DRC/LVS、GDS/OASIS |
| 封装/ATE/实验室硅片 | NOT CHECKED/NOT AVAILABLE | 没有芯片、封装、探针卡、测试程序、原始测量数据或校准证据 |
| 复现 Huang 2025 | PARTIAL | 架构关系相符；具体开关序列、模拟噪声、SRM 物理序列和硅片性能未复现 |
| TCAS/JSSC 创新主张 | 暂不成立 | 当前最强结果仍是工程实现和行为级验证，缺少新电路边界及硅片证明 |

### 1.2 必须优先处理的四项阻断

1. **VM 顶层码位与有效信号错误**：真实物理 CDAC 使用 `BITP<20:1>`，现有重构实例使用 `BITP<19:0>`，并把 `BITP<20>` 当作 `data_valid`。
2. **重构实例没有真正进入网表**：VM 的 `sar_reconstruction` 实例带有 `nlAction=ignore`，权重写口、reset、输出和 SRM 接口没有形成闭合连接。
3. **异步 SAR 与同步数字后端边界未实现**：真实电路由 `READYN` 驱动自定时 `SET` 链，不能把比较器内部异步 `CLK` 直接当成多级数字流水线时钟。
4. **没有 ASIC/硅片证据**：仓库内没有最终 GDS/OASIS、signoff 报告、封装/探针卡资料、ATE 测试程序、实验室 raw waveform 或 die-level result lineage。

### 1.3 可以保留的工程结论

现有数字结果仍有价值，但只能按下列边界解释：

- 四个 XSIM testbench 已通过：重构 49 checks、Q8 split-weight 17 checks、SRM 17 checks、校准 TB 10 checks。
- 四个 Vivado 综合目标已通过，100 MHz 内部 slack 为正；这不是真实 ASIC 时序签核。
- 512 芯片物理 CDAC 行为级活动已完成，模型显示校准显著降低静态权重误差；这不是 foundry PDK Monte Carlo，也不是 transistor/PEX/silicon 结果。
- 现有项目最可靠的下一步是先把模拟-数字接口闭合，再进行无噪声、SRM-off、512 个有效输出点的系统基线测试。

## 2. 证据范围与审查边界

### 2.1 实际检查的主要文件

| 证据 | 用途 | 当前可用性 |
| --- | --- | --- |
| `rtl/sar_calib_ctrl_serial.sv` | 前台递归权重校准 RTL | 已存在，可综合 |
| `rtl/sar_reconstruction.sv` | Q8 加权重构与 16-bit 输出 | 已存在，可综合 |
| `rtl/srm_residue_estimator.sv` | 22 次 SRM 计数与 LUT | 已存在，可综合 |
| `rtl/sar_adc_digital_top.sv` | ASIC 数字集成 skeleton | 存在，但不是真实 SAR 顶层 |
| `docs/FIXED_POINT_CONTRACT.md` | Q8/输出定点合同 | 已存在 |
| `docs/MIXED_SIGNAL_TIMING_CONTRACT.md` | 混合信号时序假设 | 已存在，但边界仍待实现 |
| `analysis/full_sar_behavioral_20260729/` | 完整行为级 SAR 闭环 | 有模型、脚本、结果 |
| `analysis/physical_cdac_mismatch_20260729/` | 6+4+5+5 物理 CDAC 行为级失配 | 有模型、512 芯片结果 |
| `analysis/vm_sar16b_compatibility_20260830/` | VM 实际层次和端口审查 | 已发现集成阻断 |
| `docs/VERIFICATION.md` | 回归结果和证据边界 | 明确声明非 AMS/PEX/硅片签核 |
| `analysis/full_flow_tapeout_review_20260830/reproducibility_audit_adc.json` | 可复现性静态审计 | 状态 WARN，缺少 manifest/paper ledger |

### 2.2 证据等级定义

- **E0：声明**：README、论文草稿或注释中的设计意图，不能独立证明实现。
- **E1：数字单元证据**：RTL 仿真、lint、综合、固定输入输出检查。
- **E2：行为系统证据**：可重跑模型、固定随机种子、Monte Carlo、静态/动态指标。
- **E3：AMS/晶体管证据**：原理图到 Spectre 网表的可复现仿真和波形。
- **E4：版图签核证据**：post-layout PEX、DRC/LVS、STA/功耗/IR/EM 等。
- **E5：硅片证据**：晶圆、封装、ATE、实验室原始数据和 die-level 统计。

本项目当前主要达到 **E1/E2**；VM 兼容性检查提供了部分 E3 结构信息，但没有提供闭合 AMS 仿真结果。E4、E5 均未证明。

## 3. 三轮独立审查记录

### 3.1 第一轮：来源、结果和证据链审查

第一轮只问一个问题：**结果是否能被第三方从仓库中重新定位和重跑？**

结论如下：

1. 数字入口较清楚：`scripts/run_all_xsim.ps1`、`scripts/build.ps1`、行为级 runner、requirements 和报告均存在。
2. 物理 CDAC 512 芯片活动有 JSON/CSV/图和确定性 replay 说明，且明确写了 mismatch/settling/AMS 边界。
3. 仓库可复现性审计为 `WARN`，主要原因是缺少正式项目 manifest、结果 lineage 和 paper ledger。
4. 没有找到可进入 ASIC signoff 的 GDS/OASIS、最终网表、SDC/STA corner、PEX、DRC/LVS、scan/ATPG、功耗和封装资料。
5. 没有找到 wafer map、探针卡 pin map、ATE program、测试限值、设备校准证书、原始波形、binning 规则或 die-to-die 追踪。

第一轮判定：**数字结果可追踪性较好；完整 tapeout/silicon evidence chain 不存在。**

### 3.2 第二轮：算法、VM 电路和论文边界审查

第二轮把论文陈述、VM 层次和 RTL 逐项对齐，重点检查“相同名称是否真的代表相同物理事件”。

发现：

- VM 真实电路包含四段桥接 CDAC，概念上接近 `6+4+5+5` 分段结构。
- VM 的物理 CDAC 驱动只消费 `BITP/N<20:1>`；`BITP/N<0>` 是最后的附加判决，不是物理 CDAC LSB。
- 两个 Flash 判决和 19 个 comparator 判决形成 21 个锁存结果，其中前 20 个对应物理 CDAC，最后 1 个不应自动塞进 20 位权重和。
- VM 采用 `READYN -> SET` 异步自定时链；当前 RTL 后端假设自由运行数字时钟，这两个时序世界没有适配层。
- 当前 VM 中 `sar_reconstruction` 被忽略且连接悬空，因此不能把已有 VM 仿真称为 RTL 已接入。
- 当前 `srm_residue_estimator` 需要 22 个同一 residue 条件下的额外随机比较，VM 正常转换的 21 个锁存结果并不等于这 22 个 SRM samples。

第二轮判定：**架构思想相容，接口语义不相容；项目是部分复现和独立数字实现，不是论文模拟电路的完整复制。**

### 3.3 第三轮：流片、生产测试和论文主张对抗审查

第三轮用最苛刻的审稿/量产问题检查：**即使 RTL 和行为结果正确，是否能在晶圆、封装和论文中证明它？**

结论：

1. 当前 weight RAM 是易失的数字状态，没有 eFuse/OTP/SRAM retention/serial reload 的生产持久化接口。
2. 校准启动、完成、超时、权重 CRC/readback、测试模式和 raw-code observability 还没有成为真实 pad/scan/ATE 合同。
3. 没有 pin-level 版本的正常模式、校准模式、SRM 模式和 debug 模式互斥定义。
4. 现有 30 us Maestro 测试时长在 5 MS/s 下约只有 150 个转换，不能支撑 512 个有效输出点，更不能支撑高可信 FFT。
5. 论文草稿中的“complete digital calibration engine”“near-Pareto optimal”“realistic noise”类措辞超过了现有 E1/E2 证据。
6. Huang 2025 已经公开了 SS、22-decision SRM、6-bit reference 测 14 个 MSB、P/N/冗余校准、64 次 averaging 和硅片测量；这些不能再作为本项目独立创新。

第三轮判定：**可以写成工程验证和可复现数字实现，但当前不足以支持“已流片闭合”或“相对 Huang 的新电路创新”。**

## 4. 与 Huang 2025 及本地 2024 文献的逐项关系

### 4.1 Huang 2025 的已知设计边界

根据本地 PDF `0849 - Huang 等 - 2025 - A 5-MSs 16-bit low-noise and low-power split sampling SAR ADC with eased driving burden.pdf`：

- 目标为 16-bit、5 MS/s、180 nm CMOS。
- SS 使用两个约 20 pF 的 sampling capacitors 与约 1 pF CDAC，使采样和快速 bit-cycling 解耦，降低 kT/C 噪声并减轻输入驱动。
- AZ、preamplifier、latch 和 split sampling 的模拟时序是性能主因，不能用数字 weight correction 代替。
- 正常 bit-cycling 后加入约 22 次 extra comparator decisions；SRM 阶段 DAC 保持不更新，统计同一 residue 的判决概率。
- SRM 的理论形式为

  \[
  v_{res}=2\sigma_{v_{n,comp,in}}\,\mathrm{erf}^{-1}(2P-1),
  \]

  其中 `P` 来自 22 次额外比较中的“1”比例。22 次是噪声抑制和时间开销的折中，文中给出约 70 ns 的 SRM 时间尺度。
- 由于 1 pF CDAC 的 mismatch，未校准线性度约为 11 bit；6-bit LSB section 被复用为 reference DAC 测量 14 个 MSB。
- 论文报告校准时 SS+SRM 将 shorted-input noise 从约 111 uVrms 降到约 38 uVrms，并使所需 averaging time 约降低 10 倍；`Navg=64` 时报告平均 SNDR 约 94 dB、平均 SFDR 约 108 dBc、3-sigma worst-case SFDR 超过 100 dBc。
- 论文的芯片结果是约 0.57 mm2、5.31 mW、5 MS/s、93.7 dB SNDR、约 95 dB DR，且包含封装后测试、输入源滤波/缓冲、不同输入频率和 source resistance 扫描。

这些数字是论文的硅片结果，不是本项目行为模型的验收标准。尤其不能将本项目的 `trend_sndr_db=94` 或 `trend_sfdr_mean_db=108` 直接写成芯片性能预测。

### 4.2 本地 2024 文献的补充作用

本地 PDF `0764 - Huang - 2024 - Advanced clock multiplier and SAR ADC design techniques for high-resolution signal chain systems.pdf` 中第 4 章进一步给出：

- b6 及低位 reference DAC 的对向切换如何提供 comparator offset 的正负抵消；
- b18/b19 在没有正常两位 Flash 压缩时的 over-range protection；
- 6-bit LSB section 的 3-sigma INL 约 ±0.39 LSB 的建模口径；
- 22 次 SRM decision、校准 averaging 和 5 MS/s 芯片测量流程。

该文献可作为 Huang 架构的详细设计背景和关系证明，但不能充当本项目的新颖性来源。该文献同时讨论 clock multiplier；本项目没有实现该 clock multiplier，不能把论文中 clock multiplier 的贡献归入当前 RTL。

### 4.3 项目实现与论文的分类矩阵

| 要素 | Huang 2025/2024 文献 | 本项目 | 分类 | 证据边界 |
| --- | --- | --- | --- | --- |
| 16-bit、5 MS/s SAR 目标 | 有 | 有目标与 VM 电路族 | 联系 | 项目没有硅片性能 |
| SS：采样电容与小 CDAC 解耦 | 有完整模拟实现和测试 | VM 有 SS 相关电路；RTL不控制其完整时序 | 部分复现 | 需 AMS/PEX 波形 |
| 1 pF 级小 CDAC | 有 | VM 为四段桥接 CDAC；绝对值/替换件需核实 | 部分复现 | 当前 proxy 不是实物提取 |
| 6-bit LSB reference 测 14 MSB | 有 | `sar_calib_ctrl_serial` 采用类似递归边界 | 近似复现 | 实际 switching sequence 未接入 |
| P/N offset cancellation | 有模拟极性切换 | RTL有 `(P+N)/2` 算术思想 | 近似复现 | P/N PHY sequencer 缺失 |
| b18/b19 protection | 文献有明确 over-range switching | RTL有保护状态/接口意图 | 近似复现 | VM真实时序未验证 |
| 22-decision SRM | 有真实 latch/SAR 额外比较 | RTL有 22 计数与 LUT | 数字边界复现 | VM没有 22 次 residue-hold sequence |
| Q8 weighted reconstruction | 文献未以本项目 RTL形式公开 | 项目独立实现 Q8、流水、饱和 | 独立数字实现 | 真实 bit mapping 未闭合 |
| 6+4+5+5 physical CDAC model | 论文电容/桥接架构相关 | 项目行为级矩阵模型 | 近似/独立验证模型 | 不是 PDK/PEX |
| `BITP<20:1>` 到数字后端 | 文献未给本项目接口 | VM实际层次已发现此映射 | 独立集成发现 | 当前实例接错 |
| XSIM/Verilator/一致性脚本 | 论文未报告 | 项目独立工程化增加 | 独立工程贡献候选 | 不能单独构成电路创新 |
| 512 virtual chips | 论文为硅片和模拟统计 | 项目行为级 512 芯片 | 独立验证活动 | 不是 silicon n=512 |

## 5. 当前项目验证结果的正确解读

### 5.1 RTL 和综合结果

已有 `docs/VERIFICATION.md` 记录：

- `tb_sar_recon_binary_norm`：49 checks，PASS；
- `tb_recon_q8_split_weights`：17 checks，PASS；
- `tb_srm_residue_estimator`：17 checks，PASS；
- `tb_gain_comp_check_lsb`：5 个 Monte Carlo run、10 checks，PASS，最差 residual `0.4937 LSB`；
- `sar_reconstruction`、`sar_calib_ctrl_serial`、SRM 和 top skeleton 的 Vivado 综合均无 error，100 MHz 约束下内部 WNS 为正。

这证明“当前模块在定义好的数字合同下可仿真和综合”。它不证明：

- comparator 的模拟事件能被正确采样；
- weight write-back 在 VM 中真正发生；
- 版图后时序仍满足；
- calibration 的 analog P/N switching 等价于 TB；
- SRM 的 22 个 samples 来自同一个真实 residue；
- 芯片输出满足 16-bit SNDR/INL/DNL。

### 5.2 完整行为级结果

`analysis/full_sar_behavioral_20260729/outputs/summary.json` 的正式行为级活动包含 512 个 virtual chips、20 个 signed decisions、当前 RTL 校准、22-decision SRM、Q8 重构、FFT 和 ramp-histogram 指标。其典型汇总为：

- `NOMINAL_NO_SRM`：SNDR 中位数约 `34.96 dB`；
- `CAL_NO_SRM`：SNDR 中位数约 `89.14 dB`；
- `CAL_SRM`：SNDR 中位数约 `91.02 dB`，SFDR 中位数约 `108.78 dBc`；
- `ORACLE_SRM`：SNDR 中位数约 `91.99 dB`；
- `CAL_SRM` 静态 INL peak-to-peak 中位数约 `2.015 LSB`，DNL peak-to-peak 中位数约 `1.477 LSB`，缺码中位数为 0，尾部仍有缺码。

这些结果清楚表明校准有效，但也清楚表明当前带噪行为模型没有达到理想 16-bit 量化极限。它们不应被包装为 Huang 论文的绝对 SNDR 复制结果。

### 5.3 物理 CDAC 行为级再验证

`analysis/physical_cdac_mismatch_20260729/` 的再验证更接近真实失配结构：6+4+5+5 分段 CDAC、面积律 mismatch、桥接矩阵求解，并以当前 RTL 校准和 SRM 解码。报告明确声明 mismatch sigma 和 parasitic 假设不是 foundry PDK card，SS/VCM/AZ/Flash timing 未包含。

该活动给出的重要基线为：

- 理想直接量化 SNDR：`98.079 dB`；
- exact physical residue：`98.079 dB`；
- deterministic SRM：`98.045 dB`；
- stochastic SRM：约 `97.145 dB`；
- 512 芯片当前校准满幅 SNDR 中位数约 `95.256 dB`，最差约 `55.619 dB`；
- -1.72 dBFS 回退输入的校准 SNDR 中位数约 `93.577 dB`，最差约 `91.206 dB`；
- DNL max 中位数约 `0.968 LSB`，INL max 中位数约 `0.993 LSB`，缺码中位数 0，最差缺码仍存在。

其中 full-scale 极端 tail 与输出 headroom/饱和有关。analysis-only headroom guard 不能被写成已实现 RTL，也不能被写成论文硅片结果。这个结果反而说明下一步必须把输出码域、总增益和 full-scale handling 固化进真实接口合同。

## 6. 从 RTL 到 GDS 的完整签核审查

### 6.1 当前已有和缺失的 flow

| Flow 阶段 | 当前证据 | 状态 |
| --- | --- | --- |
| RTL lint | Verilator/一致性脚本入口存在 | 部分通过，需保存 CI log |
| RTL simulation | Vivado XSIM 4 TB PASS | 已证明数字单元 |
| RTL formal | 未见 property/formal proof artifact | 缺失 |
| Synthesis | Vivado FPGA standalone synthesis PASS | 非 ASIC signoff |
| ASIC elaboration | `sar_adc_digital_top` 仅 skeleton | 缺失真实 integration |
| ASIC gate netlist | 未发现可审查的最终网表 | 缺失 |
| ASIC SDC/STA | 未发现多 corner signoff | 缺失 |
| CDC/RDC | 有文字 timing contract，无工具报告 | 缺失 |
| DFT/scan/ATPG | 未见 scan insertion、coverage、patterns | 缺失 |
| UPF/电源意图 | 未见 | 缺失/未检查 |
| Floorplan/placement/CTS | 未见 | 缺失 |
| DRC/LVS/ERC | 未见 | 缺失 |
| PEX/post-layout AMS | 未见 | 缺失 |
| GDS/OASIS checksum | 未见 | 缺失 |
| Package/IBIS/pad ring | 未见 | 缺失 |

### 6.2 ASIC signoff 必须新增的证据

流片前至少应有一组带 commit SHA、PDK 版本和 corner 的不可变 artifact：

1. elaborated/gate-level netlist 与 `netlist_manifest.json`；
2. clock/reset/async event 的 SDC 及 STA report；
3. CDC/RDC report 和每一条 waiver 的理由；
4. scan/ATPG、memory test、test-mode 和 coverage 报告；
5. post-route SPEF/PEX、setup/hold、IR drop、EM、power；
6. DRC/LVS/ERC/PERC clean report；
7. final GDS/OASIS、layer map、top cell、seal ring 和 checksum；
8. 模拟顶层与 digital top 的 AMS netlist/config，确认当前 RTL view 不是旧版 view；
9. 最终 pin list、pad electrical limits、ESD/IO model 和 package parasitic；
10. 版本锁定的 tapeout checklist 和 signoff owner。

## 7. 晶圆、封装、ATE 与实验室硅片测试计划

### 7.1 测试目标和数据架构

每颗 die 的数据必须沿以下路径保存，不允许只保留报告截图：

```text
wafer_id / lot_id / die_xy / package_id / board_id
    -> raw ATE or oscilloscope files
    -> parser version + calibration coefficients
    -> per-die CSV/JSON
    -> aggregate statistics and figures
    -> signed release report
```

建议每个 raw record 带有：git commit、RTL/analog netlist revision、PDK/model revision、test temperature、supply、clock、input amplitude/frequency、instrument serial/calibration date、operator、timestamp、test mode 和 pass/fail reason。

### 7.2 流片前 DFT/可测性要求

必须在 package/ATE 计划前冻结以下可观测接口：

| 测试能力 | 必须可见/可控信号 | 目的 |
| --- | --- | --- |
| digital smoke | `dig_clk`, reset, scan/test enable | 确认数字逻辑上电和时钟 |
| raw code capture | `BITP<20:1>`、EOC、captured code readback | 区分模拟 SAR 错误和 decoder 错误 |
| calibration control | start、busy、done、timeout、error | 验证校准 FSM 生命周期 |
| weight readback | address、data、CRC/version | 确认 14 个权重已写入且无位错 |
| P/N calibration visibility | phase、target bit、comparator result | 诊断 offset 和极性错误 |
| SRM visibility | residue hold、decision valid、count、residue | 确认 22 次 decision 同属一笔转换 |
| mode ownership | normal/calibration/SRM owner | 防止多源同时驱动 SET/BITP/BITN |
| analog monitors | VCM、AZ、reference、common-mode test pads | 诊断电源/VCM/settling 问题 |

当前 weight RAM 是易失状态。需要明确选择：

- 每次上电自动前台校准；
- 通过 SPI/JTAG/scan 重新装载权重；
- eFuse/OTP 存储 trim；
- retention SRAM 保存权重。

没有这个决定，就不能设计 calibration persistence 测试，也不能定义量产时间。

### 7.3 Wafer sort 方案

推荐初始统计规模：至少 3 个 wafer/lot，若条件允许覆盖 2 个 process lot；每片 wafer 选择中心、内圈、边缘等位置共至少 30 个 die，首轮总量不低于 90 die。正式量产限值应在 pilot wafer 后根据 yield 数据冻结，不能事先从 5 个样品推导。

wafer sort 顺序：

1. probe continuity、pad leakage、ESD/IO short、supply ramp current；
2. 1.8 V/3.3 V 分域静态电流和数字 scan；
3. free-running digital clock、reset release、test mode register readback；
4. 低速输入下 raw code capture，检查 `BITP<20:1>`、EOC 和 code sequence；
5. `SRM_OFF` 基线和 `SRM_ON` 计数/残差可见性；
6. 运行一次固定 Navg 的 foreground calibration，记录每个 bit 的权重和状态；
7. 读回权重、CRC、版本、done/timeout/error；
8. 低成本 DC/ramp/shorted-input screening；
9. 通过 wafer binning 后再进入封装。

首轮 wafer sort 不应直接把高精度 SNDR 作为唯一 bin。先确保每颗 die 的数字接口、校准结束和 raw code 连续性正确，否则模拟性能失败无法定位。

### 7.4 封装后 ATE 计划

封装后至少保留一批未校准和一批完成校准的对照：建议 pilot 取 30--60 packaged die，正式统计至少 100 die，并记录 wafer 坐标以分析 package/wafer 相关性。

ATE 必测项目：

- pin continuity、leakage、1.8 V/3.3 V current、power-up/down；
- digital register/scan/loopback；
- clock frequency、duty、reset/EOC latency；
- calibration time、timeout rate、weight readback repeatability；
- calibration persistence：校准后断电、上电、换温、换电源后权重是否保留或是否按设计重新校准；
- DC transfer：offset、gain、monotonicity、missing code、DNL、INL；
- dynamic FFT：SNDR、SNR、SFDR、THD、ENOB、DR、tone amplitude；
- `SRM_OFF`、`SRM_ON`、`SS_OFF`、`SS_ON` 四路 ablation；
- source resistance sweep、输入共模 sweep、输入频率 sweep；
- 供电和温度 corner。

### 7.5 实验室 bench 方案

低频输入（不高于约 20 kHz）应使用低噪声高线性信号源、RC low-pass、差分 buffer 和已校准示波器/采集卡。高频输入（约 500 kHz 至 Nyquist）应使用匹配的 band-pass/filter/differential driver；必须测量外部信号源噪声，因为 SRM 不能消除源噪声。

建议的核心记录：

| 类别 | 扫描点 |
| --- | --- |
| 输入频率 | 1 kHz、20 kHz、500 kHz、1 MHz、Nyquist 附近，另加全频 sweep |
| 采样率 | 低速 smoke、目标 5 MS/s、时钟上下限 |
| 输入幅度 | -60 dBFS 至 -0.5 dBFS、满幅单独记录 |
| 共模 | 低/标称/高三个有效范围点 |
| 供电 | 1.8 V 和 3.3 V 各自 nominal、±5%、±10% |
| 温度 | -40 C、25 C、85 C、125 C，具体以封装和工艺资格为准 |
| 模式 | SS/SRM/校准组合，以及 calibration Navg sweep |
| 源阻抗 | 至少 10、25、50、100、190 ohm 或按驱动设计实际范围 |

动态 FFT 至少使用 8192 点；论文复现/最终性能建议 65536 点并使用 coherent tone 或明确 window、bin exclusion 和 spur definition。`512` 个有效解码点是 bring-up 下限，不足以做稳定的低噪声 FFT 结论。

### 7.6 静态 DNL/INL

不能用少量正弦点或 rough histogram 代替正式静态测试。建议：

- ATE 精密 ramp 覆盖全码域；
- 或使用严格定义的 sine-histogram transition extraction；
- 分别记录 raw-code、nominal decoder、calibrated decoder、SRM off/on；
- 计算 missing code、DNL min/max/pp、INL endpoint-fit 和 best-fit 两种口径；
- 明确是否将输出饱和端点排除；
- 保存 transition-level raw counts，而不是只保存最终 INL 图。

### 7.7 PVT 和 Monte Carlo-to-silicon correlation

关联应分三级：

1. **参数层**：从 PDK mismatch、CDAC layout extraction、reference impedance、comparator offset/noise 得到模型分布；
2. **中间层**：比较每个 die 的 calibrated weight、P/N measurement difference、SRM count distribution、calibration time；
3. **性能层**：比较 SNDR/SFDR/INL/DNL/power/temperature drift 的 median、P5、P95 和 outlier。

模型只能在真实测试数据覆盖后重新校准。不能为了匹配论文 93.7 dB 而回调 mismatch sigma 或噪声参数，然后把调参后的结果作为预测验证。

## 8. 失败诊断树

| 硅片现象 | 首要怀疑 | 建议证据 |
| --- | --- | --- |
| 所有输出为零/饱和 | weight RAM 未写、reset/CDC、实例未综合 | weight readback、EOC、netlist connectivity |
| 码序跳变或反向 | `BITP<20:1>` 位序、P/N 极性、Flash 对齐 | raw bits 与理想 ramp 对照 |
| 低频尚可、高频 SNDR 掉 | input driver、VCM/SS settling、clock jitter | source impedance、频率 sweep、VCM waveform |
| SRM_ON 比 SRM_OFF 更差 | residue 未保持、22 samples 不同 residue、符号/LUT 错 | SRM count/residue trace、same-code replay |
| 校准不改善 | calibration PHY 未真正翻转、P/N 未互换、参考 DAC range 不足 | per-bit P/N raw measurement、phase trace |
| b18/b19 单独出错 | over-range protection 或 Flash mapping 错 | top-bit code sweep、vDAC range monitor |
| 满幅失败、回退幅度正常 | output headroom、symmetric gain normalization、饱和 | clip fraction、pre-saturation accumulator |
| 温度漂移明显 | AZ bandwidth、reference、VCM、comparator offset | corner waveforms、recalibration test |
| wafer 与 package 差异大 | package parasitic、bond/board、supply integrity | wafer vs package paired die |
| 单点周期 spur | clock/VCM feedthrough、digital coupling | clock spur、FFT spur map、supply probe |

## 9. 当前可辩护的 TCAS/JSSC 创新假设

以下不是已确认的新颖性，只是需要实验支持的候选假设。任何“novel/first/state-of-the-art”表述都必须在投稿前完成独立文献检索和边界比较。

### 9.1 TCAS-II 候选：异步 SAR 到数字后端的可验证接口架构

**假设**：提出一个面向 asynchronous split-sampling SAR 的 code-capture/CDC/mode-arbitration adapter，使 `BITP<20:1>`、EOC、foreground calibration 和 SRM 共享模拟开关资源，同时保证无丢码、无混码和固定 latency。

**与 Huang 的差异**：Huang 重点是模拟 SS、SRM 和芯片性能；当前候选重点是把真实异步 `READYN/SET` SAR 与独立数字 clock domain 安全闭合。

**必须补齐**：

- 可综合 adapter RTL；
- CDC/RDC/formal assertions；
- gate-level/SDF 和 AMS co-simulation；
- 5 MS/s 连续转换无丢码实测；
- 与简单直接连线 baseline 的 latency、面积、功耗、鲁棒性对比；
- PVT 下 EOC-to-capture margin。

**创新风险**：单纯“加同步器、写接口合同、做工程文档”通常不足以构成 TCAS-I/JSSC 电路创新；必须证明该架构解决了真实 split-sampling 异步事件的确定性和可量产测试问题。

### 9.2 TCAS-II 候选：校准、SRM 和 full-scale headroom 的联合数字策略

**假设**：建立一个不依赖 oracle 的校准后权重归一化/单边 headroom 管理策略，在保持 DNL/INL 的同时避免满幅饱和，并用 SRM 统计量决定有效平均次数。

**与当前结果的联系**：物理 CDAC 行为级结果显示 `CAL_CURRENT_SRM` 有明显 full-scale tail，analysis-only headroom guard 可以改善 tail，但尚未进入 RTL。

**必须补齐**：

- 数学证明或误差界；
- 对称 normalization、单边 guard、无 guard 的 ablation；
- 不同 mismatch、供电、温度、输入幅度下的 512/1000+ virtual chips；
- RTL bit-exact 实现；
- 真实 AMS 和 silicon full-scale INL/SNDR 证据。

**创新风险**：若只是对总权重乘一个 scalar，可能被认为是普通 gain correction；新意需要来自冗余 SAR 的 headroom 约束、非对称保护和 SRM/校准误差联合优化。

### 9.3 TCAS-I 候选：面积/噪声受限的低复杂度 SRM estimator 与校准协同

**假设**：根据实际 AZ/SS 噪声和 residue range，设计可综合的低复杂度多点 LUT/近似 estimator，使 22-decision SRM 在有限硬件下接近理想 moving average，并参与校准误差降低。

**必须补齐**：

- 与原始 inverse-normal LUT、分段线性、MLE、Bayesian estimator 的定量比较；
- ASIC area、power、latency，而不是只报告 FPGA LUT/FF；
- estimator quantization error、noise mismatch、decision correlation 的敏感度；
- `SRM_OFF`、exact residue、deterministic SRM、stochastic SRM 四路基线；
- 硅片输出和电源测量。

**创新风险**：Huang 已经公开 22-decision SRM。若仅把 erfinv 离线算成 LUT，不足以成为新算法；必须有新的统计估计、硬件/精度 tradeoff 或与异步 calibration 的协同机制。

### 9.4 JSSC 候选：不能直接沿用的方向

当前项目不适合直接以“另一款 16-bit 5-MS/s SS+SRM SAR ADC”投稿 JSSC，因为 Huang 2025 已经覆盖这一主架构和硅片结果。要达到 JSSC 级别，至少需要一个清晰的新电路贡献，例如：

- 新的 VCM/SS 时序，能在更短 AZ 或更低功耗下保持噪声和线性；
- 新的 CDAC/参考驱动架构，显著降低 driving burden 或面积；
- 新的 calibration PHY，在真实模拟资源下缩短校准时间并降低额外电路；
- 新的 SRM 采样/统计电路，解决 source noise、decision correlation 或带宽限制；
- 新的封装/系统协同，使高输入频率和高源阻抗下性能仍保持；
- 以上至少一项需要 transistor/post-layout/silicon 证明，并对 Huang 及其他 16-bit SAR 给出公平表格。

仅有以下内容通常不足以单独支撑 JSSC 电路创新：

- 3 个 RTL module 的工程化封装；
- Vivado 100 MHz slack；
- 26 LUT 的 SRM LUT；
- 5 次或 32/80 次行为 Monte Carlo；
- README/MOC/CI/约束整理；
- 复现已有论文的 6-bit reference、22-decision SRM 或 b18/b19 protection。

## 10. 论文草稿中的主张修正建议

| 当前可能的说法 | 审查意见 | 建议替换 |
| --- | --- | --- |
| complete digital calibration engine for the ADC | 容易被理解为完整芯片已闭合 | “digital-boundary calibration/reconstruction engine” |
| reproduces Huang's architecture | 目前只复现数字可表达边界 | “implements a qualified digital abstraction of selected algorithmic elements” |
| realistic noise | 当前为行为噪声锚点/模型假设 | “paper-anchored behavioral noise surrogate” |
| near-Pareto-optimal SRM LUT | 没有 ASIC 横向比较 | 删除，或给出完整 area/accuracy/latency Pareto data |
| validates 16-bit performance | 行为结果和 VM 集成尚未闭合 | “validates the defined RTL/behavioral contract” |
| first / novel parameter guards or methodology | 缺少文献边界和技术效果 | 降为 reproducibility practice |
| 512-chip Monte Carlo proves yield | virtual chips 不是 silicon yield | “512-chip behavioral statistical campaign” |
| 94 dB / 108 dBc acceptance | 当前是 trend marker，不是全 ADC acceptance | 明确写成 calibration-error-limited trend threshold |

论文中若保留 Huang 的 93.7 dB、5.31 mW、180.4 dB FoMS 等数据，必须明确这些是引用的外部硅片结果，不是本项目结果。

## 11. 推荐的流片前停止线

在以下项目全部完成前，不建议宣称 tapeout-ready：

### P0：接口与网表

- 修正 `raw_bits = BITP<20:1>`；
- 用明确 EOC/`SET<20>` 事件，不再用 `BITP<20>` 作为 valid；
- 增加 atomic capture + CDC；
- 重新生成 Cadence SystemVerilog view、symbol、config；
- 移除 `nlAction=ignore` 前确认新 view 完整连接；
- 从当前 Spectre netlist 核实 CDAC P/N 拓扑和疑似悬空支路；
- 定义独立 `dig_clk`、reset release 和 mode ownership。

### P1：真实算法序列

- 实现 `sar16b_calib_phy_sequencer`；
- 证明 P/N 物理极性翻转和 comparator wait/settling；
- 实现 22 次 SRM residue-hold sequence，或按真实次数重新设计 LUT；
- normal/calibration/SRM 三种模式互斥；
- 权重 readback、CRC、timeout、错误状态和 persistence 方案冻结。

### P2：签核与量产准备

- ASIC lint/CDC/RDC/formal/gate-SDF/STA/DFT；
- 多 PVT、OCV/AOCV、clock uncertainty、IR/EM、post-layout AMS；
- DRC/LVS/ERC/PEX；
- package/pad/ATE/bench 测试规格和 raw-data schema；
- wafer/package sample plan、bin limits、failure taxonomy；
- 形成 reproducibility manifest 和 paper claim ledger。

## 12. 本审查的最终结论

### 对工程

当前 RTL 不是无效方案。它对真实 SAR_16B_5M 的 20 路 CDAC、冗余权重、6 位低位参考段和数字校准方向具有合理匹配性，且已经有较好的数字单元和行为级验证基础。但它目前仍是**可移植的算法核心**，不是**已接入 VM 并完成 ASIC 流片签核的数字后端**。

### 对论文

与 Huang 2025 的关系应写成：

> 本项目复用了并数字化验证了 Huang 架构中的部分算法边界，包括 20-decision weighted reconstruction、6-bit reference-assisted recursive calibration 的抽象思想和 22-decision SRM estimator；SS/VCM/AZ/Flash/CDAC 的晶体管级时序及硅片性能不属于当前实现的已证明范围。

### 对创新

目前最稳妥的投稿方向是 **TCAS-II 风格的可验证数字集成/校准接口工作**，前提是完成真实 asynchronous SAR adapter、CDC、模式仲裁、SRM 物理序列和至少一次 AMS/FPGA/硅片闭环证明。TCAS-I 需要更强的算法/电路对比；JSSC 需要新的模拟电路或系统级硅片结果，不能只依靠现有 RTL 和行为模型。

### 结论等级

```text
RTL algorithm core:              PASS within defined digital contract
Behavioral mismatch validation: PARTIAL PASS, model-bounded
VM mixed-signal integration:    FAIL / blocked by P0 interface issues
ASIC-to-GDS signoff:            NOT PROVEN
Package/ATE/silicon:            NOT AVAILABLE
Huang reproduction:             PARTIAL, digital-boundary only
Novelty claim:                  NOT YET DEFENSIBLE without new evidence
Tapeout recommendation:        HOLD until P0/P1 closure
```

本文件是第三轮独立审查的唯一 checkpoint artifact。它没有修改代码、原理图、VM 数据库或其他项目文件。
