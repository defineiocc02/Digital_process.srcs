# Huang 2025 校准收敛代理模型审阅与工程接入报告

日期：2026-05-26
工程版本：`v3.7.0-surrogate-analysis`
新增入口：`analysis/surrogate/replicate_huang2025_calibration_convergence.py`

## 1. 结论

本次工作将用户审阅后的 Python 思路转化为工程内可重复运行的统计分析模块，但没有原样接受第四版脚本中的两个关键隐患：

1. 原脚本用浮点重构值直接计算 SNDR/SFDR/ENOB，未建立明确的 16-bit 数字输出边界，会出现超过 16-bit 量化极限的乐观结果。
2. 原脚本把代理权重表的最小项当作论文所述 `80 uV` 输出 LSB。该表来源于 RTL 重构域，不是已经证明的 analog SAR decision vector，其最小项只相当于本模型外部 16-bit LSB 的 `0.760854` 倍，不能直接用于论文噪声标尺。

修正后的模型已执行以下处理：

- 所有动态性能指标均在显式的 16-bit 输出量化之后计算。
- `111 uVrms / 80 uV = 1.3875 LSB` 与 `38 uVrms / 80 uV = 0.475 LSB` 均按外部 16-bit 输出 LSB 注入。
- SS+SRM on/off 使用同一批虚拟芯片与同一批标准高斯样本，仅改变噪声幅度。
- `Navg` 使用累计样本平均，并明确为“有效独立测量数”，不直接等同于 RTL 的 `AVG_LOOPS`。
- 增加 proxy SAR 与 RTL Q8 直接映射诊断，不把代理表误称为完整模拟前端模型。

本次接入得到的工程判断为：

> 当前 RTL 是具有可维护接口和单元回归的数字算法核心；新增 Python 模型可用于研究校准噪声与平均时间的趋势。但两者均不能单独证明论文完整 ADC 的绝对性能、物理 CDAC 正确性或流片达标。

## 2. 论文算法基本原理

依据 Huang 等人的 JSSC 2025 论文及相关博士论文，该 ADC 的关键数字相关机制如下。

### 2.1 冗余 SAR 与权重校准

- 转换使用 20 个 decision/weight 来实现 16-bit 分辨率，存在冗余位。
- 小电容 CDAC 的 mismatch 在未校准时只足以支撑约 11-bit 线性度，因此必须估计并重构真实 bit weight。
- 最低 6 位 LSB section 复用为 reference DAC，测量 14 个较高位的权重。
- 校准从低到高递归进行，后续高位依赖此前已获得的低位权重。
- P/N 两个极性测量用于消除 comparator/pre-amplifier offset。
- 顶端位需要保护 switching 以避免可用范围或共模轨迹异常。

### 2.2 SS+SRM 与校准平均时间

- 正常 SAR decision 结束后，在 DAC 保持不动的条件下执行 22 次额外噪声判决。
- 数字端对额外判决计数，再通过统计映射估计 residue。
- 论文给出的 shorted-input noise 约从 `111 uVrms` 降至 `38 uVrms`。
- 论文讨论中，启用 SS+SRM 后约 `64` 次 averaging 可达到相应动态趋势；不启用时所需 averaging time 约大一个数量级。

本报告中的 Python 模型仅复现“噪声下降引起 averaging convergence 改善”这一统计关系，而不是上面全部 switching 与 mixed-signal 行为。

## 3. 全文代码重新分析

### 3.1 `sar_calib_ctrl_serial.sv`

已实现能力：

- `MAX_CALIB_BIT=5`，即 bit 0 至 bit 5 作为可信 LSB reference segment。
- `target_bit` 从 bit 6 递归推进至 bit 19。
- P/N 测量路径和 `meas_val_p + meas_val_n` 的 offset-cancellation 结构存在。
- `AVG_LOOPS=32`，写回计算按 `2 * AVG_LOOPS` 归一化，与双极性测量匹配。
- bit 18/19 存在 protected switching 与数字补偿路径。
- 写回接口 `w_wr_en/w_wr_addr/w_wr_data` 能连接重构 RAM。

本次修正：

- 源码头部遗留的 `Q18.12` 注释与工程 `Q8` fixed-point contract 不一致；已在权威 `rtl/` 文件和 Vivado 活动副本中统一修正为 `Q8`，其中 `256 = 1 output-code LSB`。
- 本次仅修订注释，不改变 FSM、算术或综合逻辑。

未闭合边界：

- RTL 接收 `comp_out`，并不模拟真实 comparator noise、offset 漂移、kickback 或 DAC settling。
- `AVG_LOOPS` 与论文中“有效独立测量数”的物理映射仍需要由模拟时序定义。

### 3.2 `sar_reconstruction.sv`

当前数据通路合同为：

```text
weighted_sum = sum(raw_bits[i] ? +weight_ram[i] : -weight_ram[i])
normalized   = (weighted_sum >>> 1) + srm_residue
rounded      = normalized + 2^(FRAC_BITS - 1)
adc_dout     = saturate_to_int16(rounded >>> FRAC_BITS)
```

技术判断：

- Q8 权重、SRM Q8 residue 与 signed 16-bit 输出的接口合同清楚。
- `/2` 来自当前双边 `+W/-W` 重构约定，不可在行为模型中无说明地省略。
- 当前 rounding 对负值不是严格对称舍入，但已被 TB bit-exact 地固定为现有基线。
- 正常转换前必须写入高位校准权重，因为复位只初始化可信低位段。

### 3.3 `srm_residue_estimator.sv`

当前模块完成 22 个额外 decision 的计数与 Q8 LUT residue 输出。它正确表达数字边界，但不负责产生模拟噪声判决流。因此：

- LUT 接口可由 TB 验证。
- 论文中的 SS、comparator noise 和 residue 统计正确性仍需更高层模型或 mixed-signal 仿真证明。

### 3.4 Testbench 覆盖

现有四个 TB 的角色仍然合理：

| TB | 已证明内容 | 不能证明内容 |
| --- | --- | --- |
| `tb_sar_recon_binary_norm.sv` | binary-normalized pipeline 与基本输出路径 | split-cap 校准链路 |
| `tb_recon_q8_split_weights.sv` | Q8 权重、SRM injection、bit-exact 重构合同 | analog SAR decision 生成 |
| `tb_srm_residue_estimator.sv` | 22-decision LUT 边界 | 真实 comparator noise |
| `tb_gain_comp_check_lsb.sv` | 指定 real-valued TB 环境中的 P/N 递归校准 | 大规模 yield 与真实 PVT |

特别需要保留的工程事实是：`tb_gain_comp_check_lsb.sv` 目前是 5 次 Monte Carlo smoke/regression，而不是论文统计图的充分等价验证。

## 4. 新增模型的工程设计

### 4.1 文件及职责

| 文件 | 职责 |
| --- | --- |
| `analysis/surrogate/replicate_huang2025_calibration_convergence.py` | 运行 proxy sanity、单芯片频谱、paired cumulative Monte Carlo sweep |
| `analysis/surrogate/README.md` | 模型边界、运行方式、未来 RTL-equivalent 模型接口说明 |
| `analysis/surrogate/outputs/` | 运行生成物，已加入 `.gitignore`，不作为源码入库 |

运行命令：

```powershell
python -B analysis\surrogate\replicate_huang2025_calibration_convergence.py
```

`-B` 用于避免 Windows 环境中 Python 缓存文件写入对分析运行产生干扰。

### 4.2 代理权重边界

模型保留如下 20 项 reconstruction-domain-derived proxy 表，按 MSB-first 供代理转换使用：

```text
40248.69, 20124.35, 10062.17, 5031.09, 5031.09,
2535.25, 1267.63, 633.81, 316.91, 316.91,
268.20, 134.10, 67.05, 33.53,
32.00, 16.00, 8.00, 4.00, 2.00, 1.00
```

它适合作为重构权重和趋势代理的输入，但不能被直接表述为从论文物理 CDAC 提取的模拟决策向量。正式物理模型需要从 capacitor array、bridge/parasitic 与 mismatch 重新推导 effective weight。

### 4.3 相比用户第四版脚本的修正

| 项目 | 第四版风险 | 入库实现 |
| --- | --- | --- |
| 输出码域 | 浮点输出直接做 FFT，可产生超 16-bit ENOB | 在每种重构结果后显式 `round/clip` 为 16-bit code |
| 论文噪声 LSB | 使用 proxy 最小权重作为 LSB | 使用外部 `1 / 2^16` 输出 LSB |
| 总增益误差 | 每颗 chip 自身重新归一化会隐藏总增益扰动 | 使用固定 nominal denominator |
| direct RTL 映射 | 无诊断，容易误宣称闭合 | 增加 Q8 `/2`/round/saturation 直接映射诊断 |
| baseline 记录 | 每个 Navg 重复写入不变基线 | baseline 在 CSV 中仅保存 `Navg=0` 一次 |
| yield 表述 | `mean-3sigma` 容易被误读 | 使用 P5 描述性阈值，并明确不是 yield claim |

## 5. 完整运行结果

### 5.1 配置

| 参数 | 值 |
| --- | ---: |
| 输出量化位宽 | 16 bit |
| `n_samples_train` / `n_samples_test` | 32768 / 32768 |
| 训练 / 测试目标频率 | 约 1 kHz / 20 kHz coherent tone |
| Monte Carlo 虚拟芯片数 | 80 |
| SS+SRM enabled measurement noise | `0.475` external LSB rms |
| SS+SRM disabled measurement noise | `1.3875` external LSB rms |
| reference static sigma | `0.13` external LSB |
| Navg sweep | `1, 2, 4, ..., 512, 640, 1024` |

### 5.2 Proxy 与 RTL 直接映射诊断

| 指标 | 结果 | 解释 |
| --- | ---: | --- |
| Proxy 外部码单调性 | `True` | 作为趋势代理未出现反向步进 |
| 外部 16-bit 占用码数 | `65506` | 仅作 sanity check，不是正式 DNL |
| 占用范围内缺码数 | `30` | 证明代理并非理想 16-bit converter |
| Proxy span | `16.394308 bits` | 表的最小项不是外部 16-bit LSB |
| Proxy 最小项 / 外部 LSB | `0.760854` | 不应作为 `80 uV` 标尺 |
| 直接应用 RTL Q8 时饱和比例 | `0.239151` | 约 `23.9151%`，不能将 proxy encoder 与 RTL 直接闭环宣称等价 |

### 5.3 代表性单芯片结果

| Case | SNDR (dB) | SFDR (dBc) | ENOB |
| --- | ---: | ---: | ---: |
| `UNCALIBRATED_NOMINAL` | 80.227 | 85.068 | 13.034 |
| `ORACLE_ACTUAL_WEIGHT` | 95.942 | 127.787 | 15.645 |
| `STATIC_REF_FLOOR` | 94.611 | 114.516 | 15.424 |
| `W_SS_SRM_NAVG64` | 94.441 | 113.187 | 15.396 |
| `ADCTOOLBOX_SINE_BASELINE` | 95.837 | 128.409 | 15.627 |

`ADCTOOLBOX_SINE_BASELINE` 仅表示外部工具在同一 proxy 记录上的独立 sine-fit 对照；其权重域和论文片上校准权重域不作逐位等价解释。

### 5.4 Paired Monte Carlo 收敛结果

| Case | Navg | SNDR mean (dB) | SFDR mean (dBc) | SFDR P5 (dBc) |
| --- | ---: | ---: | ---: | ---: |
| `UNCALIBRATED_NOMINAL` | 0 | 86.674 | 94.295 | 85.648 |
| `ORACLE_ACTUAL_WEIGHT` | 0 | 95.955 | 127.775 | 126.706 |
| `STATIC_REF_FLOOR` | 0 | 94.650 | 112.644 | 107.469 |
| `W_SS_SRM` | 16 | 93.754 | 110.033 | 104.082 |
| `W_SS_SRM` | 32 | 94.239 | 111.521 | 105.682 |
| `W_SS_SRM` | 64 | 94.399 | 111.829 | 106.107 |
| `WO_SS_SRM` | 64 | 93.079 | 108.456 | 102.584 |
| `WO_SS_SRM` | 128 | 93.767 | 109.917 | 104.272 |
| `WO_SS_SRM` | 256 | 94.204 | 111.104 | 105.402 |
| `WO_SS_SRM` | 640 | 94.486 | 111.962 | 106.089 |

使用描述性趋势标记：

```text
SNDR_mean >= 94 dB
SFDR_mean >= 108 dBc
SFDR_P5   >= 100 dBc
```

得到：

| 状态 | 首次达到趋势标记的 Navg |
| --- | ---: |
| SS+SRM enabled | `32` |
| SS+SRM disabled | `256` |
| disabled / enabled 比例 | `8.0x` |

该 `8.0x` 是当前修正代理模型在离散 sweep 与描述性门限下的输出，不应为了追随论文“约 10 倍”的表述而调参修改。它支持相同技术方向：降低校准测量噪声显著减少所需 averaging time。

## 6. 与原算法的距离

| 技术对象 | 已进入 RTL/TB | 已进入本次 Python 模型 | 尚未复现 |
| --- | --- | --- | --- |
| Q8 calibrated reconstruction | 是 | 仅作直接映射诊断 | 物理 raw-bit 对应关系 |
| P/N offset cancellation FSM | 是 | 否 | analog switching correctness |
| 递归 weight writeback | 是 | 否，模型直接扰动真实权重 | RTL-equivalent Python golden model |
| b18/b19 protection | 是 | 否 | 物理 common-mode/range 验证 |
| 22-decision SRM LUT | 是 | 否 | noisy residue closed loop |
| SS+SRM 降噪收敛趋势 | TB 未形成论文统计图 | 是 | full-ADC dynamic mechanisms |
| 16-bit 输出性能边界 | RTL/TB 合同存在 | 是，显式量化 | transistor/PVT signoff |

## 7. FPGA 与流片判断

### 7.1 可肯定的内容

- 当前三个数字核心模块具有明确的 Q8 接口和回归测试。
- 注释标尺已与 fixed-point contract 对齐。
- 新增分析模型能够重复生成统计数据，并避免把浮点模型误写成 16-bit 性能证明。

### 7.2 不可提前宣称的内容

- 不能依据本 Python sweep 宣称 FPGA 上的 mixed-signal 实测性能达到论文水平。
- 不能依据当前 RTL/TB 宣称 ASIC 可直接 tapeout；还缺模拟接口时序、CDC/reset、寄存器控制、physical constraints、PVT 与噪声/失真闭环验证。
- 不能把 proxy 表直接作为 analog SAR decision vector 接入 RTL，因为诊断已显示明显饱和冲突。

## 8. 后续推荐闭环路径

1. 建立 `analysis/golden/huang2025_lsb_ref_calibrator.py`，逐状态复写 `sar_calib_ctrl_serial.sv` 的 P/N、递归更新和高位保护。
2. 建立物理 CDAC/bridge/parasitic 模型，从 physical capacitor mismatch 推导 analog decision weight，而不是反向借用 reconstruction table。
3. 用同一物理模型产生 raw decision，再同时驱动 Python golden 与 RTL XSIM，比较 Q8 writeback 与最终代码。
4. 将 SRM noisy decision 发生器接入闭环，并分别报告校准路径与正常 conversion path 的噪声贡献。
5. 当物理模型闭合后再进行正式 ramp INL/DNL、动态 FFT、PVT/Monte Carlo yield 评估。

## 9. 交付内容与生成物政策

纳入版本管理：

- `analysis/surrogate/replicate_huang2025_calibration_convergence.py`
- `analysis/surrogate/README.md`
- 本报告及 MOC/版本/验证文档更新
- RTL 注释 Q8 合同修正

运行生成但不纳入版本管理：

- `analysis/surrogate/outputs/huang2025_averaging_sweep.csv`
- `analysis/surrogate/outputs/proxy_sanity_report.json`
- `analysis/surrogate/outputs/fig_spectrum_compare.png`
- `analysis/surrogate/outputs/fig_sndr_averaging_sweep.png`
- `analysis/surrogate/outputs/fig_sfdr_averaging_sweep.png`

这样保留了源码、实验定义与报告的可维护性，同时避免把可再生成数据和图片当作权威代码基线。

## 10. 编辑、编译与回归执行记录

### 10.1 编辑范围

| 类型 | 文件/目录 | 变化性质 |
| --- | --- | --- |
| 新增模型 | `analysis/surrogate/` | 新增可重复统计分析，不参与 RTL 综合 |
| 新增报告 | 本文档 | 记录算法边界、修正理由与结果 |
| 文档维护 | `README.md`, `MOC.md`, `docs/*.md` | 更新导航、版本与验证状态 |
| RTL 维护 | 两份 `sar_calib_ctrl_serial.sv` 镜像 | 仅将错误的 `Q18.12` 注释更正为 Q8，无行为改动 |
| Git 清洁度 | `.gitignore` | 忽略可重生成的 analysis output |

### 10.2 执行命令

```powershell
python -B analysis\surrogate\replicate_huang2025_calibration_convergence.py
python -B scripts\check_repo_consistency.py
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_all_xsim.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build.ps1 -Target build_calib_core
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build.ps1 -Target build_recon_core
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build.ps1 -Target build_fpga_demo
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build.ps1 -Target build_asic_skeleton
```

说明：Vivado XSIM 在沙箱内能够完成编译与 elaboration，但清理/link 临时 `xsimk.exe`/object 文件时遇到 Windows access-denied；在获准的沙箱外执行同一仓库脚本后，四项回归正常完成。该现象属于运行环境对生成文件的访问限制，不是 RTL 编译失败。

### 10.3 XSIM 结果

| Testbench | 结果 | 检查数 | 关键结果 |
| --- | --- | ---: | --- |
| `tb_sar_recon_binary_norm` | PASS | 49 | binary normalization、pipeline、SRM injection 全通过 |
| `tb_recon_q8_split_weights` | PASS | 17 | Q8 manual model bit-exact 通过 |
| `tb_srm_residue_estimator` | PASS | 17 | LUT edge/mid/symmetry 通过 |
| `tb_gain_comp_check_lsb` | PASS | 10 | 5 MC runs；worst residual `0.4937 LSB` |

### 10.4 Vivado 2018.3 综合结果

目标器件为 `xc7a35tfgg484-2`，约束为 `100 MHz` 的 `core_synth.xdc`。

| Target | Top | 结果 | Slice LUT | Slice FF | WNS |
| --- | --- | --- | ---: | ---: | ---: |
| `build_calib_core` | `sar_calib_ctrl_serial` | PASS | 529 | 821 | `5.449 ns` |
| `build_recon_core` | `sar_reconstruction` | PASS | 950 | 818 | `3.999 ns` |
| `build_fpga_demo` | `sar_calib_fpga_top` | PASS | 462 | 821 | `5.441 ns` |
| `build_asic_skeleton` | `sar_adc_digital_top` | PASS | 1518 | 1661 | `3.957 ns` |

综合未出现 Error 或 Critical Warning。`build_recon_core`/集成 target 会报告重构中间寄存器在 standalone/flattened synthesis 下被优化、以及层次重建不利于 floorplanning 的普通 warning；这些不改变当前仿真通过事实，但在正式 FPGA implementation 与 ASIC physical synthesis 阶段仍应重新检查时序、层次保留与切换功耗。
