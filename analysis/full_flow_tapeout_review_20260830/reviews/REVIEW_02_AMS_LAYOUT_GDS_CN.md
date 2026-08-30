# REVIEW 02：SAR_16B AMS 至 GDS/流片全流程独立审查

审查角色：Mixed-Signal SAR ADC Tapeout Audit，Independent Reviewer 2
审查日期：2026-08-30
审查边界：`SAR_16B_5M` VM 原理图/AMS、CDAC、采样与 VCM 时序、比较器/Flash/异步 SAR、校准物理接口、SRM、PDK/模型/角落、版图/GDS/signoff、后仿真及硅前测试证据。
操作边界：只读审查；未修改 VM、原理图、版图、RTL、约束或其他工程文件；未运行新的 Spectre/Calibre/PEX/ATE 实验。

## 1. 审查结论

### 1.1 结论先行

当前工程的 RTL 算法与 `SAR_16B_5M` 的**架构方向相容**，但不具备直接接入和流片交付条件。

| 判定层级 | 结论 | 证据状态 |
|---|---|---|
| 20 路分段/桥接 CDAC 与加权重构方向 | 相容 | 已由 VM OA 层次与本地模型交叉支持 |
| 6 位低位参考段与 14 位高位权重校准方向 | 相容，但需物理时序适配 | 架构证据有，闭环证据无 |
| 当前 RTL 直接接入 VM 顶层 | 不相容 | 当前 bit slice、valid、时钟、实例状态均有阻断问题 |
| 22-decision SRM 直接接入 | 不成立 | VM 当前只暴露 21 个正常判决，未发现 SRM 序列 |
| 原理图级 AMS 已闭环 | 未证明 | Maestro 历史记录包含 simulation errors |
| 版图/GDS/DRC/LVS/PEX signoff | GAP | 当前 SAR16B 范围未发现对应产物 |
| Tapeout readiness | FAIL / BLOCKED | 缺少多个 P0 signoff gate |
| Silicon test readiness | NOT READY | 没有可追溯的芯片、ATE、封装和测试数据包 |

### 1.2 最高优先级阻断项

1. **P0：当前 `sar_reconstruction` 实例使用错误码位。** VM 顶层把 `raw_bits<19:0>` 接到 `BITP<19:0>`，实际 20 路物理 CDAC 为 `BITP<20:1>`；这会丢失最高 CDAC 位并错误纳入附加判决位。
2. **P0：当前 valid 信号错误。** `data_valid_in` 接在 `BITP<20>`，但 `BITP<20>` 是 Flash/CDAC MSB，不是转换结束脉冲。
3. **P0：异步时钟域不成立。** `I94.clk` 接在比较器/SAR 异步活动信号 `CLK`，而当前重构 RTL 按自由运行同步时钟设计。
4. **P0：当前数字实例被忽略且写口悬空。** `I94.nlAction=ignore`；`rst_n`、`w_wr_en`、`w_wr_addr`、`w_wr_data`、`adc_dout`、`data_valid_out` 在当前 VM 顶层没有形成可验证闭环。
5. **P0：CDAC 连接存在待解释异常。** `CDAC_MAIN_20b` OA 数据显示 N 侧重复状链路和 P 侧 `net22...net28` 单端支路。必须先通过当前 Spectre 网表核实，不能假定这是正常对称布局前的抽象。
6. **P0：foreground calibration 没有物理开关时序器。** 当前校准 RTL 只输出抽象 `dac_p_force/dac_n_force`，未接管 `SET/RSTT/VCM/CLKAZ/READYN`，不能直接驱动 VM 的两个差分 CDAC switch driver。
7. **P1：SRM 未闭合。** 数字 LUT 为 22 次判决，但 VM 顶层没有 22 次同一 residue 的额外比较序列，也没有 SRM 端口或 residue hold 机制。
8. **P1：不存在 SAR16B 的版图/GDS/signoff 证据。** VM 中发现的 GDS、DRC/LVS 文件属于其他 `14BIT_ADC` 系列，不能证明 `SAR_16B_5M` 已完成版图签核。

## 2. 证据与可信度边界

### 2.1 直接检查的输入

| 证据 | 位置/对象 | 审查用途 | 状态 |
|---|---|---|---|
| VM 库清单 | `/home/meow/IC/SAR_16B_5M_CORE`、`_EXP`、`_TB` | 确认设计系列和 cell | verified |
| OA 跨库层次 | `SAR_16B_5M_TB/TEST_TRAN_ALL_TRANSISTOR_wFLash_ver6` | 确认 CDAC、SS、Flash、比较器、SAR、数字实例连接 | verified |
| 未过滤 CDF/实例参数 | `checkpoint_sar16b_full_params.json` | 确认激励、电源、时序和 I94 端口 | verified |
| Maestro 配置 | `checkpoint_sar16b_maestro.json` | 确认当前 transient、noise、模型和输出 | verified |
| 历史日志 | `checkpoint_sar16b_history_logs.json` | 确认既有运行是否真正成功 | verified |
| VM 文件树 | `checkpoint_sar16b_series.json` | 确认仿真 scratch 规模和结果类型 | verified |
| 当前 RTL | `rtl/*.sv` | 与 VM 端口、时钟和算法边界比较 | verified |
| 物理 CDAC 行为模型 | `analysis/physical_cdac_mismatch_20260729/` | 检查本地失配模型和验证边界 | verified |
| repository signoff 文档 | `README.md`、`docs/VERIFICATION.md` | 复核已有声明是否越过证据边界 | verified |

### 2.2 不能从现有材料推出的结论

- RTL XSIM 通过不等于 AMS 通过。
- 行为级 CDAC 失配实验不等于 PDK mismatch 或版图后仿真。
- `.rdb` 历史目录存在不等于 Spectre 成功；本次读取到的 log 明确记录 simulation errors。
- VM 中其他 ADC 的 GDS/DRC/LVS 结果不属于 SAR16B，不能借用作 signoff 证据。
- 本报告没有访问或修改芯片版图，也没有执行 Calibre、PEX、IR/EM、天线、密度填充或 ATE 测试。

## 3. 四轮独立审查记录

为满足独立复核要求，本 checkpoint 采用四个彼此分开的审查视角。每轮都重新检查“证据是否支持结论”，不把前一轮的判断直接当作通过条件。

### Review Pass A：架构和信号映射复核

检查对象：顶层 OA 层次、CDAC 端口、Flash、`SAR_Logic_transistor_woflash`、两个 `CDAC_SWITCH_DRIVER_NEW`、`sar_reconstruction`。

独立结论：

- `SET<0>` 到 `SET<19>` 控制 20 个物理 CDAC 决策，映射到物理 bit 20 到 bit 1。
- `SET<20>` 锁存 `BITP/N<0>`，它是附加判决/残差相关信息，不驱动物理 CDAC。
- 正常转换共有 21 个锁存结果：2 个 Flash 判决加 19 个比较器判决；其中 20 个结果参与 CDAC，1 个为附加结果。
- 当前 I94 使用 `BITP<19:0>`，因此存在确定的位序错误。
- 当前 `data_valid_in=BITP<20>`，因此 valid 语义也错误。

判定：**架构方向 PASS；现有顶层接入 FAIL。**

### Review Pass B：AMS/时序/校准物理接口复核

检查对象：split sampling、VCM、AZ、`READYN`、`CLK0/CLK00`、`RSTT`、比较器及校准 RTL。

独立结论：

- VM 正常转换使用异步 ready-driven SAR：`COMP_AZ.READYN` 回送 `SAR_Logic_transistor_woflash.CCLK`，再推进 `SET<0:20>`。
- 关键 5-MS/s 周期为约 200 ns；已有配置包含 `CLKS`、`CLKSTOP`、`CLK_nt`、`CLKDAC_top`、`CLKAZ`、`RSTT` 和异步 SAR reset 释放时序。
- `sar_calib_ctrl_serial.sv` 的 `COMP_WAIT_CYC=16` 只是数字周期等待，不能自动等价于真实 CDAC settling、VCM 稳定或 comparator ready。
- `dac_p_force/dac_n_force` 是抽象差分控制量；VM driver 还要求 `BITP/BITN/SET/RSTT/VCM` 的互补、三态和高压/低压域控制。
- 校准必须在正常转换、foreground calibration、SRM 三种模式之间实现互斥 ownership，否则存在两个控制源同时驱动模拟开关的风险。

判定：**数字算法接口有复用价值；AMS 物理接口未实现，校准闭环 FAIL。**

### Review Pass C：版图/GDS/signoff 复核

检查对象：repository 与 VM 的 GDS/OASIS、layout、DRC/LVS/PEX、IR/EM、antenna/ERC/latch-up/ESD、density/fill 和 release package。

独立结论：

- 当前 repository SAR16B 工程没有对应 GDS/OASIS、DEF/LEF 版图交付、PEX/SPEF、Calibre DRC/LVS/PEX 或 IR/EM 报告。
- VM `/home/meow/IC` 搜索到的 GDS 和大量 DRC/LVS 文件集中在 `/home/meow/IC/14BIT_ADC`，属于其他设计系列；这些文件不能作为 SAR16B signoff。
- 未找到 SAR16B 的 layout cell、stream-out manifest、top-level GDS hash、层映射、seal-ring/IO/ESD 说明或 signoff runset 证据。
- 没有版图证据，无法判断 CDAC common-centroid、dummy、shielding、guard ring、参考线、VCM 线、比较器敏感节点、数字时钟隔离和电源回路质量。

判定：**所有 SAR16B 物理 signoff gate 为 GAP；tapeout readiness FAIL。**

### Review Pass D：论文/证据/可交付性挑战复核

检查对象：论文式主张、行为级报告、Maestro 历史记录、测试数据和流片交付闭环。

独立结论：

- 本地行为级实验可以支持“20 路分段 CDAC、Q8 重构、P/N 校准、22 次 SRM 数字边界”的算法研究结论。
- 现有物理 CDAC 模型的 mismatch 中心和 parasitic 参数来自项目模型假设，不是 PDK 版图后提取结果。
- 当前 VM Maestro 记录中 `ExplorerRun.0` 有 1 个 simulation error，`Interactive.7/8/9` 各有 1 个 error，`Interactive.6` 有 3 个输出表达式 error。
- 当前 `30 us` stop time 在 5 MS/s 下约提供 150 个转换，不足以支持 512 点 ADC 解码/FFT 证据。
- 没有芯片批次、封装、ATE pattern、校准寄存器配置、原始采集波形、温度/电源条件和仪器校准记录。

判定：**研究原型证据部分成立；论文绝对性能和 silicon readiness 未证明。**

## 4. VM 实际架构与 RTL 适配分析

### 4.1 顶层层次

从 OA 层次可确认以下链路：

```text
split-sampling SS_MAIN x 20 / differential sides
        -> CDAC_MAIN_20b (four segmented/bridge sections)
        -> Flash (2 initial decisions)
        -> COMP_AZ (auto-zero comparator / READYN)
        -> SAR_Logic_transistor_woflash (asynchronous SET chain)
        -> BITP/BITN<20:0>
        -> current sar_reconstruction instance I94 (ignored)
```

实际存在但没有接入当前维护 RTL 的模块：

- `sar_calib_ctrl_serial`
- `srm_residue_estimator`
- `sar_adc_digital_top`

因此当前 VM 不是“RTL 已经集成但性能还未优化”，而是“模拟 SAR top 与维护 RTL 仍处于接口未闭合状态”。

### 4.2 正确的 raw-code 映射

| 模拟结果 | 物理含义 | 推荐数字连接 |
|---|---|---|
| `BITP<20>` | Flash/CDAC 最高决策 | `raw_bits[19]` |
| `BITP<19:1>` | 其余 19 路物理 CDAC 决策 | `raw_bits[18:0]` |
| `BITP<0>` | 最终附加判决/残差信息 | 不作为 CDAC LSB；另存为 residue/EOC 辅助量 |
| `SET<20>` + `READYN` | 异步完成事件候选 | code capture/EOC adapter 输入 |

因此应采用：

```text
captured_raw_bits[19:0] = BITP[20:1]
```

必须在下一次 `RST/CLK0` 清除 bit latch 前完成原子锁存。不能把单个 Flash bit 直接当 valid。

### 4.3 时钟与 CDC

当前 `sar_reconstruction` 需要一个稳定的数字时钟，用于：

- 权重 RAM 写回；
- partial-sum pipeline；
- SRM counter；
- output valid pipeline。

VM 的 `CLK` 是比较器/异步 SAR 事件的一部分，不是自由运行时钟。推荐边界为：

```text
async BITP<20:1> + SET<20>/READYN
        -> atomic capture latch
        -> request/toggle synchronizer
        -> free-running digital clock domain
        -> sar_reconstruction
```

至少需要：

- asynchronous code capture latch；
- stable-data window check；
- request/acknowledge CDC 或 pulse-stretch synchronizer；
- reset release sequencing；
- one-shot EOC 防重复采样；
- overflow/timeout diagnostic。

直接把 `CLK` 接到多级重构会导致时钟不连续、采样边界不确定、权重写回与正常 code capture 竞争，以及异步脉冲宽度无法满足标准数字时序假设。

### 4.4 foreground calibration 物理边界

当前校准 RTL 的数学动作是：

```text
measure target weight using lower trusted weights
P/N polarity measurement
average 32 iterations
recursive writeback
top-bit protection for b18/b19
```

要连接 VM，必须新增 `sar16b_calib_phy_sequencer`，至少定义：

1. 进入 calibration 前停止采样输入并回到已知 VCM/reset 状态。
2. 配置 target/reference CDAC 码，生成两个 `CDAC_SWITCH_DRIVER_NEW` 所需的互补控制。
3. 约束 `RSTT`、VCM 预充、switch settle、auto-zero 和 comparator evaluate 的先后关系。
4. 以 `READYN` 或明确 comparator done 为完成条件，附加最大等待超时。
5. 通过 mode arbiter 禁止 normal SAR、calibration 和 SRM 同时驱动模拟开关。
6. 对校准读出的 comparator 极性作独立 golden-vector 校验，不能仅依赖信号名推断。

如果校准使用的 switching path 与正常 conversion 不同，校准得到的是 mode-specific effective weight，不能保证正常转换中的 code linearity 被修正。

### 4.5 SRM 边界

当前数字 LUT 的合同是 22 次额外判决：

```text
count -> Q8 residue -> reconstruction before rounding/saturation
```

VM 当前正常链只有 21 个判决输出，其中 20 个用于 CDAC，1 个为附加判决；不能直接将 `BITP<20:0>` 解释成 22 次 SRM。

要成立必须新增：

- normal SAR 结束后的 residue hold；
- 22 次相同 residue 条件下的 comparator evaluate；
- 每次 evaluate 后产生稳定且去重的 `decision_valid`；
- ones-count 与 analog polarity 的定义；
- SRM comparator noise/offset/相关性模型；
- `srm_residue` 与对应 raw code 的原子绑定；
- SRM 失败、超时和过饱和处理。

若实际电路无法提供 22 次独立观察，则应重新推导 LUT，而不是用现有 22-entry LUT 强行接线。

## 5. CDAC、VCM、匹配和版图风险

### 5.1 CDAC 架构联系

VM `CDAC_MAIN_20b` 的决策结构与本地行为模型在高层次上相符：

- 四段分段/桥接结构，概念上接近 `6+4+5+5`；
- 20 个物理 CDAC 控制位；
- 低位段可作为参考权重基础；
- 高位存在冗余/非二进制有效权重。

这足以支持“当前 RTL 算法值得适配”的架构判断，但不足以支持真实权重表。实际权重必须从当前 schematic netlist、器件 CDF、bridge/parasitic 和版图 PEX 重新计算。

### 5.2 重合/悬空支路挑战

OA 数据显示：

- N 侧出现两套外观相似的梯形/桥接电容链；
- P 侧另有 `net22` 至 `net28` 等单端网络，涉及桥电容和中间 bit 支路；
- 这些现象可能是有意的差分拓扑、层次展开造成的别名、迁移残留，或实际悬空/重复连接。

目前证据不能在三者之间做选择。必须执行以下 gate：

1. 从当前 VM 产生带 instance path 的 Spectre schematic netlist。
2. 对 P/N 两侧逐 capacitor 建立端点表，标注 top plate、bottom plate、bridge、VCM、VREF、floating node。
3. 对每个 `net22...net28` 检查是否在网表中有第二端、是否被器件 body/寄生连接。
4. 对重复链路计算节点总电容和有效 bit weight，比较 P/N 相对误差。
5. 将结果与 schematic 图形和后续 layout connectivity 交叉确认。

在该 gate 通过前，任何“校准能够消除全部 CDAC 失配”的结论都只能限于本地行为模型，不能延伸到 VM 电路。

### 5.3 版图必须检查的模拟匹配项目

由于没有 SAR16B layout/GDS 证据，下列项目均为 GAP：

- CDAC 单元 common-centroid、交错/对称、dummy 和边缘环境；
- bridge capacitor 方向、周边寄生和 bottom-plate routing；
- P/N 两侧物理长度、层数、via 数和邻近数字线一致性；
- VCM 线的低阻抗、Kelvin/星形连接和 shield；
- VREFP/VREFN 独立供电、去耦、guard ring 和数字回流隔离；
- comparator input、preamp high-impedance node 的 shield 和时钟隔离；
- split-sampling sampling switch 的输入走线、bootstrapped control 和 charge-injection 对称性；
- `CLKAZ`、`READYN`、`SET` 和 `RSTT` 对模拟敏感节点的耦合；
- substrate/well isolation、deep-Nwell、guard ring、latch-up 防护；
- ESD/IO 保护器件与模拟输入电容、参考噪声的相互影响。

## 6. PDK、模型、角落和 Monte Carlo provenance

### 6.1 已发现的配置

当前 Maestro 配置记录：

- Spectre 23.1，Virtuoso IC6.1.8；
- 模型路径 `/home/meow/Desktop/TSMC18/tsmc18/../models/spectre/cmn018_assp_v1d2.scs`；
- 多个 TT section，包括 `tt_m`、`tt_3v`、`tt_mim`、`tt_fmom` 等；
- nominal 温度 27 C；
- transient noise enabled，`noisefmax=10G`，`noiseruns=100`，seed `1423525`。

### 6.2 Provenance 缺口

尚未形成可流片级的模型 provenance：

- 没有版本锁定的 PDK release/hash；
- 没有完整 SS/FF、低压/高压、温度、工艺 mismatch corner 矩阵；
- 没有明确区分 model section 与 process corner 的映射表；
- 没有 wafer-level capacitor mismatch、bridge mismatch、comparator offset/noise 的统计来源；
- 没有 post-layout extracted model 使用的 rule deck、PEX 版本和运行命令；
- 没有每个 corner 的 raw netlist、log、seed、结果 hash；
- `noiseruns=100` 只表明配置存在，不能表明 100 个 run 成功或被分析。

通过标准：所有 PVT/Monte Carlo 运行必须能由 manifest 唯一重现，记录 PDK hash、模型 section、温度、电源、输入、seed、run count、失败 run 和 raw PSF/CSV hash。

## 7. AMS、PEX、DRC/LVS、IR/EM 和 release gate

### 7.1 Gate 总表

| Gate | 必需证据 | 当前判定 | 通过标准 |
|---|---|---|---|
| G0 设计身份 | SAR16B top、PDK、版本、视图清单 | PASS/partial | top/library/config 唯一且版本锁定 |
| G1 原理图结构 | cross-library schematic/netlist | PARTIAL | 无 dangling/duplicate 未解释网络；P/N 拓扑闭合 |
| G2 normal conversion | 0-noise AMS，至少 512 个 EOC/code | FAIL/GAP | code mapping、EOC、VCM handoff、bit order 全通过 |
| G3 split sampling/VCM | 多周期波形和电荷/共模指标 | GAP | sample、hold、VCM、reset 窗口均有 margin |
| G4 comparator/Flash | offset/noise/metastability、Flash→SAR 时序 | GAP | decision polarity、ready、settling、边界码全通过 |
| G5 calibration PHY | foreground switching 实际控制 | FAIL/GAP | 与 normal path 同源，P/N、VCM、RSTT、READYN 全闭合 |
| G6 SRM | 22 次同 residue 判决和 residue code | FAIL/GAP | ones-count 分布、Q8 符号、时序绑定全通过 |
| G7 PDK/corners | TT/SS/FF/temp/VDD/MC manifest | GAP | 每 corner 有成功 log/raw output/hash |
| G8 layout matching | CDAC/comparator/reference/clock layout review | GAP | matching、shield、guard ring、dummy、隔离签字 |
| G9 DRC/ERC/antenna | 当前 SAR16B top 结果 | GAP | DRC/ERC/antenna 为 0 个 blocker，waiver 有批准 |
| G10 LVS | schematic/layout LVS report | GAP | top-level device/net match；所有 soft-connect 有解释 |
| G11 PEX | extracted netlist/SPEF/RC summary | GAP | PEX netlist hash 与 signoff top 一致 |
| G12 post-layout AMS | PEX + AMS + noise/MC | GAP | normal/calibration/SRM 全场景达标，有失败统计 |
| G13 IR/EM/power | power integrity、reference、clock、ESD | GAP | 电压/电流/电迁移/热约束有 margin |
| G14 density/fill/latch-up/ESD | full-chip physical signoff | GAP | density、fill、latch-up、ESD、seal-ring 全通过 |
| G15 GDS/OASIS release | stream-out、层映射、hash、manifest | GAP | 可读取、hash 固定、版本与 LVS/PEX 对齐 |
| G16 silicon test | ATE pattern、封装、校准、原始数据 | GAP | 可重复测试 16-bit code、SNDR/SFDR/INL/DNL，数据可追溯 |

### 7.2 现有 Maestro 证据的真实含义

当前 test 为：

```text
ADC_TOP_16b_5MS_SS_SRM_TEST:TEST_TRAN_ALL_TRANSISTOR_wFLash_ver6:1
```

配置包含 transient noise，但历史结果有 errors，且当前输出主要是 `P/N`、`VIN/VIP`、Flash、`BITP<20:0>`、VCM、比较器内部节点和功耗。没有：

- `adc_dout`；
- `data_valid`；
- calibration weight writeback；
- SRM ones count/residue；
- 16-bit code capture；
- FFT/INL/DNL 原始输入。

所以这组材料只能证明“曾经配置过一个 SAR16B transient test”，不能证明“当前模拟电路和维护 RTL 已完成 AMS 联调”。

## 8. 与 Huang 论文的联系、差异和证据距离

### 8.1 联系

本项目与论文相关的共同技术主线包括：

- 16-bit 目标与冗余 SAR decision；
- split-sampling/VCM 相关采样架构；
- 分段 CDAC 和低位参考段；
- 用 bit-weight calibration 处理静态 CDAC mismatch；
- P/N 测量减少 comparator/preamp offset 影响；
- 额外 noisy decisions 形成 SRM residue 统计修正；
- 数字端根据权重和 residue 进行最终重构。

### 8.2 主要差异

| 对象 | 论文/原算法层面 | 当前项目证据 | 距离 |
|---|---|---|---|
| 真实 CDAC | 论文具体 split-cap/physical implementation | VM 有 schematic，但权重尚未从当前网表/PEX提取 | 中等/高 |
| 采样和 VCM | 由模拟开关、电荷和时序共同实现 | VM 有时钟源和 SS cell，但未完成指标化验证 | 高 |
| 14 位权重测量 | 6-bit LSB reference 辅助高位测量 | RTL 有递归数字控制；没有物理 switching 闭环 | 高 |
| P/N offset cancel | 模拟测量序列与 comparator 行为共同决定 | RTL 有 P/N 数据通路，VM 未接入 | 高 |
| top-bit protection | 与模拟范围和共模路径相关 | RTL 有保护逻辑，未在 VM 验证 | 高 |
| SRM | 额外重复 noisy comparator observation | RTL 有 22-entry LUT，VM 无 22 次序列 | 高 |
| SNDR/SFDR | 完整 ADC 经过噪声、settling、参考、采样和失真 | 当前行为级结果部分关闭普通噪声，VM 结果有 errors | 很高 |
| 版图/PEX | 论文实现必须包含版图寄生影响 | SAR16B 无 GDS/PEX/signoff 证据 | 不可判定 |

### 8.3 不能直接声称的论文级结论

当前项目可以谨慎声称：

> 已建立一套与论文技术方向相符的数字算法基线，并在行为级物理 CDAC 代理模型上验证了静态权重校准、Q8 重构和 SRM 数字接口。

当前项目不能声称：

> 已完整复现论文芯片；
> 已在 SAR16B 晶体管电路中证明校准有效；
> 已完成 PEX、PVT、Monte Carlo、GDS signoff 或 silicon 性能复现。

## 9. 可能的 TCAS/JSSC 创新点

以下是**候选研究命题**，不是已确认的新颖性。是否可投稿取决于文献检索、完整电路实现、芯片数据和与已有工作的定量对照。

### 候选 1：VCM-aware asynchronous foreground calibration

核心命题：针对 split-sampling 的 VCM handoff 和异步 `READYN` SAR，设计一个与正常转换共享 CDAC switching path 的 foreground calibration sequencer，在校准期间显式控制 VCM、`RSTT`、AZ、settling 和 P/N polarity。

潜在贡献：

- 把“数字权重估计”提升为“VCM/charge-path-aware effective-weight estimation”；
- 量化校准 switching path 与 normal path 不一致时的残余误差；
- 用 async-ready handshake 替代固定数字等待，降低 PVT 下校准偏差。

必要证据：schematic/PEX/Spectre、PVT/MC、校准前后 INL/SNDR、与 Huang/既有 foreground calibration 的同条件对比。这个方向更接近 JSSC，但目前尚未实现。

### 候选 2：20-CDAC/21-decision code capture with explicit residue ownership

核心命题：将 20 个物理 CDAC decisions 与额外 residue decision 明确分离，通过异步 capture + CDC 将 `BITP<20:1>` 送入数字重构，同时保留 `BITP<0>` 作为 residue/EOC 证据。

潜在贡献：

- 解决 Flash/MSB、物理 CDAC 位和附加判决混在同一总线的工程问题；
- 形成对 split-sampling asynchronous SAR 可复用的 code ownership protocol；
- 为 SRM/校准共用同一笔转换建立原子绑定。

这是较明确的工程创新候选，适合 TCAS-I/II 级方法论文；但必须有完整 RTL、AMS 和 silicon/FPGA 实测证据，不能只提交接口草图。

### 候选 3：P/N recursive calibration with top-bit safe switching

核心命题：在分段桥接 CDAC 中，从可信 6-bit reference 段递归估计 14 个高位，并把 b18/b19 的 over-range/common-mode protection 纳入实际模拟切换时序，而不是仅在数字端做补偿。

潜在贡献：

- 物理安全约束和数字递归估计共同闭环；
- 对 top-bit protection 引起的测量偏差给出可计算补偿；
- 比简单 sine-fit calibration 更适合低功耗前台校准。

风险：论文技术主线已经包含 LSB-assisted calibration、P/N 测量和 top-bit protection 的相近思想。若没有新的 switching、复杂度、能耗、收敛或鲁棒性结果，单独宣称创新不足。

### 候选 4：SRM-assisted calibration-time/accuracy co-optimization

核心命题：不是只使用固定 22-entry residue LUT，而是联合优化 noisy decision count、LUT quantization、校准 averaging、comparator noise 和最终 reconstruction error。

潜在贡献：

- 给出“额外 SRM decision 数量 - calibration time - SNDR/SFDR”的设计曲线；
- 处理相关噪声、非理想 ones-count 分布和 finite-count bias；
- 使 SRM 的降噪收益与校准收敛时间在一个统一模型中可测量。

风险：需要证明算法不是普通重复采样加 LUT；需要与论文的 SRM 方案和其他 statistical residue 方法作严格 baseline。

### 候选 5：Tapeout-oriented digital/analog contract verification

核心命题：建立从 CDAC physical netlist、权重提取、RTL Q8 writeback、SRM residue、PEX 后 AMS 到 silicon code capture 的可追溯合同。

潜在贡献：

- 研究重点是 mixed-signal verification methodology，而不是单一电路技巧；
- 以 bit mapping、EOC、VCM phase、权重单位和 residue sign 为可机器检查的 contract；
- 适合 TCAS 工程方法/验证方向，但 JSSC 需要绑定明确电路或芯片性能提升。

### 9.1 创新等级建议

| 目标 | 当前最现实的主线 | 当前完成度 |
|---|---|---|
| TCAS-I/II 方法论文 | async code ownership + VCM-aware calibration contract | 概念成立，实验不足 |
| JSSC 电路论文 | 共享 switching path 的 VCM-aware foreground calibration + SRM | 尚未实现，缺芯片数据 |
| 复现/工程报告 | 论文算法边界、RTL、行为模型和失败证据闭合 | 已有基础，需补 AMS 真实证据 |

## 10. 必须补齐的工程实施顺序

### Phase 0：冻结设计身份

- 冻结 `SAR_16B_5M_TB/TEST_TRAN_ALL_TRANSISTOR_wFLash_ver6` 为唯一 top。
- 导出 config、schematic netlist、HDL、model manifest 和版本 hash。
- 说明 `sar_reconstruction` 是使用、替代还是删除；禁止保留 `nlAction=ignore` 的含糊状态。

### Phase 1：修复模拟接口合同

- 实现 `BITP<20:1>` 原子 capture。
- 从 `SET<20>/READYN` 建立 EOC，不再使用 `BITP<20>` 作为 valid。
- 引入自由运行数字时钟和 CDC。
- 定义 `BITP<0>` 的 residue/EOC 角色。
- 对 `rst_n`、权重写口和输出建立可观察端口。

### Phase 2：核实 CDAC

- 生成当前 Spectre netlist。
- 解释 N 侧重复链和 P 侧 `net22...net28`。
- 从端点表推导 nominal effective weights。
- 建立 P/N mismatch、bridge/parasitic、VCM 和 switch resistance 模型。

### Phase 3：实现 calibration PHY 和 mode arbiter

- normal / calibration / SRM 三态互斥。
- 共享真实 CDAC driver 和 comparator path。
- 用 `READYN`/settle acknowledgment 替换固定等待。
- 逐 bit 记录 measured P/N、average、writeback、失败/超时原因。

### Phase 4：实现真实 SRM

- 明确 22 次 decision 是否由电路产生。
- 若不能，重新生成实际 decision-count LUT。
- 验证同一 residue、decision independence、polarity、Q8 sign 和 code binding。

### Phase 5：AMS 验证

- 0-noise ideal：normal conversion 至少 512 个 code，理想 16-bit SNDR 约 98 dB 量级。
- mismatch only：normal conversion，比较 nominal/oracle/calibrated。
- VCM/sampling/settling/charge injection。
- comparator offset/noise/metastability。
- SRM on/off、校准前后、full-scale/back-off、多频点。
- 每个 corner 和 MC run 保存 raw PSF/CSV、log、seed、config hash。

### Phase 6：layout/signoff

- CDAC/comparator/reference/clock layout review。
- DRC/ERC/antenna/latch-up/ESD/density/fill。
- LVS；然后 PEX；再跑 post-layout AMS。
- IR/EM、reference droop、clock integrity、substrate noise。
- 生成 GDS/OASIS、layer map、stream-out log、top hash 和 release manifest。

### Phase 7：silicon test

- 封装、板级电源、参考、时钟、输入幅度/共模。
- 校准模式寄存器和校准完成判据。
- 512/8192/更长 code capture；FFT、INL、DNL、missing code、SFDR、SNDR、ENOB。
- PVT、芯片间统计、校准时间、功耗、失败率和 raw data lineage。

## 11. 最终判定

### 可以确认

1. 当前 RTL 的 `sar_calib_ctrl_serial`、`sar_reconstruction`、`srm_residue_estimator` 在数字算法层有清晰职责和既有单元级验证基础。
2. VM `SAR_16B_5M` 的 20 路 CDAC、分段/桥接结构、Flash + 异步 SAR 链和 6 位低位参考思路，与该数字算法方向存在真实架构联系。
3. 本地物理 CDAC 行为模型足以作为后续算法对照起点，但不是 VM PDK/PEX 模型。

### 不能确认

1. 当前 RTL 能否不经适配直接用于 VM：不能。
2. 当前校准能否已经在 VM transistor-level CDAC 上消除失配：没有证据。
3. 当前 SRM 是否与 VM 模拟电路闭合：没有证据，且当前判决数量不匹配。
4. SAR16B 是否完成 layout/GDS/DRC/LVS/PEX/IR-EM signoff：不能确认，现状按 GAP 处理。
5. 是否可 tapeout：不能。至少 P0-1 至 P0-6 和 G8-G15 必须关闭。
6. 是否具备论文创新性：有候选方向，但必须补充真正的物理实现、定量 baseline 和 silicon/后仿真证据。

**Reviewer 2 的最终建议：暂缓 tapeout signoff。先修复 code capture/CDC、CDAC 网表异常和 calibration PHY，再建立 512 点无噪声 normal conversion 与 PEX 后 AMS 闭环；在此之前，项目应被标记为“architecture-compatible digital/AMS prototype”，而不是“tapeout-ready SAR16B”。**

## 12. 审查输入索引

- [VM SAR16B 兼容性报告](../../vm_sar16b_compatibility_20260830/SAR16B_RTL_COMPATIBILITY_REPORT_CN.md)
- [VM 层次 checkpoint](../../vm_sar16b_compatibility_20260830/checkpoint_sar16b_hierarchy.json)
- [VM 完整参数 checkpoint](../../vm_sar16b_compatibility_20260830/checkpoint_sar16b_full_params.json)
- [VM Maestro checkpoint](../../vm_sar16b_compatibility_20260830/checkpoint_sar16b_maestro.json)
- [VM 历史日志 checkpoint](../../vm_sar16b_compatibility_20260830/checkpoint_sar16b_history_logs.json)
- [VM 库与仿真树 checkpoint](../../vm_sar16b_compatibility_20260830/checkpoint_sar16b_series.json)
- [当前 RTL 验证说明](../../../docs/VERIFICATION.md)
- [物理 CDAC 再验证说明](../../physical_cdac_mismatch_20260729/VALIDATION_REPORT_CN.md)
- [当前物理 CDAC 模型](../../physical_cdac_mismatch_20260729/physical_cdac.py)
