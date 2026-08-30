# SAR_16B 从 RTL 到 GDS、流片与硅后测试全流程独立审查总报告

## 文档控制

| 项目 | 内容 |
|---|---|
| 审查日期 | 2026-08-30 |
| 仓库 | `D:/ReedZhao/Document/ADC_Digital_PROCESS/proc_vivado/sar_adc_v3` |
| 审查基线 | Git `a2ee34e7bdfa7ded19379c66962165a2f7e30db4`，分支 `main` |
| VM 范围 | `/home/meow/IC/SAR_16B_5M_CORE`、`SAR_16B_5M_EXP`、`SAR_16B_5M_TB` 及对应 simulation 目录 |
| 论文基准 | Huang 2024 thesis Chapter 4；Huang et al. JSSC 2025 |
| 审查轮次 | 4 个独立 reviewer，且每份报告内部含 3 至 4 个重新取证 pass |
| 状态词 | `VERIFIED`、`PARTIAL`、`GAP`、`CONTRADICTED`、`NOT_CHECKED` |

## 1. 执行结论

### 1.1 一句话结论

当前仓库已经形成可综合、单元测试通过的 **Q8 加权重构、P/N 递归前景校准和 22-decision SRM 数字算法核**，并有 512-chip 物理代理行为实验；但它尚不是可直接接入 VM `SAR_16B_5M` 的完整 ADC digital top，更不是完成 ASIC netlist、GDS 或流片签核的工程。

### 1.2 放行判定

| 决策 | 判定 | 原因 |
|---|---|---|
| 继续维护三个核心 RTL | GO | 代码可综合，固定点合同和单元 TB 有直接证据 |
| 开始 `SAR_16B_5M` adapter/calibration PHY 实现 | GO | P0 接口缺口已经定位，下一步路径明确 |
| 声称完整复现 Huang 芯片 | NO-GO | 只复现数字边界和行为趋势，缺 SS/VCM/真实 SRM/PEX/硅片 |
| ASIC synthesis/STA signoff | HOLD | 当前只有 Xilinx FPGA 综合；无 ASIC library、SDC/MMMC、CDC/LEC/DFT |
| GDS release/tapeout | NO-GO | 无完整 routed layout、DRC/LVS/PEX、IR/EM、stream-out 或 release manifest |
| TCAS/JSSC 已形成创新结论 | NO-GO | 当前只有候选假设；未完成现有技术检索、实现和对比证据 |

### 1.3 P0 阻断项

1. VM 正确物理 CDAC code 是 `BITP<20:1>`，而旧实例使用 `BITP<19:0>`；同时把 Flash/CDAC MSB `BITP<20>` 错作 valid。
2. 异步 SAR 的 EOC/code 必须先原子锁存，再跨到自由运行 `dig_clk`；当前没有 adapter、CDC/RDC 证明。
3. `sar_adc_digital_top.sv` 自己声明只是 skeleton，没有 normal/calibration/SRM mode arbitration 和 AFE 时序。
4. 校准核只输出抽象 `dac_p_force/dac_n_force`，没有实际 `VCM/SET/RSTT/CLKAZ/READYN` PHY sequence。
5. 22-count SRM estimator 已通过数字单测，但 VM 没有同一 residue 下 22 次额外比较和 transaction pairing。
6. VM 中旧 `sar_reconstruction` 实例 `I94` 为 `nlAction=ignore`，reset、writeback 和 output 未闭合。
7. 当前唯一相关 OA layout 只有 9 个器件实例、0 个顶层 shape；不是完整 ADC layout。

## 2. 四轮独立审查方法

| Reviewer | 独立范围 | 主要输出 | 最终 disposition |
|---|---|---|---|
| Review 01 | RTL、DV、fixed point、CDC/RDC、综合、STA、LEC/GLS、DFT | `reviews/REVIEW_01_RTL_TO_NETLIST_CN.md` | RTL baseline 可继续；tapeout integration NO-GO |
| Review 02 | VM schematic、AMS、VCM、CDAC、layout、DRC/LVS/PEX、GDS | `reviews/REVIEW_02_AMS_LAYOUT_GDS_CN.md` | 架构相关但不可直连；physical signoff GAP |
| Review 03 | wafer/package/ATE/bench、论文关系、TCAS/JSSC 边界 | `reviews/REVIEW_03_SILICON_PAPER_NOVELTY_CN.md` | 仅数字边界 partial reproduction；投稿主张未成立 |
| Review 04 | 对前三轮逐条反驳、矛盾消解、跨域 transaction challenge | `reviews/REVIEW_04_ADVERSARIAL_INTEGRATION_CN.md` | 以第四报告为最终挑战记录 |

各 reviewer 不以“前一轮写了 PASS”作为证据，而回到 RTL、TB、VM checkpoint、OA 数据、行为输出和论文重新判断。主报告只接受可定位的文件、日志、脚本、网表/版图对象或论文事实。

## 3. 数字算法原理与 RTL 对应

### 3.1 加权重构

对 20 个决策位 `b_i` 和 Q8 权重 `W_i`，当前重构核计算 signed differential sum：

```text
s_i = +1, b_i=1
s_i = -1, b_i=0
S = sum(s_i * W_i), i=0..19
D = sat16(round((S/2 + R_SRM) / 2^8))
```

RTL 对应：

- `sar_reconstruction.sv:83-90` 保存低 6 位 nominal Q8 权重，并接受校准 writeback。
- `sar_reconstruction.sv:136-149` 以 `+W_i/-W_i` 做 4 x 5 组并行求和。
- `sar_reconstruction.sv:171-174` 合并四组 partial sums。
- `sar_reconstruction.sv:215` 做 `/2` 并注入同单位的 SRM residue。
- `sar_reconstruction.sv:221-233` Q8 rounding、右移和 signed-16 saturation。

工程限制：

- reset 后 bit6 至 bit19 权重为 0，必须有 `weights_ready` 或 normal conversion gate；当前 top 未提供。
- 现有 `+0.5 LSB` rounding 对负值并非严格对称。若目标是 round-half-away-from-zero 或 round-to-nearest-even，需冻结合同并增加负半 LSB 边界 TB。
- `CAP_NUM=20`、`FRAC_BITS=8`、`OUTPUT_WIDTH=16` 已由 guard 锁定，这是受控配置，不应再描述为完全参数化。

### 3.2 P/N 递归前景校准

论文关系为：

```text
D_k,+ = +W_k + V_os + n_+
D_k,- = -W_k + V_os + n_-
W_hat_k = (D_k,+ - D_k,-)/2
```

`M=32` 个 P/N pairs 的理想随机噪声标准差：

```text
sigma(W_hat_k) = sigma_n / sqrt(2M) = sigma_n/8
```

当前 RTL 从 bit6 递归到 bit19：

- `sar_calib_ctrl_serial.sv:217-230` 执行 P setup/search/calc、N setup/search/calc、accumulate/update。
- `sar_calib_ctrl_serial.sv:308-315` 以已知 `shadow_weights` 串行重建低位量化结果。
- `sar_calib_ctrl_serial.sv:323-334` 累加 P/N 结果并写回当前位，供下一高位递归使用。
- `sar_calib_ctrl_serial.sv:183-198` 对最高两位进行 protection compensation。
- `sar_calib_ctrl_serial.sv:363` 除以 `2*AVG_LOOPS`，默认 `AVG_LOOPS=32`。

这里的 `meas_val_p + meas_val_n` 依赖 phase-N SAR code 已经按相反极性编码为正幅度。TB 可证明当前行为模型内部自洽，但 VM comparator polarity、reference switching 和 differential code convention 尚未验证，不能仅凭加法形式证明物理正确。

### 3.3 SRM 数字估计

当前 estimator 统计 22 次 noisy decisions 中的 1 数量 `K`，用离散 inverse-normal LUT 得到 Q8 residue：

```text
p_hat = f_endpoint(K, 22)
R_Q8 = round(0.5 * Phi_inverse(p_hat) * 2^8)
```

`srm_residue_estimator.sv:45,67-74` 把 `22 decisions/Q8` 锁成受控合同；`123-151` 完成 accepted-decision count 和 LUT update。

P0 事务问题：`sar_adc_digital_top.sv:146` 把保持的 `srm_residue_q` 直接送入每次 reconstruction，但 top 没有 code/residue transaction ID、freshness 或 `srm_done` gate。若连续转换，旧 residue 可能被错误应用于新 raw code。这是 integrated top 必须修复的确定性问题。

## 4. 本轮重新运行的数字验证

### 4.1 XSIM

本轮在 Vivado 2018.3 64-bit 下重新运行；需显式设置 `PROCESSOR_ARCHITECTURE=AMD64`，否则 launcher 会误选不存在的 win32 executable。

| TB | Checks | Failed | 证明范围 |
|---|---:|---:|---|
| `tb_sar_recon_binary_norm` | 49 | 0 | 20-to-16 binary normalization、流水、writeback、SRM +/-1 code |
| `tb_recon_q8_split_weights` | 17 | 0 | Q8 split-weight 与 manual model bit-exact |
| `tb_srm_residue_estimator` | 17 | 0 | 22-count LUT 边界、中点和对称性 |
| `tb_gain_comp_check_lsb` | 10 | 0 | 5 次行为 MC；worst residual 0.4937 LSB |
| 合计 | 93 | 0 | 仅 RTL 单元/合同范围 |

纠错：Review 01 文本写了“100 checks”，但四份当前 `xsim.log` 的计数和为 93；主报告以直接日志为准，把 100 标记为 `CONTRADICTED` 文档错误。

### 4.2 综合

| Top | WNS @ 10 ns | TNS | Slice LUT | Slice FF |
|---|---:|---:|---:|---:|
| `sar_reconstruction` | +3.999 ns | 0 | 950 | 818 |
| `srm_residue_estimator` | +7.480 ns | 0 | 26 | 22 |
| `sar_calib_ctrl_serial` | +5.449 ns | 0 | 533 | 821 |
| `sar_adc_digital_top` | +3.957 ns | 0 | 1520 | 1661 |

这些数字只证明 `xc7a35tfgg484-2` 上单时钟 100 MHz post-synth timing 通过。它不证明 ASIC PDK 面积/功耗/时序，也没有约束 VM async inputs、I/O delays、CDC、reset recovery/removal 或 multi-mode paths。

### 4.3 工具缺口

- `python scripts/check_repo_consistency.py`：PASS。
- Verilator：`NOT_RUN`，当前机器无 executable；这既不是 lint fail，也不是 lint pass。
- 未发现可用的 SpyGlass/Questa CDC、Jasper/Formality/Conformal、scan/ATPG、SDF GLS 或 UPF 结果。

## 5. 行为级实验的正确解读

### 5.1 16-bit 理想锚点

理想满幅正弦量化 SNDR：

```text
SNDR_ideal = 6.02N + 1.76 = 98.08 dB, N=16
```

修正后的 physical-CDAC revalidation 报告给出：

| Case | SNDR |
|---|---:|
| Direct ideal quantizer, full scale | 98.0791 dB |
| Segmented CDAC, no SRM | 95.0870 dB |
| Segmented CDAC, exact physical residue | 98.0789 dB |
| Segmented CDAC, expected-count SRM | 98.0449 dB |
| 22-decision stochastic SRM | mean 97.1437 dB |

因此，理想 16-bit 锚点已经达到 98.08 dB。`no SRM` 的 95.09 dB 不是因为脚本偷偷加入 ordinary sampling/comparator noise；该实验把这些噪声设为 0。差值来自 proxy segmented decision/residue 未被数字解码完全恢复。它证明 SRM/residue 在该 proxy converter 中承担信息恢复角色，不能被解释成真实芯片关闭 SRM 必然损失同样数值。

### 5.2 512-chip mismatch 实验

物理代理配置：unit capacitor sigma 1.2%，node parasitic sigma 2%，comparator-input-cap sigma 2%。512 个 virtual chips 的 effective-weight RMS relative error 平均 0.730%，max-absolute relative error 平均 1.779%。

`CAL_CURRENT_SRM` full-scale 结果：

- mean SNDR 94.761 dB，median 95.256 dB；491/512 大于等于 94 dB。
- mean SFDR 111.985 dBc。
- mean INL lower/upper 约 -1.020/+1.025 LSB。
- mean missing code 0.469，但 worst 30；存在少量 saturation/outlier，最差 SNDR 55.619 dB。

结论是 **行为模型内校准有效，但尚未达到流片良率结论**。原因是电容中心值和 bridge/parasitic 网络来自项目 MATLAB/行为假设，而非 VM final schematic、PDK mismatch statistics 或 PEX extraction。

### 5.3 16-bit on-chip self-cal + ADCToolbox 独立交叉实验

新增独立实验包：

```text
analysis/self_cal_adctoolbox_behavioral_20260830/
```

这里重新冻结了主算法身份：ADCToolbox 仅用于 FFT、ramp DNL/INL 和外部 sine-fit baseline；片上主校准仍执行 6-bit LSB reference、P/N、32 pairs、bit6..19 recursion、b18/b19 protection 和 Q8 writeback。

单一 reference chip 使用 6+4+5+5 physical-CDAC proxy，配置 unit-cap sigma 1.2%，实际 effective-weight RMS relative error 0.5919%；normal sampling/comparator/reference/settling noise 全部关闭。结果如下：

| Decoder | SNDR | SFDR | INL pp | Missing |
|---|---:|---:|---:|---:|
| Direct ideal 16-bit control | 98.093 dB | - | - | - |
| Nominal Q8, no SRM | 61.630 dB | 66.731 dB | 108.505 LSB | 1061 |
| Project on-chip self-cal, no SRM | 93.433 dB | 105.547 dB | 2.732 LSB | 4 |
| Project on-chip self-cal, expected SRM | 95.437 dB | 106.870 dB | 1.909 LSB | 0 |
| Project on-chip self-cal, stochastic 22 SRM | 94.907 dB | 107.049 dB | 1.909 LSB | 0 |
| Oracle Q8, no SRM | 95.181 dB | 117.945 dB | 1.999 LSB | 556 |
| Oracle Q8, exact residue | 98.053 dB | 124.417 dB | 0.000 LSB | 0 |
| ADCToolbox external sine baseline | 98.026 dB | 124.978 dB | 0.837 LSB | 0 |

片上自校准单独带来 31.804 dB SNDR 改善，gain-aligned weight RMSE 从 9.286 LSB 降到 0.2286 LSB，改善 40.63 倍。expected SRM 再增加 2.003 dB，真实 22-count stochastic case 相对 expected 上限损失 0.530 dB。这里 normal comparator noise 为 0，因此这 2.003 dB 只应解释为 residue-information recovery，不是论文前放噪声抑制的证据。该结果证明项目自校准在当前物理失配代理内有效，不证明 VM transistor/PEX/silicon。

为单独验证 SRM 降噪方向，独立包又执行了 32 次 paired comparator-noise ablation：每次先用 `sigma_comp=0.5 LSB` 生成一份带噪声的 8192-point raw-bit stream，再让 no-SRM 和 22-decision SRM 解码器共用该 raw stream。结果如下：

| Weight path | No SRM mean SNDR | 22-SRM mean SNDR | Paired gain | Error RMS reduction |
|---|---:|---:|---:|---:|
| Oracle physical weights | 90.532 dB | 95.888 dB | +5.356 dB | 0.6203 -> 0.3348 LSB |
| Project self-cal weights | 89.716 dB | 93.888 dB | +4.172 dB | 0.6722 -> 0.4158 LSB |

该成对实验确认当前 SRM 数字行为模型确实降低 comparator-decision/quantization-residue 路径的误差，而不是通过重新抽取一组更有利的 normal-conversion noise 制造改善。它仍未包含 split-sampling kT/C cancellation、AZ aliasing、前放带宽噪声谱和真实 residue-hold timing，因此不能替代论文 `111 -> 38 uVrms` 或 VM AMS 证据。

差距分解表明：nominal weights 即使加入 exact physical residue 也只有 61.632 dB，说明低值由 weight mismatch 主导；oracle weights 在 no-SRM 下为 95.181 dB，expected SRM 后为 98.020 dB，约 2.84 dB 属于 residue information；self-cal expected-SRM 比 oracle 仍低 2.584 dB，属于当前 weight-estimation residual。完整解释见独立行为报告 8.5 至 8.8 节。

工具箱由独立 reviewer 完成三轮审计；冻结 checkout 测试为 `62 passed, 6 deselected, 1 xfailed, 13 warnings`。外部 sine-fit 使用 16384 点已知正弦和全局浮点 least-squares，必须与 32-pair 片上方案分开命名和解读。

### 5.4 512 的三种含义必须分开

| “512” | 含义 | 可支持的结论 |
|---|---|---|
| 512 virtual chips | 512 个 mismatch seeds，每颗有 8192-point FFT | 行为模型统计，不是 silicon sample size |
| 512 decoded conversions | AMS/bench bring-up 最低连续 code 数 | 可检查码序、EOC、吞吐和粗略波形，不足以做 94 dB FFT |
| 512 silicon dies | 量产/良率样本 | 当前完全没有 |

严肃动态测试至少 8192 点；论文级低噪声结果建议 65536 点 coherent capture，或明确 window、fundamental bins、harmonic bins 和 spur exclusion。

## 6. VM `SAR_16B_5M` 兼容性结论

### 6.1 已核实层次

VM 电路包含 split-sampling/CDAC、2-bit flash、异步 SAR logic、comparator/preamplifier、VCM/sampling controls 和一个旧 `sar_reconstruction` 实例。架构方向与 Huang 论文及本项目数字核相关。

### 6.2 位与事务映射

| VM signal | 物理含义 | 数字侧处理 |
|---|---|---|
| `BITP<20>` | Flash/CDAC MSB | `raw_bits[19]` |
| `BITP<19>` | Flash/CDAC next bit | `raw_bits[18]` |
| `BITP<18:1>` | comparator-driven CDAC decisions | `raw_bits[17:0]` |
| `BITP<0>` | 最终附加判决，不驱动物理 CDAC | 独立保存，不能作为 reconstruction LSB |
| `SET<20>`/真实 EOC | 转换完成事件候选 | 先确认稳定窗口，再 atomic capture + CDC |

正确主映射是：

```text
captured_raw[19:0] = BITP[20:1]
```

### 6.3 时钟和 CDC

`COMP_AZ.READYN` 推进 async SAR sequence。推荐结构：

```text
async SAR domain
  -> EOC-qualified 20-bit holding register
  -> toggle/req-ack or async FIFO CDC
  -> free-running dig_clk domain
  -> reconstruction/SRM/calibration bookkeeping
```

不能逐 bit 使用普通 2FF synchronizer，因为会在不同 cycle 混合两笔 code。必须先在源域锁存整笔 bus，再同步 ownership event。

### 6.4 现有 AMS 时长

当前 Maestro transient 约 30 us；在 5 MS/s 理论最多约 150 conversions，且已有历史 simulation errors。它不能满足用户要求的 512 个连续有效解码点，也没有 `adc_dout/data_valid/calibrated_weights/srm_residue` 的闭环输出。

## 7. Layout、GDS 和 physical signoff 现场证据

### 7.1 文件清点

在四个声明的 SAR16B roots 下扫描 2581 个文件：

- OA layout：1 个。
- GDS/OASIS stream-out：0。
- DEF/LEF 等 place-route exchange：0。
- extracted/timing artifacts：0。
- 以 DRC/LVS/PEX/ERC/antenna/IR/EM 命名的 signoff artifacts：0。

“0”只表示这些 roots 下没有匹配文件，不证明 VM 其他位置绝对不存在；发布时仍应由设计负责人冻结 search scope。

### 7.2 唯一 OA layout 的真实内容

`SAR_16B_5M_TB/TEST_TRAN_ALL_TRANSISTOR_wFLash_ver6/layout/layout.oa` 经 read-only Virtuoso SKILL 读取：

- object count 9，instance count 9，shape count 0。
- 5 个 `cfmom`、1 个 `crtmom`、1 个 `mimcap`、1 个 NMOS、1 个 PMOS。
- 顶层没有可见 routing/shape；截图只显示松散器件。

这不是完整 `SAR_16B_5M` ADC layout，不能支持 matching、DRC、LVS、PEX、IR/EM 或 GDS release 结论。

## 8. RTL 到 GDS 的门禁

完整明细见 `TAPEOUT_GATE_MATRIX.csv`。当前 17 个 gate 中没有任何一个可以支持 tapeout release；主要阶段为：

| 阶段 | 当前状态 | 退出条件 |
|---|---|---|
| Requirements/contract | PARTIAL | 冻结 bit/EOC/Q8/latency/SRM ownership 和 release manifest |
| RTL unit DV | PARTIAL | lint、coverage、reset/X/Z、back-to-back 和 assertions 闭合 |
| Async adapter/calibration PHY/SRM PHY | GAP | 正常、校准、SRM 三模式在真实 switching path 上闭合 |
| Transistor AMS | GAP | 0-noise 512 code、8192+ FFT、PVT/MC、失败统计和 raw data |
| ASIC synth/STA/CDC/LEC/DFT | GAP | 目标库和 MMMC signoff，unconstrained=0，equivalence/ATPG clean |
| Layout/PnR | FAIL/GAP | 完整 routed hierarchy 和 matching review |
| DRC/LVS/PEX/post-layout | GAP | final hash 对齐，所有 blocker 清零或有批准 waiver |
| GDS/OASIS | GAP | re-import、checksum、layer map、manifest 与 LVS/PEX 同版本 |
| Silicon test | GAP | wafer/package/ATE/bench raw data 可追溯 |

## 9. 流片前实现顺序

### Phase A：冻结设计身份

1. 建立 `release_manifest.yml`，记录 top/library/cell/view、RTL commit、PDK/model、corner、tool version、script/hash。
2. 冻结 `BITP<20:1>`、EOC、comparator polarity、Q8、latency、SRM decisions 和 reset semantics。
3. 对 VM CDAC 实际 netlist 做 P/N connectivity、duplicate/dangling net 和 effective-weight extraction。

### Phase B：完成数字/模拟适配

1. `sar16b_async_capture_adapter`：atomic code capture、source-held bus、CDC handshake、overflow/error counters。
2. `sar16b_mode_arbiter`：normal/calibration/SRM 独占，进入和退出均回 VCM/reset safe state。
3. `sar16b_calib_phy_sequencer`：sampling、reference preload、target toggle、settle、AZ/evaluate、READYN/timeout。
4. `sar16b_srm_phy_sequencer`：hold one residue、22 evaluates、decision_valid、code/residue transaction ID。
5. 加 `weights_ready`、calibration checksum/readback 和 stale-residue protection。

### Phase C：验证闭环

1. 纯数字：lint、formal assertions、coverage、random backpressure、reset during transaction。
2. 0-noise AMS：SRM off，连续 512 EOC/code，证明 bit order、VCM 首次切换、full-scale 和无额外降级。
3. physical mismatch：同一 decision stream 用 nominal/calibrated/oracle 三套权重解码。
4. PVT/MC：normal、P/N calibration、b18/b19 headroom、SRM 22 decisions、timeout/metastability。
5. 长记录：8192/65536-point FFT，ramp/sine-histogram DNL/INL，完整 seed/checkpoint/raw data。

### Phase D：ASIC 和 physical closure

1. ASIC library synthesis、MMMC SDC/STA、CDC/RDC、LEC、GLS/SDF、UPF、scan/ATPG/MBIST。
2. floorplan、mixed-signal boundary、clock/reset/power/reference route、CDAC matching 和 isolation。
3. DRC/LVS/ERC/antenna/density/latch-up/ESD/IR/EM。
4. PEX 后重新跑 normal/calibration/SRM、PVT/MC/noise 和 failure statistics。
5. 仅在 final database hash 与 signoff reports、stream-out manifest 一致时释放 GDS/OASIS。

## 10. 硅后测试计划

### 10.1 必须设计进芯片的可观测性

- 20-bit raw decision readback、final extra decision、EOC timestamp/status。
- 20 个 Q8 weight readback/write test mode、calibration target/loop/status/error。
- SRM 22-bit decision stream、ones count、residue Q8、transaction ID。
- bypass modes：nominal/calibrated/oracle-emulation、SRM off/on、SS off/on、manual VCM/phase control。
- scan/test clock/reset、timeout、brownout/reset cause 和版本 ID。

### 10.2 Wafer sort

- continuity、leakage、supply shorts、digital scan/ID/readback。
- comparator alive、clock/EOC alive、raw code monotonic smoke。
- foreground calibration completion、weight range/checksum、SRM counter alive。
- 低成本 DC ramp 粗 DNL/missing-code 筛选。

### 10.3 Packaged ATE/bench

- DC：offset/gain、transition histogram、DNL/INL、missing code、hysteresis。
- AC：SNDR/SNR/SFDR/THD/ENOB vs input frequency/amplitude/sample rate。
- 四象限 ablation：SS off/on x SRM off/on；校准前/后；不同 averaging loops。
- PVT：VDD/temp/reference/common-mode/clock jitter；记录 fail code 和 calibration convergence。
- 功耗：analog/digital/reference/clock 分 rail；报告 normal、calibration、SRM 模式能量。
- 每份原始数据绑定 wafer/die/package/board/instrument/firmware/RTL/weight/temperature/time。

## 11. 与 Huang 论文的联系和差异

### 11.1 联系

- 都采用 20-decision redundant-weight 思路和小 CDAC/split-sampling 背景。
- 都以 6 个 LSB reference decisions 递归测量 14 个高位。
- 都使用 P/N polarity 消除静态 offset，并默认 32 pairs。
- 都需要 b18/b19 over-range protection。
- 都使用 22-decision statistical residue information。

### 11.2 关键差异

| Huang 2025 | 当前项目 |
|---|---|
| 完整 transistor circuit、layout 和 silicon | 数字 RTL、行为代理和未闭合 VM schematic |
| SS、VCM、reference、AZ、SRM physical timing 已实现 | PHY sequencer/mode arbiter 尚未实现 |
| 论文中 raw decision ownership 由电路架构确定 | VM 暴露 20 CDAC/21 latched decision 的 mapping hazard |
| calibration 与 actual CDAC switching 共用 | 当前只输出抽象 force buses |
| 93.7 dB SNDR、INL、功耗和 FoM 为硅片实测 | 无 GDS、die 或测量数据 |

因此，当前最准确的表述是：**复现了论文数字算法边界和部分统计趋势，尚未复现论文 mixed-signal 实现与芯片结果。**

## 12. TCAS/JSSC 创新候选与反驳

以下均为 hypothesis，不是 novelty conclusion。投稿前必须补 IEEE Xplore/Google Scholar/专利检索，并覆盖 2025-2026 的新工作。

### 12.1 候选 A：异步 20-CDAC/21-decision transaction ownership

主张：提出可形式化验证的 atomic code capture、residue ownership 和 CDC architecture，解决 split-sampling async SAR 中 final decision、EOC 和 22-decision SRM 的跨域一致性。

反驳：若只是“加同步器和寄存器”，属于常规工程，难以形成论文。需要 theorem/assertion、lost/mixed-code failure model、面积/功耗/latency、PVT/AMS 及 FPGA/硅片结果。完成后更接近 TCAS-II。

### 12.2 候选 B：VCM-aware shared calibration PHY

主张：normal SAR、P/N foreground calibration 和 SRM 共用实际 switching path，通过 VCM-safe phase sharing 降低额外开关、校准能量和 transient error。

反驳：Huang 已说明 calibration 与 normal SAR 高兼容并可启用 SS/SRM。必须提出论文未覆盖的新 phase/circuit，并量化 energy、settling、linearity、offset tolerance 和 area。若有 PEX/silicon，可能达到 TCAS-I/JSSC。

### 12.3 候选 C：confidence-based adaptive calibration stop

主张：不固定 32 pairs，而根据每位 posterior confidence、reference-DAC error floor 和递归误差传播动态停止；高位采用不同 sample budget。

反驳：仅改变平均次数不足。必须推导 bias/variance 和 error propagation，证明在同 SNDR/SFDR/yield 下减少 calibration time/energy，并与 fixed-32、Huang、dual-segmental/self-calibration 方法公平对比。适合 TCAS-I。

### 12.4 候选 D：SRM/calibration/headroom 联合策略

主张：将 top-bit protection、residue estimator precision 和 calibrated full-scale gain 联合优化，避免 saturation outliers，同时最小化 22-decision 开销。

反驳：当前 512-chip 结果仍有严重 outlier；在修复前它是问题，不是贡献。需要先证明 root cause，再给出可综合算法和 PVT/MC/silicon improvement。

### 12.5 候选 E：production-observable calibration architecture

主张：片上 weight/SRM/raw readback、fault isolation 和 ATE-friendly test compression，使高精度 SAR 校准可量产诊断。

反驳：DFT/observability 通常是 supporting contribution，单独不足以支撑 JSSC；必须绑定可测的 test-time、coverage、yield-learning 或 field-recalibration 优势。

### 12.6 投稿层级判断

| 层级 | 当前距离 | 必需新增证据 |
|---|---|---|
| TCAS-II | 最近，但尚未实现 | adapter/PHY RTL、formal+AMS、硬件成本和明确 failure reduction |
| TCAS-I | 中等距离 | 新估计/控制理论、强 baseline、PVT/MC、post-layout/FPGA 或 silicon |
| JSSC | 距离大 | 新 mixed-signal circuit/system contribution、完整 GDS、post-layout 和芯片实测 |

不能作为新颖点直接复用：split sampling、6-LSB-to-14-MSB calibration、P/N offset cancellation、32-pair averaging、b18/b19 protection、22-decision SRM、SS+SRM 10x averaging benefit。

## 13. 证据索引

- `evidence/local_validation_20260830.json`：本轮 XSIM、Vivado synthesis、consistency 和 lint 状态。
- `evidence/vm_sar16b_layout_summary.json`：read-only OA object/shape/instance inventory。
- `evidence/vm_sar16b_layout_oa.png`：唯一 layout 视图截图。
- `evidence/vm_sar16b_physical_asset_inventory.json`：四个 VM roots 的物理资产清点。
- `evidence/PAPER_FACTS_AND_RELATIONSHIP.md`：论文事实、数学关系和复现距离。
- `reproducibility_audit_adc.json`：项目级粗审，状态 WARN；不能代替 clean rerun。
- `TAPEOUT_GATE_MATRIX.csv`：G0-G16 release gates。
- `PAPER_COMPARISON_AND_NOVELTY_MATRIX.csv`：论文联系、差异和创新候选边界。
- `../self_cal_adctoolbox_behavioral_20260830/SELF_CAL_BEHAVIORAL_REPORT_CN.md`：16 位片上自校准数学、实现、运行和结果总报告。
- `../self_cal_adctoolbox_behavioral_20260830/reviews/REVIEW_01_ADCTOOLBOX_AUDIT_CN.md`：ADCToolbox 三轮独立源码/API/tests/集成审计。
- `../self_cal_adctoolbox_behavioral_20260830/outputs/summary.json`：本轮 noise-isolated 自校准、SRM、oracle 和外部 baseline 的机器可读证据。

## 14. 最终工程判断

1. **算法核：PARTIAL PASS。** 三个核心 RTL 的方向、Q8 算术和当前 TB 范围成立。
2. **自校准有效性：PASS within behavior model / GAP at physical integration。** noise-isolated reference chip 上 SNDR 提升 31.80 dB、gain-aligned weight RMSE 改善 40.63 倍；对 VM/PDK/PEX 尚未证明。
3. **VM 兼容性：FAIL until adapter/PHY closure。** 位映射、EOC/CDC、mode arbitration、calibration PHY 和 SRM transaction 都是 P0。
4. **ASIC/GDS：GAP/NO-GO。** 当前没有足以审查的完整 physical implementation 或 signoff package。
5. **硅片：NOT AVAILABLE。** 不存在可声称的 wafer/package/bench 性能。
6. **论文：Huang digital-boundary reproduction only。** TCAS/JSSC 只能从新问题和新证据出发，不能把已有论文方案或普通工程补全重新命名为创新。

最终 disposition：**GO for adapter + mixed-signal closure；HOLD for ASIC signoff；NO-GO for GDS/tapeout claim；NO-GO for current JSSC novelty claim。**
