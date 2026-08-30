# ADCToolbox 独立审计报告：片上自校准行为模型集成边界

**审计角色**：独立 ADCToolbox reviewer
**审计 checkpoint**：2026-08-30
**审计对象**：用户指定 fork defineiocc02/ADCToolbox、upstream Arcadia-1/ADCToolbox、本地冻结 checkout，以及本项目片上 16-bit SAR foreground calibration 的集成边界。
**本报告性质**：只读审计；本 checkpoint 未修改 ADCToolbox、未安装依赖、未修改现有工程代码。
**唯一新增文件**：本文件。

## 1. 结论先行

### 总体结论：PARTIAL

ADCToolbox 是可复用的 Python ADC 分析与行为建模工具箱。当前本地冻结版本提供：

1. 物理电容阵列到有效权重的初步计算：convert_cap_to_weight；
2. 二进制/次二进制 SAR 正向行为模型：sar_convert、sar_reconstruct；
3. 频谱、SNDR/SFDR/SNR/THD/ENOB 和 ramp INL/DNL 分析；
4. 外部正弦激励下的数字权重识别：calibrate_weight_sine、calibrate_weight_sine_lite。

核心纠偏如下：

> calibrate_weight_sine 只能作为外部 sine-fit identification baseline 和旁路交叉验证，不能替代本项目 16-bit on-chip self-calibration。

本项目的主校准仍应保持：

    6-bit LSB reference DAC
        -> target bit b6, b7, ... b19
        -> P/N differential measurement
        -> 32 P/N pairs per target bit
        -> comparator-offset cancellation and averaging
        -> recursive shadow-weight update
        -> b18/b19 top-bit protection
        -> Q8 write-back to reconstruction engine

片上算法结论：GAP。ADCToolbox 没有实现上述片上校准 FSM、P/N 模拟测量、VCM/开关时序、保护位策略或 Q8 RTL write-back。

工具箱复用结论：VERIFIED（有边界）。本地 0.9.1 checkout 的 calibration unit tests 与 cap-to-weight tests 已安全运行通过；这证明既有函数契约和回归样例在其测试范围内可用，不证明物理 split-CDAC、论文电路或本项目 RTL 的完整正确性。

用于本项目行为模型的推荐方式：VERIFIED/PARTIAL。用 ADCToolbox 建立独立 analog SAR forward model、physical cap-to-weight、train/test 频谱和 ramp metrics；将片上 P/N recursive calibration 作为项目独立模块；再用 ADCToolbox 对校准前后结果做旁路比较。

## 2. 证据与状态定义

| 状态 | 本报告含义 |
|---|---|
| VERIFIED | 有本地源码、具体行号或可复现实验直接支持；结论仅限于声明的范围。 |
| PARTIAL | 部分证据成立，但存在模型边界、未覆盖条件或只能支持趋势。 |
| GAP | 缺少必要源码、commit、测试、实测或跨域接口证据，不能作工程结论。 |
| CONTRADICTED | 现有代码/证据与目标声明直接冲突。 |

本报告不把“全仓库 pytest 通过”自动解释为校准准确性证明；校准准确性必须另外有可观测性、物理标尺、独立 train/test、残差和 corner/Monte Carlo 证据。

## 3. 来源、commit、许可与 fork 边界

### 3.1 本地 upstream：VERIFIED

审计命令：

    git -C C:\Users\Administrator\Desktop\ADCToolbox_EVAL_20260728\upstream status --short --branch
    git -C C:\Users\Administrator\Desktop\ADCToolbox_EVAL_20260728\upstream log -1 --format=fuller
    git -C C:\Users\Administrator\Desktop\ADCToolbox_EVAL_20260728\upstream remote -v

观测结果：

- 工作树：main...origin/main，无未提交修改；
- upstream remote：https://github.com/Arcadia-1/ADCToolbox.git；
- HEAD：a8995cf4faf73dde9918589bfeb866c6a77db12d；
- commit message：Restore full-calibration ENOB bit sweep；
- commit date：2026-07-09T09:29:41+08:00；
- Python package version：python/src/adctoolbox/__init__.py:46 为 0.9.1。

### 3.2 用户指定 fork：GAP

审计命令：

    git ls-remote https://github.com/defineiocc02/ADCToolbox.git HEAD refs/heads/main

本次返回：fatal: unable to access ... Recv failure: Connection was reset。本地 upstream checkout 的 remote 也只指向 Arcadia upstream，没有 defineiocc02 的本地 remote 或独立 fork checkout。因此本报告不能确认 fork 当前 HEAD、fork commit、fork 相对 upstream 的 diff、fork 的分支保护状态或 fork 的 CI 状态。

这不是说 fork 一定有改动，而是说本 checkpoint 没有网络证据，不能把 upstream commit 当作 fork commit。后续应保存 fork URL、fork HEAD SHA、upstream base SHA、git diff --stat、git diff --name-status、fork LICENSE/COPYING 和 fork CI 证据。

### 3.3 许可：VERIFIED（限本地 checkout）

- 根目录 LICENSE:1-20 声明 MIT；
- python/LICENSE:1-20 也声明 MIT；
- 许可证要求在复制或大段分发时保留 copyright 与许可文本；
- 本地 checkout 的许可不自动证明用户 fork 没有额外文件、第三方数据或额外许可证。fork 许可仍是 GAP。

## 4. 三轮独立审查

### Pass 1：源码/API 审查

Pass 1 状态：VERIFIED（工具箱行为）/ GAP（片上算法替代）。

#### 4.1 calibrate_weight_sine 的真实数学角色

源码：python/src/adctoolbox/calibration/calibrate_weight_sine.py:30-41、43-121、140-264。

输入是 (N_samples, M_bits) 的 0/1 bit matrix，或者多个 dataset 的 list。函数把 weighted bit sum 拟合到正弦参考：

    y[n] = sum_m w_m b_m[n] + d_k

并把参考写成归一化的正弦/余弦基函数及可选谐波。它把基波的一个 quadrature coefficient 固定为 1，再由最小二乘估计权重、DC 和其余正交分量。源码 calibrate_weight_sine.py:207-215 调用固定频率 solver，_lstsq_solver.py:61-100 比较 cosine=1 与 sine=1 两种基准，选残差较小者。

因此它识别的是：

- 一个外部已知或可估计输入正弦下的 bit-column 线性组合；
- 以 solver_unit_sine 为基础的相对权重；
- 可再通过 scale_calibration_output 变换到指定线性参考尺度。

它不是：

- 6-bit LSB reference DAC 对单个高位电容的 P/N 模拟测量；
- comparator offset cancellation；
- 32 对 P/N 样本的片上平均；
- bit6 到 bit19 的递归 shadow register 更新；
- b18/b19 protection 的开关控制；
- VCM 预充电、采样、DAC settling、comparator reset 或异步 SAR 时序。

#### 4.2 full API 与 lite API：PARTIAL

full API 的签名在 calibrate_weight_sine.py:30-40，顶层导出在 python/src/adctoolbox/__init__.py:181-189。它支持多 dataset、频率策略、频率细化、谐波 nuisance、rank patch 和详细 metadata。

lite API 在 calibrate_weight_sine_lite.py:6-9。它只接受一个 bit matrix 和一个频率，构造 [bits, DC, sin] 设计矩阵，以 cosine=1 为前提使用 scipy.linalg.lstsq，然后以 sqrt(1+sin_coeff**2) 归一化并做极性修正（calibrate_weight_sine_lite.py:24-46）。

工程选择：

- calibrate_weight_sine：只用于独立外部 baseline、训练/测试交叉校准、数值趋势研究；
- calibrate_weight_sine_lite：只用于已知频率且设计矩阵良好时的快速对照；
- 二者都不能作为 RTL golden model，更不能产生本项目的 w_wr_en/w_wr_addr/w_wr_data 时序。

#### 4.3 rank-deficiency patch：PARTIAL

源码：_patch_rank_deficiency.py:35-49、61-126、128-185。

实现先把 bit matrix 与 DC 列合并检查 rank；若有缺秩，则：

1. 丢弃常量 bit 列；
2. 保留增加 rank 的列；
3. 对线性相关列用 Pearson correlation 接近 ±1 的列进行合并；
4. 以 nominal weight ratio 重建原始 bit 维度；
5. 对不可观测列给出 warning，返回权重为 0。

该 patch 对外部 identification 很有用，但不能被解释为恢复了物理信息。尤其要注意：

- 依赖的是 capture 中的可观测 bit activity，不是 CDAC 的真实电容值；
- 相关性阈值为 abs(abs(correlation)-1.0) < 1e-3，对一般线性依赖但非 ±1 correlation 的列可能无法映射；
- 丢弃常量列后返回 0 只是“本次 capture 不可识别”，不是该 bit 的物理权重为 0；
- 这正好与片上校准相反：片上算法必须通过专门的 LSB reference measurement 使目标 bit 可观测，而不是把不可观测 bit 丢掉。

#### 4.4 数值 conditioning：VERIFIED（实现存在）/ PARTIAL（高精度适用性）

源码：_scale_columns_for_conditioning.py:4-32、34-74。

它按每列最大值的十进数量级缩放 bit columns，再在结果端恢复。对 0/1 bit matrix 通常没有显著量级差异；对 merged/weighted effective columns 则可减少尺度差异。solver 使用 scipy.linalg.lstsq，没有把 condition number、singular values、residual rank 作为硬性 pass/fail 门槛。

可用的诊断函数是 diagnose_calibration_matrix，源码 diagnose_calibration_matrix.py:8-35 说明它只做 diagnostic，不拒绝输入、不改变 calibration behavior。因此行为模型必须把 rank、condition、bit activity 和 recovered weight shape 作为独立验收项，而不是仅看函数没有抛异常。

#### 4.5 频率估计和 refinement：PARTIAL

full API 的单位检查在 calibrate_weight_sine.py:124-138：显式频率大于 0.5 会报错，要求传 normalized Fin/Fs。频率策略在 :171-215 选择 Python 或 MATLAB 风格粗估计，再进入 _solve_weights_searching_freq。

Python 粗估计源码 _estimate_frequencies.py:62-119：按 bit toggle 排序，取两组候选 bit 重构信号，调用 spectrum/estimate_frequency 选优。源码头部 :4-8 已记录已知问题，包括短数据、某些点的二次谐波误判和 Nyquist 失败。

MATLAB 风格粗估计源码 _estimate_frequencies.py:122-174：对前若干 nominal reconstructed prefixes 估计频率并取 median。它提高了 Python/MATLAB 复现一致性，但仍然是粗估计，不是异步 SAR 时钟或采样相位的建模。

频率细化源码 _lstsq_solver.py:186-366：根据当前频率构造 harmonic derivative columns，联合求权重、DC、harmonic 和频率增量。风险包括：

- 非相干输入、短 record、错误初值时可能收敛到错误局部解；
- max_iter 与 reltol 是数值终止条件，不是物理频率锁定证明；
- 多数据集模式要求共享 bit weights，但允许每个 dataset 独立频率；
- 细化结果必须通过独立 test capture 验证，不能用 training residual 作为唯一证据。

频率 API find_coherent_frequency 在 fundamentals/frequency.py:12-60 支持 adc_odd、nearest_coprime 和 matlab_findbin。本项目应固定记录 fs、n_fft、target frequency、实际 coherent bin、policy，避免把 Hz 误传为 normalized frequency。

#### 4.6 harmonic handling：VERIFIED（语义）/ PARTIAL（误用风险）

calibrate_weight_sine 的 docstring :45-55、:83-89 明确：高次谐波是 fitted reference/nuisance terms，可以避免 source/test-chain harmonics 污染权重估计，但不会从 calibrated_signal 中删除这些谐波。返回的 snr_db/enob 在 harmonic_order>1 时是扣除 fitted reference 后的 residual metric，不是 ADC FFT 的动态 SNDR/ENOB（:99-121）。

以下说法是 CONTRADICTED：

    harmonic_order=5 -> ADC harmonic distortion 已被校准消除
    cal[snr_db] -> 论文中的最终动态 SNDR
    cal[error] 很小 -> 片上 comparator/VCM/SRM 噪声已被解决

#### 4.7 weight scale、offset 和返回值：VERIFIED（API）/ GAP（项目 Q8 对齐）

full API 返回 dict，主要字段由 calibrate_weight_sine.py:99-121 和 _post_process.py:94-105 定义：

    weight
    offset
    calibrated_signal
    ideal
    error
    refined_frequency
    snr_db
    enob
    scale_convention = solver_unit_sine

_post_process.py:39-40 计算 DC offset，:83-92 做极性修正。scale_calibration_output.py:14-59 允许使用直接 scale、target weight sum 或 target sine peak；比例指标保持不变。

关键风险：target_weights 的 scale 是按 sum(target_weights)/sum(result[weight]) 得到（scale_calibration_output.py:85-105），这是一个整体线性尺度，不是逐 bit 的 Q8 physical mapping。它不能自动证明：

    toolbox weight[i] == sar_reconstruction.weight_ram[i]
    toolbox offset == RTL offset convention
    toolbox signed output == RTL differential +/- sum convention
    toolbox residue == RTL Q8 SRM residue

本项目应将 ADCToolbox 的权重作为浮点参考，再由项目自己的明确 contract 完成 Q8 量化、饱和、舍入和 write-back。不能把 solver output 直接 cast 到 w_wr_data。

#### 4.8 物理 cap-to-weight：PARTIAL

源码：fundamentals/convert_cap_to_weight.py:13-50、51-112。

函数支持 caps_bit/caps_bridge/caps_parasitic，按 LSB-to-MSB 迭代等效负载、bridge attenuation 和 normalized bit weights，并返回 (weights, c_total)。输入/输出 order 可通过 input_order/output_order 指定。

可用于：

- 从真实 schematic/PEX 提取的 Cd/Cb/Cp 生成有效权重；
- 检查 LSB-to-MSB 与 MSB-to-LSB 顺序；
- 将物理 CDAC 数值送入 SAR forward model。

不能用于：

- 把 reconstruction-domain proxy table 伪装成 physical capacitor array；
- 自动建模 bottom-plate parasitic、switch Ron、VCM、charge injection、reference settling、layout coupling；
- 从单个 normalized weight vector 反推出唯一物理电容拓扑。

实现只严格检查数组长度和 order；对负数、NaN/Inf 等物理非法输入没有完整的统一硬校验，出现 c_node_total == 0 时直接跳过（:79-84）。因此物理模型入口必须由项目 wrapper 先做 finite/non-negative/shape/单位检查。

### Pass 2：tests、examples 与 numerics 审查

Pass 2 状态：VERIFIED（指定 unit tests）/ PARTIAL（准确性证明）。

#### 4.9 已运行测试

使用已有虚拟环境，不安装依赖、不写 upstream 源码，并关闭 pytest cache：

    $py = "C:\Users\Administrator\Desktop\ADCToolbox_EVAL_20260728\envs\upstream-main\Scripts\python.exe"
    & $py -m pytest -p no:cacheprovider --basetemp "$env:TEMP\adctoolbox-audit-20260830-6" tests/unit/calibration tests/unit/test_cap2weight.py -q

结果：

    62 passed, 6 deselected, 1 xfailed, 13 warnings in 36.56s
    EXIT=0

定向子集也运行过：

    39 passed, 1 xfailed, 8 warnings in 22.69s

覆盖内容包括：full/lite calibration、自动频率、MATLAB/Python frequency policy、harmonic nuisance、rank patch、conditioning、scale output、diagnose 和 cap-to-weight。

警告不是失败，但应保留在证据链中：

- fit_sine_4param did not converge in 1 iterations 出现在频率估计测试；
- scale test 中 declared [0,1] 但输入范围达到约 [0.020374,2.01998]，说明 scale/满量程声明必须由调用方一致配置。

#### 4.10 数值 smoke test

在 envs/upstream-main 中直接调用公开 API，生成 12-bit + duplicated redundant bit 的 SAR capture：

    adctoolbox version: 0.9.1
    capture shape: (4096, 13)
    full weight length: 13
    lite weight length: 13
    scale_convention: adc_reference_scale
    all returned weights finite: True
    relative weight error against nominal target: 2.0789e-4
    rank: 13
    uncalibrated nominal SNDR: 72.10 dB
    calibrated test reconstruction SNDR: 73.85 dB

该实验只说明公开 API 可以运行，且在一个低阶合成例中能改善重构；它不是本项目 16-bit 结果，也没有包括 VCM switching、SRM residue、P/N averaging 或 top-bit protection。因此该数值结论评级为 PARTIAL。

#### 4.11 tests 的覆盖边界

| 属性 | 状态 | 原因 |
|---|---|---|
| 真实 split/bridge CDAC 的 PEX 权重可识别 | GAP | 没有本项目 schematic/PEX truth 对照。 |
| 20-decision、14 MSB + 6 LSB reference 的片上递归校准 | GAP | toolbox calibration 是外部 sine-fit。 |
| P/N offset cancellation 与 32 pairs | GAP | 无片上 comparator/DAC measurement FSM。 |
| b18/b19 protection | GAP | rank patch 不等于 top-bit protection。 |
| Q8 quantization、rounding、saturation 与 RTL bit-exact 一致 | GAP | toolbox 输出为浮点 solver scale。 |
| SRM 22 decisions、inverse-normal LUT 与本项目 residue | GAP | toolbox 没有本项目 SRM contract。 |
| 16-bit full-scale、INL/DNL、missing code、PVT/Monte Carlo yield | GAP | 既有测试不是本项目完整 silicon model。 |

#### 4.12 examples、CI、LICENSE：PARTIAL

README.md:170-183 给出 digital calibration 示例，但示例只展示外部 calibrate_weight_sine 与 analyze_spectrum 的使用。python/src/adctoolbox/examples/05_debug_digital/ 中有 mismatch、weight scaling 和 sine calibration 示例，可以作为行为模型 API 模板。

.github/workflows/ci.yml 的 active job 主要运行 models、spectrum、oversampling unit tests 和若干 basic/spectrum/signal/toolset examples；digital-debug example block 在当前文件中是注释状态，不能把 CI 绿色解释为数字校准全流程已验证。

这也说明父任务应运行项目自己的独立行为模型测试，不应只依赖 ADCToolbox CI。

### Pass 3：项目集成、目标误用和 adversarial 审查

Pass 3 状态：PARTIAL；把 toolbox 当片上主校准属于 CONTRADICTED。

#### 4.13 与本项目 on-chip calibration 的边界

项目 RTL：

- Digital_process/Digital_process.srcs/sources_1/new/sar_calib_ctrl_serial.sv:49-75 定义 CAP_NUM=20、AVG_LOOPS=32、MAX_CALIB_BIT=5、REF_WEIGHT_LSB=256 和 P/N DAC force / comparator / weight write-back 接口；
- sar_calib_ctrl_serial.sv:244-260 在 reset 时加载 bit0..5 reference weights；
- sar_calib_ctrl_serial.sv:279-301 执行 P/N SAR search；
- sar_calib_ctrl_serial.sv:305-315 对 SAR code 做 serial accumulation；
- sar_calib_ctrl_serial.sv:322-340 做 averaging、递归 shadow-weight update 和 write-back。

这与 ADCToolbox 的关系是：

    项目片上 calibration FSM  -> 生成/更新真实 Q8 calibrated weights
    ADCToolbox sine-fit        -> 读出一段 raw bit capture 后的独立外部估计 baseline
    ADCToolbox metrics         -> 对片上校准前后输出进行旁路分析

二者可以比较校准趋势，但不能互换。toolbox sine-fit 不知道 dac_p_force/dac_n_force 的物理含义，也不知道一次 P/N pair 是怎样通过 VCM 和 comparator 产生的。

#### 4.14 与 reconstruction/SRM 的标尺风险

sar_reconstruction.sv:46-70 定义 20-bit raw input、Q8 FRAC_BITS=8、16-bit signed output 和 weight write interface；:78-90 使用 weight RAM 并支持同步写入；:101-173 使用 4x5 partial sums；:201-235 做 /2、SRM injection、rounding、saturation。

srm_residue_estimator.sv:44-47 定义 DECISION_COUNT=22、FRAC_BITS=8；:67-74 明确当前 LUT 只按 22 decisions/Q8 验证；:145-152 在接受完 22 个 decision 后输出 residue。

所以任何行为模型必须分别保留三个尺度：

1. analog decision/voltage domain；
2. normalized floating reconstruction domain；
3. RTL Q8 integer domain。

禁止直接做：

    w_rtl = np.asarray(cal[weight], dtype=np.int32)

正确做法是先定义目标 contract，例如 1 output-code LSB = 256 Q8 units，再验证 sum/differential /2 / FRAC_BITS / saturation 与 RTL 完全一致，并保存量化误差。

#### 4.15 允许复用的 ADCToolbox API contract

行为级模型可依赖如下冻结接口：

| 阶段 | 允许 API | 必须记录 |
|---|---|---|
| 物理 CDAC | convert_cap_to_weight | Cd/Cb/Cp 单位、输入/输出 order、归一化方式、返回 c_total。 |
| SAR forward | sar_ideal_weights、sar_apply_cap_mismatch、sar_convert | analog weights、cap units、seed、quant_range、noise 参数。 |
| 外部 baseline | calibrate_weight_sine | train capture、normalized freq、harmonic_order、frequency policy、rank metadata。 |
| 快速 baseline | calibrate_weight_sine_lite | 仅已知频率/良好 conditioning；不能当主结果。 |
| 尺度恢复 | scale_calibration_output | scale source、target weights 或 target sine peak、scale factor。 |
| 频谱 | find_coherent_frequency、analyze_spectrum/compute_spectrum | fs、N、actual bin、window、side bins、OSR、max harmonic、full-scale range。 |
| 静态线性 | compute_inl_from_ramp/analyze_inl_from_ramp | 线性 ramp、code range、endpoint policy、exclude endpoints、missing codes。 |
| 诊断 | diagnose_calibration_matrix、analyze_weight_radix、analyze_overflow | rank/condition、bit activity、weight shape、overflow。 |

#### 4.16 明确禁止的误用

1. 禁止把 calibrate_weight_sine 作为 6-bit LSB reference + P/N + recursive foreground calibration 的实现；
2. 禁止把 cal[snr_db]、cal[enob] 直接报告为最终 ADC FFT SNDR/ENOB；
3. 禁止把 harmonic_order>1 解释为 ADC harmonic distortion 已消除；
4. 禁止把 solver_unit_sine 的 floating weight 直接当作 RTL Q8 w_wr_data；
5. 禁止用 scale_calibration_output(target_weights=...) 代替逐 bit fixed-point contract；
6. 禁止把 convert_cap_to_weight 的输出当作包含版图寄生、开关非线性和 VCM 时序的完整 analog model；
7. 禁止用正弦输入的粗 histogram helper 冒充正式 ramp INL/DNL；
8. 禁止用 512 点输出声称完成 16-bit 高动态范围 FFT。512 点可以做 smoke/接口检查，94 dB 级频谱应使用至少 8192 点，推荐 65536 点并固定 coherent bin；
9. 禁止把同一 capture 同时用于 sine-fit training 和最终性能结论而不说明 optimistic bias；
10. 禁止把软件 Monte Carlo 样本数解释为 silicon yield，除非建立明确的统计模型和 confidence interval。

## 5. 独立行为模型应如何调用工具箱

本 checkpoint 不新增行为模型文件；以下是给父任务实现时必须遵守的结构化 contract。

### 5.1 推荐数据流

    physical Cd/Cb/Cp or explicit project truth table
            |
            v
    convert_cap_to_weight  ----> analog effective weights
            |
            +--> inject declared mismatch / PVT / dynamic error
            |
            v
    sar_convert(vin, actual_analog_weights, ...)
            |
            +--> raw_bits_train -- calibrate_weight_sine -- baseline weights only
            |
            +--> raw_bits_test  -- project on-chip P/N recursive model -- Q8 weights
            |
            v
    sar_reconstruct / project RTL-equivalent reconstruction
            |
            +--> analyze_spectrum / compute_spectrum
            +--> compute_inl_from_ramp
            +--> overflow/radix/bit activity diagnostics

片上主模型应单独实现：

    measure_weight_pn(target_bit, lsb_reference, comparator_model)
    average_32_pairs()
    recursive_shadow_update(bit6_to_bit19)
    protect_top_bits_b18_b19()
    quantize_to_q8_and_write_back()

ADCToolbox 只在主模型旁边提供输入生成、forward conversion、独立 sine-fit baseline 和 metrics。

### 5.2 最小 train/test 验证矩阵

| Case | train | test | 主断言 |
|---|---|---|---|
| Ideal binary | coherent sine | 独立 coherent sine | toolbox/项目重构在理想尺度下 bit-exact 或误差低于 0.5 LSB。 |
| Physical split CDAC | Cd/Cb/Cp truth | 独立 frequency/phase | convert_cap_to_weight 与 SAR forward 的 order/normalization 一致。 |
| Static mismatch, no noise | calibration stimulus | separate ramp + sine | 片上 recursive calibration 后权重误差、INL/DNL、SNDR 均改善；不能只看 sine residual。 |
| P/N offset | fixed comparator offset | independent capture | P/N pair cancellation 对 offset 有明确残差上界。 |
| 32-pair averaging | 1/2/4/8/16/32 pairs | independent capture | 随机 measurement error 近似按 1/sqrt(N) 下降，且和 RTL counter 语义一致。 |
| top-bit protection | b18/b19 extreme codes | ramp/full-scale sine | 不发生 over-range、符号翻转或不可恢复 code gap。 |
| SRM | 22 decisions | sine + residue | residue count/index/LUT/Q8 与 RTL 一致；SRM on/off 只改变声明的 correction term。 |
| external baseline | ADCToolbox train | project test | sine-fit 结果仅作为旁路识别 baseline，不与 on-chip result 混名。 |
| 512-point smoke | 512 samples | 512 samples | 仅检查接口、valid、码流和粗指标；不作 16-bit FFT signoff。 |
| performance | 8192/65536 samples | 独立 frequency/phase | 报告 SNDR/SFDR/THD/ENOB，附 window/bin/full-scale/seed。 |

## 6. 关键风险清单

### P0

1. **片上主校准误替换**：把 external sine-fit 当成 on-chip calibration。状态：CONTRADICTED；必须保持项目 P/N recursive FSM。
2. **Q8 标尺断裂**：toolbox solver scale、normalized weights、RTL signed differential sum 和 srm_residue 没有自动对齐。状态：GAP。
3. **physical topology 不足**：若只使用 effective proxy vector，不能声称真实 split/bridge CDAC。状态：PARTIAL。
4. **fork provenance 不闭合**：defineiocc02 fork HEAD/diff 无法由本次网络命令确认。状态：GAP。
5. **独立 test 不足**：训练残差不是 16-bit dynamic performance；必须独立 capture 验证。状态：PARTIAL。

### P1

1. 频率 normalized/Hz 混用；
2. auto frequency 在短 record、Nyquist、二次谐波下误锁；
3. harmonic nuisance 指标被误读为 FFT SNDR/THD；
4. rank patch 将不可观测 bit 置零后被误读为物理权重为零；
5. convert_cap_to_weight 输入非法值未由 wrapper 统一拒绝；
6. calibrate_weight_sine_lite 的输入 shape、finite、负频率和 conditioning 检查较弱；
7. scale_calibration_output 只能整体 scaling，不能完成 per-bit Q8 quantization；
8. ramp INL/DNL 的统计基准依赖线性均匀 ramp 与 code range；
9. spectrum 默认 window/side-bin 与项目旧 TB 若不统一，会产生不可比指标。

### P2

1. 固定第三方 commit、Python 版本、NumPy/SciPy 版本和 PYTHONPATH；
2. 保留 upstream LICENSE 与 fork license 证据；
3. 把 calibration metadata、seed、frequency policy、scale factor、rank patch metadata 写入 manifest；
4. 将 toolbox baseline 与 on-chip 主算法在文件名、图例、CSV case name 中分开；
5. 每次论文结果同时保留 raw bits、calibrated weights、metrics config 和 git SHA。

## 7. 对本项目的最终裁决

| 目标 | 裁决 |
|---|---|
| 用 ADCToolbox 做 SAR forward model | VERIFIED，但必须声明其不含 settling/metastability/charge injection/PVT。 |
| 用 convert_cap_to_weight 连接真实 Cd/Cb/Cp | PARTIAL，需输入真实物理拓扑和 wrapper validation。 |
| 用 calibrate_weight_sine 做外部 baseline | VERIFIED，必须独立 train/test、记录 scale 和 frequency。 |
| 用 calibrate_weight_sine 替代本项目片上校准 | CONTRADICTED，禁止。 |
| 用 toolbox 直接产生 w_wr_data | GAP，必须由项目 Q8 contract 和量化检查完成。 |
| 用 toolbox metrics 分析项目输出 | VERIFIED/PARTIAL，需固定 FFT、window、full-scale 和 code convention。 |
| 声称本项目 on-chip self-calibration 已被 ADCToolbox 证明 | GAP，尚无 P/N/recursive/top-bit/SRM 闭环证据。 |

## 8. 交付给父任务的实现准则

1. 行为级模型必须把本项目 lsb_ref_pn_recursive_calibration 作为主校准模块；不得 import 或包裹 sine-fit 充当主逻辑。
2. ADCToolbox 只能作为独立旁路：生成 stimulus、执行 SAR forward、执行外部 sine-fit baseline、执行频谱和静态线性指标。
3. 任何报告表格至少分成 ONCHIP_PN_RECURSIVE、ADCTOOLBOX_SINE_BASELINE、ORACLE_ACTUAL_WEIGHT、NOMINAL_UNCALIBRATED 四类，避免结果混淆。
4. 量化前保存浮点权重，量化后保存 Q8 权重、每 bit 量化误差、sum error、saturation count 和 output code convention。
5. 片上行为模型必须覆盖 P/N offset、32-pair averaging、b18/b19 protection、SRM 22-decision residue，并用独立 test capture 做验证。
6. 512 点只作为 bring-up/smoke；正式 16-bit 动态结论使用更长 record，并把频率、bin、window 和 harmonic exclusion 写入 manifest。
7. fork 网络证据补齐前，所有结果必须标注为基于 upstream a8995cf4... 的冻结版本，不得标注为 fork HEAD 结果。

**最终一句话**：ADCToolbox 值得纳入本项目行为级验证链，但它是“外部识别与测量工具”，不是“片上自校准算法实现”；本项目的可信主线必须由 6-bit LSB reference、P/N 32-pair averaging、bit6..19 recursive update、top-bit protection、SRM 和 RTL/Q8 contract 自己闭合。
