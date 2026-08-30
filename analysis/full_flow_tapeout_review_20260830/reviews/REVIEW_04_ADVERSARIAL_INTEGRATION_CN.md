# REVIEW_04：跨域对抗性集成审查

**角色**：Independent Reviewer 4，cross-domain adversarial reviewer
**日期**：2026-08-30
**工作目录**：`D:/ReedZhao/Document/ADC_Digital_PROCESS/proc_vivado/sar_adc_v3`
**目的**：专门寻找 REVIEW_01、REVIEW_02、REVIEW_03 的共同遗漏、证据误用、结论过度和互相矛盾。
**写入边界**：本文件是本轮唯一新增/编辑文件；未修改 RTL、TB、VM、物理资产或其他报告。

## 1. 结论先行

当前最准确的工程标签是：**四个 RTL 单元 TB 已通过、四个数字模块可在指定 Artix-7 条件下综合，但 VM/AMS 顶层尚未形成可验证的数字闭环，且不存在可支持 tapeout 的 SAR16B 物理交付物。**

本轮采用的新增事实为：

- 四个 XSIM TB 均 PASS；
- `sar_reconstruction`、`srm_residue_estimator`、`sar_calib_ctrl_serial` 和 `sar_adc_digital_top` 在 Vivado 2018.3、`xc7a35t`、仅 `10 ns` 内部时钟假设下综合 PASS；
- 集成顶层报告为 WNS `+3.957 ns`、`1520` LUT、`1661` registers；
- Verilator 当前不可用，因此不存在可据此宣称 PASS 的独立 lint 证据；
- OA layout 证据确实存在一个 layout view，但仅含 `9` 个 PDK 实例、`0` 个 shape；物理资产清单在声明的四个 SAR16B 根目录下未发现 GDS、DRC、LVS、PEX 或其他 signoff named file。

**最终 gate**：`sar_adc_digital_top` 综合 PASS 不是 ASIC netlist signoff；OA layout view 存在不是版图完成；行为级 512-chip 不是 AMS/硅片统计；文献关系分析不是新颖性检索结论。当前 tapeout recommendation：**HOLD**。

## 2. 审查输入与证据规则

已读取并交叉使用：

1. `analysis/full_flow_tapeout_review_20260830/reviews/REVIEW_01_RTL_TO_NETLIST_CN.md`
2. `analysis/full_flow_tapeout_review_20260830/reviews/REVIEW_02_AMS_LAYOUT_GDS_CN.md`
3. `analysis/full_flow_tapeout_review_20260830/reviews/REVIEW_03_SILICON_PAPER_NOVELTY_CN.md`
4. `analysis/full_flow_tapeout_review_20260830/evidence/vm_sar16b_layout_summary.json`
5. `analysis/full_flow_tapeout_review_20260830/evidence/vm_sar16b_physical_asset_inventory.json`
6. `analysis/vm_sar16b_compatibility_20260830/SAR16B_RTL_COMPATIBILITY_REPORT_CN.md`
7. 当前 `rtl/*.sv`，以及 `delivery/sar_adc_v3_digital_core_2026-05-18/tb/*.sv` 四个关键 TB。

证据等级沿用以下边界：E1 为 RTL/TB/综合，E2 为行为级模型，E3 为可复查的晶体管/AMS 仿真，E4 为 PEX/DRC/LVS/STA/IR/EM/GDS，E5 为可追溯硅片/ATE。结论只能停留在产生它的最低证据等级，不能因多个 E1 结果叠加而自动升为 E3-E5。

**文献限制**：以下仅按用户指定的 Huang 2025、Bagheri 2020、Chen 2024 的已知覆盖关系做反证框架；没有声称完成新的系统性新颖性检索，也没有给出 patent novelty 或 first-of-kind 结论。

## 3. 总体判定表

| 事项 | 判定 | 优先级 | 责任域 | 可验证关闭条件 |
|---|---|---:|---|---|
| 四个 XSIM TB 在其声明范围内通过 | VERIFIED | P2 | RTL/验证 | 保存同一 commit、Vivado 版本、命令、log/hash；不得外推到 VM |
| 四模块 Vivado 综合通过 | VERIFIED | P2 | RTL/FPGA flow | 固化顶层、part、脚本、约束和 utilization/timing report；仍标为 FPGA-only |
| `+3.957 ns` WNS 是完整时序签核 | PARTIAL | P1 | FPGA/STA | functional/scan/calibration/SRM SDC、IO delay、generated clock、recovery/removal、zero unconstrained endpoints |
| `1520 LUT/1661 registers` 是稳定可复用资源结论 | PARTIAL | P2 | FPGA flow | 用唯一 run manifest 绑定源文件、Tcl、Vivado、part；解释旧文档 `1518/1661` 差异 |
| Verilator/独立 lint 已通过 | GAP | P2 | RTL/CI | 恢复 Verilator 或批准替代 lint，保存 `-Wall` log 和 waiver；当前不可用不能算 PASS |
| VM 当前 RTL 已集成 | CONTRADICTED | P0 | AMS/数字集成 | I94 使用当前 SV view、`nlAction` 不再 ignore；端口、reset、writeback、输出均闭环并有 AMS netlist |
| `raw_bits` 使用 `BITP<19:0>` 合法 | CONTRADICTED | P0 | AMS/接口 | 明确 `raw_bits[19:0]=BITP[20:1]`，并用 ramp/边界码/极性测试证明 |
| `BITP<20>` 可作为 data valid | CONTRADICTED | P0 | AMS/接口 | 独立 EOC/READYN capture，`BITP<20>` 只作为 CDAC MSB |
| 数字 reconstruction 已覆盖顶层集成 | GAP | P1 | RTL/验证 | 增加 top-level TB，覆盖 capture、calibration write、SRM、reset、连续 conversion 的组合行为 |
| SRM 22 个样本已由 VM 产生 | GAP | P1 | AMS/SRM | 同一 residue hold 下 22 次 evaluate，`start/valid/done/residue` 和 raw code 绑定 |
| OA layout 是可流片版图 | CONTRADICTED | P0 | VM/版图 | 当前 view 有非零 geometry、top-level net/instance 完整、stream-out GDS 可读且 hash 固定 |
| SAR16B DRC/LVS/PEX/GDS signoff 存在 | GAP | P0 | 物理实现 | 当前 SAR16B top 的 DRC/LVS/PEX/STA/IR/EM/antenna/ERC 及 release manifest 全部可复查 |
| 30 us 已提供 150 个有效 ADC 输出 | PARTIAL | P1 | AMS/验证 | 先定义 EOC/data_valid，再运行 `>512` 个有效输出并保存 raw PSF/code；30 us 只能给出约 150 个 200 ns 周期上限 |
| 当前项目可称为完整 16-bit ADC 验证 | PARTIAL | P1 | 系统验证 | 无噪声、SRM-off、校准前后、真实 EOC 的 512/8192 点闭环，并有明确输出码域/饱和合同 |
| TCAS/JSSC 新颖性已成立 | GAP | P1 | 论文/架构 | 新数学或新电路先实现，再以同条件 baseline、AMS/PEX 和硅片数据证明技术效果；不以本报告宣称新颖性 |

## 4. 第一遍：claim-vs-evidence

这一遍只问：**报告中的句子，是否被同一范围、同一对象、同一运行的证据直接支持？**

### 4.1 被正确支持的主张

| 主张 | 判定 | 优先级 | 责任域 | 依据与可验证关闭条件 |
|---|---|---:|---|---|
| 四个 TB PASS | VERIFIED | P2 | RTL/验证 | `tb_sar_recon_binary_norm` 49、`tb_recon_q8_split_weights` 17、`tb_srm_residue_estimator` 17、`tb_gain_comp_check_lsb` 10 checks，均为 0 failed。关闭条件是保存同一 commit、版本、命令和 log/hash；仅限各自 DUT 数字合同。 |
| 三核心加 `sar_adc_digital_top` 综合 PASS | VERIFIED | P2 | RTL/FPGA flow | 兼容性报告记录 0 errors、0 critical warnings、3 warnings；目标为 `xc7a35t`。关闭/维护条件是固定顶层、part、Tcl、输入 hash 和 report；仍不得升为 ASIC 证据。 |
| 内部 100 MHz WNS 为正 | PARTIAL | P1 | FPGA/STA | `+3.957 ns` 与 10 ns clock 一致，但 XDC 只有 `create_clock`，且 27 个 input、71 个 output 未有 IO delay。关闭条件是完整 ASIC/MMMC SDC 和 zero unconstrained endpoints。 |
| 行为级 512-chip 活动存在 | VERIFIED | P2 | 行为建模/验证 | 可作为 E2 活动证据；关闭条件是把 mismatch、noise、settling、headroom 假设和 seed 固化，并明确不能称 PDK MC、PEX 或 silicon yield。 |

### 4.2 共同遗漏或需要降级的主张

| 发现 | 判定 | 优先级 | 责任域 | 对抗性结论与关闭条件 |
|---|---|---:|---|---|
| “数字算法基线较完整”被读成“ADC 系统已验证” | PARTIAL | P1 | RTL/系统验证 | 四个 TB 没有实例化 `sar_adc_digital_top`，也没有驱动 VM 的 `BITP/READYN/SET`。关闭条件是 top-level TB + 真实 capture/EOC/SRM/calibration 组合闭环。 |
| `0.4937 LSB` 被用来支持真实校准精度 | PARTIAL | P1 | 校准/AMS 验证 | comparator 是行为 stub，`MC_RUNS=5`、offset=5 LSB、noise=0.5 LSB、32 averages。关闭条件是 PVT/AMS/PEX 或硅片同口径 residual 与失败统计。 |
| `22-decision` 被用来支持 VM SRM | GAP | P1 | AMS/SRM | TB 人为提供 22 个同步 valid；VM 正常链只有 21 个锁存结果。关闭条件是同一 residue hold 的 22 次物理 evaluate 或按真实次数重建 LUT。 |
| `30 us` 等于 150 个有效转换 | PARTIAL | P1 | AMS/验证 | 只是约 150 个名义周期上限，不是 `data_valid` 计数；关闭条件是定义 EOC 后保存超过 512 个有效 code/PSF。 |
| “未找到 SAR16B layout cell” | CONTRADICTED | P0 | VM/版图 | 与 JSON 冲突：指定 layout view 明确存在且有 9 个实例。关闭条件是改写为“空几何/非 signoff layout view”，并保留 evidence hash。 |
| “layout 存在”被等同于版图完成 | CONTRADICTED | P0 | VM/版图 | JSON 的 `shape_count=0`、`shape_type_counts={}`；bbox 由实例 bbox 形成。关闭条件是非零 geometry、top net/instance closure 和 stream-out GDS。 |
| “全 VM/全文件系统无 GDS” | PARTIAL | P1 | 物理资产审计 | 清单只覆盖四个声明根目录，不能证明其他路径不存在。关闭条件是明确扫描边界，或提供全 VM manifest；当前只能说 roots 内未发现。 |
| `1518 LUT/1661 registers` 与本轮 `1520/1661` 同时作为当前结果 | CONTRADICTED | P2 | FPGA flow/报告 | 1518 是旧记录，当前 run 为 1520。关闭条件是按 run 绑定 commit、Tcl、tool、part、report/hash，不能发布单一无 provenance 数字。 |
| Verilator 入口存在等于 lint 通过 | GAP | P2 | RTL/CI | 本轮 Verilator 不可用，没有 lint transcript。关闭条件是恢复 Verilator 或批准替代 lint，保存 `-Wall` log 和 waiver。 |

### 4.3 对前三份报告的一致性纠偏

前三份报告在“当前不能 tapeout”这一总方向上相互支持，但有三处措辞需要收紧：

1. REVIEW_01 将 GDS/PEX/DRC/LVS 写为 `NOT_CHECKED`，在本轮新增 OA/资产证据后应改成：**layout view 已检查但为空几何；SAR16B signoff artifacts 为 GAP**。
2. REVIEW_02/03 将“没有 layout”写得过宽；应区分 **layout view、可绘制几何、stream-out GDS、签核报告** 四层。
3. REVIEW_03 将 `Verilator/一致性脚本入口存在`写成“部分通过”太乐观；Verilator 不可用时只应保留 `GAP`，一致性脚本即使通过也不能代替 lint。

## 5. 第二遍：接口、时序、算法一致性

这一遍不采信报告结论，只从当前 RTL、TB 和兼容性证据重新追踪信号语义。

### 5.1 P0/P1 集成发现

| 发现 | 判定 | 优先级/责任域 | 可验证关闭条件 |
|---|---|---|---|
| raw code 位序错误 | CONTRADICTED | P0，AMS/数字接口 | 对当前 VM 的真实连接逐端点证明：`raw_bits[19:0]=BITP[20:1]`；`BITP[0]` 单独保存，不能进入 20-bit CDAC weighted sum。 |
| valid 语义错误 | CONTRADICTED | P0，AMS/数字接口 | 独立 `async_eoc` 由 `READYN/SET<20>` 定义并经 capture/CDC；禁止用 Flash/CDAC MSB 作为 valid。 |
| `I94.clk` 采用异步 SAR activity | GAP | P0，AMS/CDC | 独立 `dig_clk` 驱动 reconstruction；异步事件使用 pulse/toggle/handshake synchronizer，并以 late/early/metastability/timeout tests 关闭。 |
| 当前 VM I94 被 `nlAction=ignore` 且总线悬空 | CONTRADICTED | P0，AMS netlisting | 当前版本 SV view/symbol/config 被 netlisted；`rst_n`、`w_wr_*`、`srm_*`、`adc_dout`、`data_valid_out` 均有可观察连接，netlist 无 ignored digital instance。 |
| `sar_adc_digital_top` 只是组合骨架 | VERIFIED | P1，RTL 集成 | `rtl/sar_adc_digital_top.sv` 自身注释和结构都说明未实现 full SAR controller、mode arbitration；需要 top-level functional TB，不得因综合成功提升为集成完成。 |
| SRM residue 没有 transaction pairing | GAP | P1，RTL/SRM | 当前 top 将 `srm_residue_q` 直接连到 reconstruction；应增加 residue-valid/tag 或明确 SRM-off 值，并断言 raw code、EOC、22 decisions、residue 属于同一 transaction。 |
| SRM 数量和物理序列不一致 | GAP | P1，AMS/SRM | `srm_residue_estimator` 的 22 次输入必须来自 DAC 不更新的同一 residue；若 VM 只能生成其他次数，按真实次数和 sigma 重新推导 LUT，而不是只改参数。 |
| calibration PHY 缺失 | GAP | P0，AMS/模拟控制 | 将 `dac_p_force/dac_n_force` 映射到真实 `BITP/BITN/SET/RSTT/VCM/CLKAZ/READYN`，定义三态、互补、settled、timeout 和安全回 VCM。 |
| normal/calibration/SRM ownership 未定义 | GAP | P0，AMS/数字集成 | mode arbiter 给模拟开关唯一 owner；证明 back-to-back conversion、calibration collision、SRM overlap 时没有多源驱动。 |
| calibration 完成语义过窄 | PARTIAL | P1，RTL/AMS | 当前 `calib_done` 只代表数字 FSM 状态；改为同时包含 analog-safe、writeback-complete、CRC/readback 和 CDC acknowledgement，或明确拆分这些状态。 |
| weight RAM readiness 未闭合 | GAP | P1，RTL/ATE | reset 后 bit 6..19 为零，必须有 `weights_ready`/normal-conversion inhibit、上电装载方案和 readback；证明校准未完成时不会输出伪有效码。 |
| rounding/负数合同未闭合 | PARTIAL | P2，RTL/算法 | TB 当前与实现的 `+0.5`/算术右移一致，但需冻结 negative rounding、full-scale saturation、gain normalization 的数学定义并覆盖边界向量。 |

### 5.2 TB 反证

四个 TB 的 PASS 不能关闭以下缺口：

| TB 反证项 | 判定 | 优先级 | 责任域 | 可验证关闭条件 |
|---|---|---:|---|---|
| reconstruction TB 将 `data_valid_in` 作为同步单周期脉冲 | GAP | P0 | RTL/CDC | 增加异步 EOC、BITP 原子捕获、跨域撕裂和 late/early event test。 |
| SRM TB 直接同步送 22 个决策 | GAP | P1 | AMS/SRM | 覆盖 sparse valid、start while busy、额外决策、residue hold 和 DAC 不更新。 |
| calibration TB 使用 real-valued comparator stub | PARTIAL | P0 | AMS/校准 PHY | 接入 `VCM/SET/RSTT/CLKAZ/READYN` 模型，加入 settling、PVT、ownership 和 timeout。 |
| 全部 TB 缺少 X/Z、reset mid-transaction、write collision、SRM-off、512 valid code | GAP | P1 | RTL/系统验证 | 增加 assertions、reset/碰撞/连续 EOC 回归和 512/8192 有效样本 scoreboard。 |

## 6. 第三遍：tapeout 与 silicon-test gate

这一遍只问：**即使 RTL 算法正确，是否已经有能交付给 foundry、ATE 和审稿人的闭环证据？**

| Gate | 判定 | 证据判读 | 责任域 | 关闭条件 |
|---|---|---|---|---|
| OA layout view 存在 | VERIFIED | 证据 JSON 的 layout view 有 9 个 PDK instances | VM/版图 | 仅说明 OA 对象可读，不等于几何或 signoff |
| OA layout geometry 完成 | CONTRADICTED | `shape_count=0`、无 shape type/layer counts | VM/版图 | 产生真实 geometry，检查 top cell、层、pin、instance connectivity |
| SAR16B GDS/OASIS | GAP | physical inventory 的 `stream_out=[]` | 物理实现 | current SAR16B top 的 GDS/OASIS、stream-out log、layer map、hash |
| SAR16B DRC/LVS/PEX | GAP | `signoff_named_file=[]`、`extracted_or_timing=[]`；不能推断其他路径 | 物理 signoff | DRC/ERC/antenna、LVS、PEX/SPEF 和报告均指向同一 netlist/top/hash |
| analog matching/IR/EM/ESD | GAP | 0 shape 不能检查 common-centroid、dummy、shield、guard、reference routing 或电源完整性 | 模拟版图/物理 signoff | PEX 后关键网波形、IR/EM/ESD/latch-up/density/fill 通过 |
| ASIC synthesis/STA | GAP | 当前仅 Artix-7 FPGA 综合；`+3.957 ns` 不覆盖 ASIC library | ASIC 前端/STA | target library、multi-mode multi-corner SDC、zero unconstrained、slew/load/recovery/removal clean |
| CDC/RDC/reset/power | GAP | 文字 timing contract 不是工具 signoff；无 UPF/CPF/level-shifter 报告 | RTL/ASIC signoff | CDC/RDC report、waiver、reset release、power intent 和多电压 crossing clean |
| LEC/GLS/SDF | GAP | 无 final gate netlist、LEC、SDF 或 min/typ/max GLS | ASIC 验证 | RTL-to-gate equivalence PASS，GLS 覆盖 async EOC、reset、writeback、SRM、back-to-back |
| DFT/ATE observability | GAP | 无 scan/ATPG/MBIST、raw code、weight CRC/readback、mode pin contract | DFT/测试 | test-mode、coverage、patterns、weight persistence、raw BITP/EOC 可观测并有 log |
| AMS normal conversion | GAP | Maestro 既有 history 有 errors；当前 output 无 `adc_dout/data_valid` | AMS 验证 | 修正 netlist 后 0-noise、PVT/MC、至少 512 valid EOC/code，保存 PSF/netlist/hash |
| AMS calibration | GAP | 数字校准 stub 未控制真实 switch/VCM/READYN | AMS/校准 PHY | P/N、VCM、AZ、settling、timeout、mode ownership 在 schematic/PEX AMS 通过 |
| AMS SRM | GAP | 没有 22 次同 residue 的真实 sequence | AMS/SRM | 22 samples、ones-count、sigma 标定、same-residue trace、SRM-on/off 对照 |
| silicon/ATE | GAP | 无 wafer、package、ATE、raw waveform、die-level lineage | 测试/硅片 | wafer/lot/die/package/board ID 到 raw data、parser、统计和 signed report 全链路 |

### 6.1 P0/P1/P2 归责清单

**P0：不关闭就不能称 VM 集成。**

1. `BITP<20:1>` capture、独立 EOC、异步到同步 CDC；责任域：AMS/数字接口。
2. I94 旧 view、`nlAction=ignore`、悬空 reset/write/output；责任域：Cadence netlisting/集成。
3. calibration PHY 和 normal/calibration/SRM 唯一 ownership；责任域：模拟控制/数字集成。
4. CDAC OA 异常支路必须由当前 schematic Spectre netlist 逐端点解释；责任域：模拟设计/版图。
5. 产生可读的 SAR16B geometry/GDS，并开始 DRC/LVS gate；责任域：版图/物理实现。

**P1：不关闭就不能称 gate-level、系统性能或可投稿实验闭环。**

1. 顶层功能 TB、weights-ready、stale residue、transaction tag、reset/timeout/XZ；责任域：RTL/验证。
2. 真实 22-decision residue-hold sequence，或重建符合真实 decision count 的 estimator；责任域：AMS/SRM/算法。
3. ASIC SDC/STA、CDC/RDC、LEC、GLS/SDF、DFT/power intent；责任域：ASIC signoff。
4. 0-noise/SRM-off/校准前后至少 512 valid conversions，再做 noise/MC/PEX；责任域：AMS 验证。
5. 输出码域、saturation、full-scale/headroom 和 calibration persistence 合同；责任域：算法/系统/测试。

**P2：不关闭不一定阻断功能，但会阻断可复现发布。**

1. 资源数字 `1518` 与 `1520` 的 run provenance；责任域：FPGA flow。
2. Verilator 不可用时的独立 lint 替代证据；责任域：RTL/CI。
3. 历史总 checks `93` 与当前 `49+17+17+10=100` 的文档一致性；责任域：验证报告。
4. 把参数 guard、Q8 LUT 和 5-seed calibration 明确写成 qualified configuration，而不是通用 IP/yield 证明；责任域：论文/维护。

## 7. TCAS-II / TCAS-I / JSSC 候选的反证

下表不是新颖性结论，只是把候选主张放回已知覆盖和所需证据中。

| 候选主张 | 反证：更像什么/已被谁覆盖 | 当前判定 | 优先级 | 责任域 | 若仍要成立，最低新增证据 |
|---|---|---|---:|---|---|
| 20 路 split CDAC、6-bit reference、P/N 校准、22-decision SRM | Huang 2025 已覆盖该主架构、SS、22 次 SRM、6-bit reference 测高位、P/N/冗余校准和硅片结果；当前只是数字边界复现 | CONTRADICTED | P1 | 论文/架构 | 提出新的电路或统计机制，并做同条件面积、能耗、时间、SNDR/INL/DNL 对比和 silicon。 |
| 递归 bit-weight calibration + stochastic/noisy decision | Bagheri 2020 已覆盖确定性自校准与 stochastic quantization 的 mismatch calibration 思路；“多次 noisy decision + 数字校正”本身不能作为新点 | PARTIAL | P1 | 算法/校准 | 需要不同观测模型、收敛/误差界、资源复杂度或与 Bagheri 的严格 ablation；再有 AMS/硅片证明。 |
| 双段/分段权重测量、误差补偿 | Chen 2024 的 dual-segmental bit-weight self-calibration 与误差分析已覆盖分段权重校准的核心方向；当前 `6+4+5+5` 行为模型没有证明数学或电路机制不同 | PARTIAL | P1 | 算法/模拟 | 明确新的分段可观测性/误差传播定理、不同 reference reuse 或实质新 switching network；给出 transistor/PEX 及 silicon error histogram。 |
| async `READYN/SET` 到同步 reconstruction 的 code-capture/CDC | 可能是工程方法贡献，但同步器、接口合同、脚本和 mode arbiter 单独通常是工程集成，不自动成为 TCAS-I/JSSC 电路创新 | PARTIAL | P1 | CDC/数字集成 | 形式化无丢码/不混码/固定 latency 证明；metastability/EOC margin 数学界；面积功耗 latency 与直接连线 baseline；AMS/GLS/连续 5 MS/s 实测。 |
| calibration、SRM、full-scale headroom 联合优化 | 目前 headroom guard 还是 analysis-only，且 scalar gain correction 会被视为常规校正 | GAP | P1 | 算法/系统 | 新联合优化目标、overflow/INL/SRM MSE 证明、bit-exact RTL、PVT/MC/PEX、full-scale silicon ablation。 |
| 低复杂度 SRM LUT/erfinv 实现 | 固定 22-entry inverse-normal LUT 已是实现细节；Huang 已有 22-decision SRM，离线 LUT 不够新 | GAP | P1 | 算法/RTL | 新 estimator（相关噪声、有限样本置信度、adaptive N 或 Bayesian/MLE tradeoff）的数学、ASIC area/power/latency 和 silicon。 |
| 512-chip behavioral campaign、CI、parameter guards、Q8 pipeline | 这是工程验证/可复现性贡献，不能单独支撑 JSSC 电路新颖性 | VERIFIED | P2 | 工程验证/论文 | 若投 TCAS 工程方法，需把合同、失败分类、自动化复现和实测收益形成可重复方法；不能包装为电路 first。 |

### 7.1 分刊物结论

- **TCAS-II**：最有机会的是“真实异步 SAR 的可验证接口/transaction ownership”或“带误差界的联合 estimator”，但当前只处于候选阶段。必须先有完整实现和 quantitative baseline。
- **TCAS-I**：需要比接口包装更强的算法或电路机制，尤其要处理 decision correlation、finite-sample bias、full-scale/headroom 或 calibration energy/latency，并用 ASIC/AMS 数据闭合。
- **JSSC**：当前“另一款 16-bit、5 MS/s、SS+SRM SAR ADC”会直接撞上 Huang 2025 的主架构和硅片结果。必须新增可辨认的模拟电路、参考/VCM/校准 PHY 或系统协同贡献，并提供 post-layout 和 silicon 结果。现有 RTL、Vivado slack、26-entry LUT、5-run MC、512 virtual chips 都不够。

## 8. 推荐的停止线和交付顺序

1. 冻结 source-of-truth、VM cell/view、bit order、EOC、SRM count、权重单位和 run manifest。
2. 先用当前 Spectre schematic netlist 解释 CDAC `net22...net28`、N 侧重复链和所有 dangling/soft-connect。
3. 设计 `async_eoc/code_capture_adapter`、独立 `dig_clk`、reset synchronizer、mode arbiter 和 transaction tag。
4. 接入当前 `sar_reconstruction`/calibration/SRM view，禁止 `nlAction=ignore`，做 top-level RTL+AMS smoke。
5. 先跑 0-noise、SRM-off、至少 512 个**有效 EOC**；确认码位、极性、饱和和权重 readback，再打开 calibration 和 SRM。
6. 对 calibration PHY、VCM/AZ/settling、SRM same-residue sequence 做 PVT/MC/PEX AMS，并把失败 run 原始结果固定下来。
7. 完成 GDS/DRC/LVS/PEX/IR/EM/DFT/STA/GLS/SDF 和 release checksum；最后才讨论 tapeout。
8. 论文中把现有工作写成“qualified digital-boundary implementation/behavioral validation”，删除 `complete ADC`、`near-Pareto`、`realistic noise`、`yield`、`novel/first` 等越界词，除非后续证据真正关闭。

## 9. 最重要的五个纠偏点

1. **空 layout 不是版图完成**：OA view 存在，但 `9 instances / 0 shapes`；不能把对象存在升级为 GDS、DRC/LVS 或 tapeout readiness。
2. **四个 XSIM PASS 不是顶层 PASS**：TB 只覆盖三个算法模块的同步数字合同，没有 VM `BITP<20:1>`、独立 EOC、异步 CDC、ownership 或真实 SRM。
3. **WNS 只属于 FPGA 内部 10 ns 假设**：`+3.957 ns`、`1520/1661` 不代表 ASIC STA；而 `1518/1661` 的旧文档值必须按 run provenance 处理。
4. **当前接口存在确定性 P0 错误**：`BITP<19:0>` 应改为物理 CDAC 的 `BITP<20:1>`，`BITP<20>` 不能兼任 valid；I94 还被 ignore 且总线未闭环。
5. **创新主张必须降级**：Huang 2025 已覆盖 SS/SRM/reference/P-N 主架构，Bagheri 2020 覆盖 deterministic self-calibration + stochastic quantization 方向，Chen 2024 覆盖 dual-segmental bit-weight calibration/error-analysis 方向；当前可保留的是工程集成候选，尚无新数学、新电路或硅片证据支撑 TCAS/JSSC 新颖性。

## 10. 最终处置

**综合状态**：

```text
RTL unit contract             VERIFIED (限定于四个 TB)
FPGA synthesis                VERIFIED (xc7a35t, 10 ns internal clock)
FPGA/ASIC timing signoff     PARTIAL / GAP
VM code capture               CONTRADICTED / P0
VM digital netlist closure    CONTRADICTED / P0
Calibration PHY               GAP / P0
SRM physical sequence         GAP / P1
SAR16B layout geometry        CONTRADICTED (0 shapes)
SAR16B GDS/DRC/LVS/PEX        GAP / P0
Silicon/ATE                   GAP / P1
Novelty claim                 GAP; no novelty search claimed
Tapeout                       HOLD
```

在 P0 接口、真实 calibration PHY、SRM transaction、SAR16B physical signoff 和可追溯 silicon-test gate 关闭前，不能把当前项目称为“已流片集成的 16-bit SAR ADC”，也不能把行为级指标或 Huang 的硅片指标写成本项目实测结果。
