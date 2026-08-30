# 16 位 SAR 片上前景自校准与 ADCToolbox 独立行为验证报告

## 1. 文档控制

| 项目 | 内容 |
|---|---|
| 报告日期 | 2026-08-30 |
| 工程根目录 | `D:/ReedZhao/Document/ADC_Digital_PROCESS/proc_vivado/sar_adc_v3` |
| Git 基线 | `main`，开始审查时 HEAD 为 `a2ee34e7bdfa7ded19379c66962165a2f7e30db4` |
| 主算法 | 本项目 16 位 SAR 片上 P/N 递归前景自校准 |
| 输出分辨率 | signed 16 bit |
| SAR 判决数 | 20 decisions，其中包含冗余判决，不代表 20 位 ADC |
| 固定点格式 | signed Q8，`256 = 1 final-code LSB` |
| LSB reference | bit0 至 bit5，共 6 个参考权重 |
| 校准目标 | bit6 至 bit19，共 14 个权重 |
| 校准平均 | 每目标位 32 组 P/N pair，即 64 次标量比较测量 |
| SRM | 同一 residue 下 22 次统计判决，count-to-Q8 LUT |
| ADCToolbox | 0.9.1，审计 commit `a8995cf4faf73dde9918589bfeb866c6a77db12d` |
| 证据等级 | 行为级验证，不是 AMS、PEX、GDS 或硅片签核 |

## 2. 首要纠偏：这是 16 位片上自校准

本实验的主对象不是 ADCToolbox 的正弦拟合算法，也不是 20 位 ADC。

正确架构定义为：

```text
16-bit signed ADC output
    <- 20 redundant SAR decisions
    <- 20 physical/effective decision weights
    <- 6 trusted LSB reference weights
    <- recursively calibrate 14 higher weights
```

其中 20 是冗余 SAR 的判决维数，16 才是最终有效输出宽度。多出的判决用于非二进制冗余、split-CDAC 和误差恢复。当前项目的片上校准数据流为：

```text
6-bit LSB reference section
    -> target bit6
    -> P/N polarity searches
    -> 32-pair averaging
    -> Q8 shadow weight update
    -> target bit7 ... bit19 recursively
    -> b18/b19 protected search
    -> synchronous weight writeback
    -> normal 20-decision reconstruction
    -> optional 22-decision SRM residue correction
    -> signed 16-bit output
```

ADCToolbox 的 `calibrate_weight_sine()` 需要外部正弦激励和一整段 raw-bit capture，通过全局最小二乘识别权重。它只在本报告中作为旁路参考，名称固定为：

```text
ADCTOOLBOX_SINE_EXTERNAL_BASELINE
```

它不能替代片上 P/N 自校准 FSM，也不能直接生成 RTL 的 `w_wr_en/w_wr_addr/w_wr_data` 时序。

## 3. 代码组织与来源关系

### 3.1 本次新增实验包

```text
analysis/self_cal_adctoolbox_behavioral_20260830/
├── README.md
├── requirements.txt
├── THIRD_PARTY_NOTICES.md
├── run_self_cal_behavioral.py
├── test_self_cal_behavioral.py
├── SELF_CAL_BEHAVIORAL_REPORT_CN.md
├── reviews/
│   └── REVIEW_01_ADCTOOLBOX_AUDIT_CN.md
└── outputs/
    ├── summary.json
    ├── metrics.csv
    ├── weights.csv
    ├── srm_noise_ablation.csv
    ├── calibration_trace.json
    ├── run_log.txt
    ├── fig_weight_error.png
    ├── fig_spectrum_compare.png
    ├── fig_inl_compare.png
    ├── fig_calibration_trace.png
    └── fig_srm_noise_ablation.png
```

### 3.2 复用的项目模块

主脚本没有重新发明第二套自校准逻辑，而是直接调用当前工程已有、与 RTL 对齐的行为实现：

| 文件 | 本实验复用内容 |
|---|---|
| `analysis/full_sar_behavioral_20260729/full_sar_model.py` | P/N search、32-pair average、bit6..19 recursion、b18/b19 protection、20-decision conversion、SRM LUT、Q8 reconstruction |
| `analysis/physical_cdac_mismatch_20260729/physical_cdac.py` | 6+4+5+5 segmented CDAC、bridge/parasitic network、physical-cap mismatch、effective Q8 weight extraction |
| `Digital_process/.../sar_calib_ctrl_serial.sv` | 片上自校准 RTL source of truth |
| `Digital_process/.../srm_residue_estimator.sv` | 22-decision SRM count-to-Q8 source of truth |
| `Digital_process/.../sar_reconstruction.sv` | signed differential sum、`/2`、Q8、rounding、saturation source of truth |

这种组织方式把“算法实现”和“实验编排”分开。新脚本负责构造物理样本、建立 train/test capture、选择 decoder、调用指标函数和保存证据；片上校准算法仍由项目自己的模块实现。

## 4. 数学原理

### 4.1 20 次冗余判决到 16 位输出

设 raw decision 为 `b_i in {0,1}`，signed decision 为：

```text
s_i = 2*b_i - 1 in {-1,+1}
```

物理 CDAC 的 Q8 权重为 `W_i`，则 signed differential weighted sum 为：

```text
S_Q8 = sum(i=0..19, s_i * W_i)
```

重构 RTL 中存在显式 `/2`，因此不含 SRM 时：

```text
D = sat16(round((S_Q8 / 2) / 2^8))
```

加入同单位 residue `R_Q8` 后：

```text
D = sat16(round((S_Q8 / 2 + R_Q8) / 2^8))
```

这里 `W_i` 与 `R_Q8` 都在 Q8 域，`256` 表示一个最终 16 位输出码 LSB。`/2` 来自 `+W/-W` 双边 differential decision，而不是把 20 位 ADC 任意压缩为 16 位。

### 4.2 P/N offset cancellation

目标权重为 `W_k`，参考 DAC 搜索得到的等效幅度为 `M`。抽象比较器观测可写成：

```text
P phase: e_P = +W_k - M_P + V_os + n_P
N phase: e_N = -W_k + M_N + V_os + n_N
```

P/N 相位互换 target/reference 极性。若用带符号的测量结果表示，经典估计式为：

```text
W_hat_k = (D_k,+ - D_k,-) / 2
```

当前 RTL 的 phase-N search 已经把反极性结果重新编码为正幅度 `meas_n`，因此实现形式为：

```text
W_hat_k = average(meas_p + meas_n) / 2
```

两种写法只是 phase-N 的符号约定不同。理想固定 comparator offset 在两相中相同，组合后被抵消；随机噪声则通过平均减小。

### 4.3 32 对 P/N 平均

每个 target bit 进行 `M=32` 组 P/N pair。RTL 行为对应：

```text
accumulator += meas_p + meas_n
result_q8 = round(accumulator / (2*M))
```

默认值下：

```text
2*M = 64
result_q8 = (accumulator + 2^5) >> 6
```

若每次标量测量噪声独立且标准差为 `sigma_n`，P/N pair 后再平均的理想标准差为：

```text
sigma(W_hat) = sigma_n / sqrt(2*M) = sigma_n / 8
```

这个推导只适用于独立零均值噪声。reference-DAC 静态误差、settling bias、charge injection 和 correlated noise 不会自动按 `1/sqrt(N)` 消失。

### 4.4 递归权重更新

bit6 的测量依赖 bit0..5 的参考权重；bit7 的搜索可以复用已经校准的 bit6；随后逐位递归到 bit19：

```text
shadow[0:5] = nominal LSB reference weights
for k = 6..19:
    shadow[k] = calibrate_one_target(k, shadow[0:k-1])
```

这也是为什么各 bit 不能完全并行独立估计。前一低位的偏差会向后传播。当前参考芯片出现约 1.37% 的整体增益修正，主要反映低 6 位 reference anchor 与物理单位权重之间的比例差。整体增益不等于非线性，因此报告同时给出 direct RMSE 和 gain-aligned RMSE。

### 4.5 最高两位保护

对 bit18 和 bit19，低位 reference range 可能不足以直接覆盖目标幅度。当前项目采用 protection compensation：

- 校准 bit18 时强制加入 bit17；
- 校准 bit19 时强制加入 bit17 和 bit18；
- 搜索结果再补回相同保护权重。

保护策略避免目标权重超出低位搜索范围，但必须在真实 VCM/reference switching path 上验证 headroom、settling 和 comparator polarity。行为模型只能证明数字求值方式一致。

### 4.6 22-decision SRM

normal SAR 完成后保留 analog residue `r`。在相同 residue 下做 22 次含统计噪声的 comparator decision：

```text
K = sum(j=1..22, decision_j)
p_hat = K / 22
r_hat approximately sigma * Phi_inverse(p_hat)
```

这里的 comparator noise 不是额外叠加到最终数字码上的“坏噪声”，而是把固定 residue 转换成 Bernoulli 概率的观测载体。若单次判断满足：

```text
decision_j = 1  when  r + n_j >= 0
n_j ~ Normal(0, sigma^2)
P(decision_j = 1 | r) = Phi(r / sigma)
```

则 22 次统计得到 `r_hat`，数字输出对 residue 的剩余误差由 `r` 变成 `r-r_hat`。SRM 真正降噪的判据不是“22 次判断本身无噪声”，而是：

```text
E[(r-r_hat)^2] < E[r^2]
```

有限 22 次观察使 `r_hat` 有估计方差，但只要该方差小于未校正 residue/error 的方差，系统总噪声仍会下降。当前 paired experiment 正是直接检查这个不等式，而不是把 stochastic SRM 与无关的另一组 raw conversion 做比较。

实际 RTL 不在线计算 inverse CDF，而使用经过端点处理的 23 项 Q8 LUT：

```text
K in [0,22] -> R_Q8[K]
```

本实验把两种情况分开：

1. `SELF_CAL_Q8_SRM_EXPECTED`：使用期望 count 四舍五入，检查确定性 transfer curve；
2. `SELF_CAL_Q8_SRM_22_STOCHASTIC`：真实抽取 22 次判决的二项计数，检查有限观察数带来的随机损失。

静态 INL/DNL 不能使用随机 SRM，否则相同 input code 会被随机分散并产生伪 missing code。因此两种动态 SRM case 的静态指标都使用确定性 expected-count transfer curve，这一点已经写入代码注释和证据边界。

### 4.7 ADCToolbox 外部正弦拟合

外部 baseline 使用 raw-bit matrix `B`，shape 为 `(N_samples,20)`，以及已知归一化频率 `f_in/f_s`。其基本最小二乘模型为：

```text
B*w + d approximately A*cos(2*pi*f*n) + C*sin(2*pi*f*n)
```

solver 返回 `solver_unit_sine` 尺度。实验随后调用：

```python
scale_calibration_output(result, target_weights=nominal_q8)
```

这只恢复一个全局线性尺度，不证明逐 bit Q8 hardware contract。外部拟合使用 16384 个已知正弦样本并同时观察全部 20 个 bit columns，因此接近 oracle 是合理的；它的激励、存储、矩阵求解和计算量与片上 32-pair 自校准完全不同，不能拿来替代硬件方案。

## 5. ADCToolbox 三轮独立审计

独立 reviewer 对冻结 checkout 完成了三轮审查，完整记录见 `reviews/REVIEW_01_ADCTOOLBOX_AUDIT_CN.md`。

### 5.1 Pass 1：源码与 API

核查了：

- `calibrate_weight_sine` 与 lite 版本的真实数学角色；
- rank-deficiency patch；
- numerical column conditioning；
- normalized-frequency API 与 refinement；
- harmonic nuisance 的正确语义；
- `solver_unit_sine` 与 Q8 的尺度边界；
- `convert_cap_to_weight` 的能力和物理模型限制。

结论是工具箱可以用于外部 identification 和性能分析，但没有 P/N FSM、VCM switching、recursive shadow update、top-bit protection 或 SRM Q8 writeback。

### 5.2 Pass 2：tests、examples 与 numerics

冻结环境中的工具箱测试结果：

```text
62 passed, 6 deselected, 1 xfailed, 13 warnings in 36.56s
```

这个结果证明被选测试范围内 API 可运行，不证明本项目片上算法或真实 split-CDAC 正确。

### 5.3 Pass 3：集成与对抗式误用审查

审查明确禁止：

- 把 sine-fit 称作片上自校准；
- 把 `cal[snr_db]` 当最终 ADC FFT SNDR；
- 把 harmonic nuisance 当作 ADC 失真已经消除；
- 把浮点 solver weight 直接 cast 为 Q8 writeback；
- 把 512 点 smoke 当 94 dB 级 16 位 FFT；
- 把 behavior Monte Carlo 样本数称作 silicon yield。

用户 fork `defineiocc02/ADCToolbox` 的网页可见，但本轮 `git ls-remote` 遇到 connection reset。本地冻结 checkout 的 remote 是 Arcadia upstream，因此可复现结果只能绑定 upstream commit `a8995cf4...`，不能虚构 fork HEAD。

## 6. 实验设计

### 6.1 物理失配样本

使用项目现有 6+4+5+5 segmented-CDAC 物理代理模型。先对 bit capacitor、bridge capacitor、node parasitic 和 comparator input capacitor 施加失配，再求解 capacitance matrix 得到 effective weights，而不是直接对最终权重表任意加百分比。

配置与 chip 17 的实际抽样结果：

| 项目 | 配置或观测值 |
|---|---:|
| Unit-cap sigma 配置 | 1.2% |
| Node-parasitic sigma 配置 | 2.0% |
| Comparator-input-cap sigma 配置 | 2.0% |
| bit-cap 实际 RMS relative error | 0.5808% |
| bit-cap 实际范围 | -1.6150% 至 +1.1332% |
| bridge-cap 实际 RMS relative error | 0.4089% |
| effective-weight 实际 RMS relative error | 0.5919% |
| effective-weight 实际范围 | -1.3873% 至 +0.6412% |

这里的 1.2% 是单位电容 sigma。较大 capacitor 由多个 unit 组成，其 sigma 按 `1/sqrt(N)` 缩小；bridge 和寄生还会把误差相关地映射到多个 effective weights。

### 6.2 失配实验的噪声隔离

为了单独回答“失配能否被自校准消除”，normal conversion 中以下因素全部关闭：

```text
sampling noise                  = 0
normal comparator noise         = 0
normal comparator offset        = 0
reference noise                 = 0
DAC settling error              = 0
```

校准路径仍保留：

```text
calibration comparator offset   = 5.0 LSB
calibration comparator noise    = 0.5 LSB
P/N pairs per target            = 32
```

因此未校准与自校准之间的主要差异来自同一 CDAC mismatch truth 下的数字权重估计，不是 normal-path 噪声开关。

SRM stochastic case 使用 `sigma=0.5 LSB` 的统计判决噪声，因为 inverse-normal residue estimation 必须依靠已知 comparator-noise distribution。这里的随机判决是 residue 的统计观测机制，不是 ordinary conversion path 的噪声源。

必须强调：这组 normal-path 零噪声结果只证明两件事：

1. 片上权重自校准是否能消除 physical-CDAC mismatch；
2. SRM LUT 是否能恢复 segmented/redundant conversion 结束后的 residue 信息。

它**不能**单独证明论文所说的前放/比较器噪声抑制。为此，本轮新增下面的成对带噪声消融实验。

### 6.3 SRM 降噪成对消融

独立配置如下：

```text
capture length                    = 8192 samples
independent noise repeats         = 32
normal comparator noise sigma     = 0.5 LSB
SRM observation noise sigma       = 0.5 LSB
SRM decisions                     = 22
sampling noise                    = 0
reference noise                   = 0
DAC settling error                = 0
input amplitude                   = 0.90 positive full scale
```

每个 repeat 只运行一次带比较器噪声的 20-decision normal SAR conversion。随后：

```text
same raw_bits -> no-SRM reconstruction
same raw_bits -> 22-decision stochastic-SRM reconstruction
```

因此 SRM on/off 的差异不可能来自重新抽取 normal-conversion noise，也不可能来自不同 raw code。脚本逐次检查 expected/stochastic SRM 的 `raw_bits` 完全相同，最终 `summary.json` 记录：

```text
raw_bits_shared_between_srm_on_off = true
```

该实验只隔离 comparator/pre-amplifier decision noise 与 held-residue estimation。它没有实现 split-sampling 的 kT/C cancellation、AZ noise aliasing、前放带宽噪声谱，也不能直接替代论文完整的 `111 -> 38 uVrms` 晶体管级噪声预算。

### 6.4 动态 capture

| Capture | 用途 | N | 目标频率 | 实际 coherent bin/frequency |
|---|---|---:|---:|---:|
| A | 仅供外部 sine-fit baseline 训练 | 16384 | 0.71 MHz | 由脚本写入 `summary.json` |
| B | 所有 decoder 的独立最终测试 | 16384 | 1.13 MHz | 由脚本写入 `summary.json` |

片上 P/N 自校准不使用 capture A。它通过内部 target/reference P/N 测量产生 Q8 weights。A/B 分离只用于防止 ADCToolbox 外部 baseline 在训练数据上自评分。

### 6.5 静态 capture

生成完整 signed 16-bit range 的均匀 ramp，每码 2 个样本：

```text
65536 codes * 2 samples/code = 131072 samples
```

使用 ADCToolbox `analyze_inl_from_ramp()` 做 endpoint-corrected DNL/INL 和 missing-code extraction。全局 gain/offset 与非线性分开处理。

### 6.6 Decoder 矩阵

| Decoder | 权重 | Residue | 目的 |
|---|---|---|---|
| `NOMINAL_Q8_NO_SRM` | nominal | 0 | 未校准失配基线 |
| `NOMINAL_Q8_EXACT_RESIDUE` | nominal | exact physical residue | 判断 residue 能否补救错误权重 |
| `SELF_CAL_Q8_NO_SRM` | 项目 P/N 自校准 | 0 | 单独验证校准消除失配 |
| `SELF_CAL_Q8_SRM_EXPECTED` | 项目 P/N 自校准 | 期望 22-count LUT | 确定性校准+residue 上限 |
| `SELF_CAL_Q8_SRM_22_STOCHASTIC` | 项目 P/N 自校准 | 22 次随机判决 | 有限 SRM observations 的真实波动 |
| `SELF_CAL_Q8_EXACT_RESIDUE` | 项目 P/N 自校准 | exact physical residue | 分离 weight residual 与 SRM LUT error |
| `ORACLE_Q8_NO_SRM` | physical truth | 0 | 分离 redundant residue information |
| `ORACLE_Q8_SRM_EXPECTED` | physical truth | 期望 22-count LUT | 当前 Q8/LUT 上限 |
| `ORACLE_Q8_EXACT_RESIDUE` | physical truth | exact physical residue | 行为模型理论上限 |
| `ADCTOOLBOX_SINE_EXTERNAL_BASELINE` | 外部 sine-fit | 期望 22-count LUT | 非片上旁路参考 |

## 7. 实际编辑、编译与运行记录

### 7.1 新增与修改

本轮只在独立实验包和总审查包中新增文件，没有改写三个核心 RTL。原因是用户已经明确要求核心逻辑不要随意改动，本轮目标是审计与建立可复现行为验证。

主脚本的工业化约束包括：

- 固定 16-bit/20-decision/Q8/32-pair/22-SRM contract；
- 进程稳定 seed；
- train/test 分离；
- decoder 名称强制区分片上与外部 baseline；
- 输出 JSON/CSV/trace/figures；
- shape、finite、raw-bit identity 和 calibration-improvement assertions；
- paired SRM on/off 共用 raw-bit stream，并对 SNDR 与 error-RMS 改善做回归断言；
- headless Matplotlib backend；
- dependency commit 和 module path 写入 summary。

### 7.2 语法编译

```powershell
python -m py_compile run_self_cal_behavioral.py test_self_cal_behavioral.py
```

结果：PASS。

### 7.3 第一次 pytest

第一次运行得到：

```text
3 passed, 1 failed
KeyError: 'frequency'
```

根因：当前 ADCToolbox 0.9.1 的 sine-calibration 返回键是 `refined_frequency`，不是 `frequency`。这与当前本地 `adctoolbox-user-guide` 的 return-key 约定一致。

修复：读取 `result["refined_frequency"]`，并保留 `initial_frequency`。

### 7.4 第一次完整实验

第一次完整实验完成了校准、转换和外部拟合，但在汇总静态结果时失败：

```text
KeyError: 'SELF_CAL_Q8_SRM_22_STOCHASTIC'
```

根因：动态 decoder 有 stochastic SRM case，静态 ramp 故意没有随机 transfer curve。

修复：静态同名 case 明确复用 expected-count SRM transfer curve，并在代码中解释原因。没有通过随机重复填补 static histogram。

### 7.5 最终 pytest

```text
5 passed in 7.09s
```

五项测试分别证明：

1. active contract 是 16-bit、20 decisions、Q8、32 P/N、22 SRM；
2. reference chip 上项目自校准必须降低 gain-aligned weight RMSE；
3. SRM expected/stochastic 模式不得改变原始 20-decision raw bits；
4. ADCToolbox solver 只能以明确外部 baseline 名称运行，输入矩阵为 `(N,20)` 且输出 finite。
5. 带噪声 SRM 成对消融必须保持 raw bits 恒等，并同时改善 oracle/self-cal 的平均 SNDR 与 affine-aligned error RMS。

随后把本包与 `full_sar_behavioral_20260729`、`physical_cdac_mismatch_20260729` 的三个测试文件联合运行：

```text
21 passed in 12.50s
```

这证明新增 SRM 消融没有破坏既有校准、physical-CDAC 和 512-chip revalidation helper 的接口契约。

### 7.6 最终完整运行

最终命令成功退出，完整 stdout 保存在 `outputs/run_log.txt`。生成了 JSON、两个 CSV、五张图和 per-target calibration trace；其中 `srm_noise_ablation.csv` 保存 32 repeats × 5 decoders = 160 条动态记录。

## 8. 结果

### 8.1 16 位理想控制

理论满幅正弦量化 SNDR：

```text
SNDR_ideal = 6.02*16 + 1.76 = 98.08 dB
```

本轮 direct ideal 16-bit quantizer 得到：

```text
SNDR = 98.093 dB
```

两者相差 0.013 dB，证明 stimulus、coherent FFT 和指标尺度能够达到理想 16 位基准。该控制项先通过，随后 mismatch/calibration 结果才具有解释价值。

### 8.2 动态与静态结果

| Decoder | SNDR dB | SFDR dB | ENOB | INL pp LSB | Missing codes |
|---|---:|---:|---:|---:|---:|
| Nominal, no SRM | 61.630 | 66.731 | 9.945 | 108.505 | 1061 |
| Nominal, exact physical residue | 61.632 | 66.726 | 9.946 | 108.505 | 1093 |
| On-chip self-cal, no SRM | 93.433 | 105.547 | 15.228 | 2.732 | 4 |
| On-chip self-cal, expected SRM | 95.437 | 106.870 | 15.561 | 1.909 | 0 |
| On-chip self-cal, stochastic 22 SRM | 94.907 | 107.049 | 15.473 | 1.909 | 0 |
| On-chip self-cal, exact physical residue | 95.441 | 106.867 | 15.562 | 1.865 | 0 |
| Oracle, no SRM | 95.181 | 117.945 | 15.518 | 1.999 | 556 |
| Oracle, expected SRM | 98.020 | 123.807 | 15.990 | 0.000 | 0 |
| Oracle, exact residue | 98.053 | 124.417 | 15.995 | 0.000 | 0 |
| ADCToolbox external sine baseline | 98.026 | 124.978 | 15.991 | 0.837 | 0 |

静态 `INL pp=0` 的 oracle 是该确定性行为模型中 exact physical weight/residue 的数学上限，不代表晶体管 ADC 或硅片会有零 INL。

### 8.3 自校准是否有效

在 normal conversion 零随机噪声、同一 physical mismatch truth 下：

```text
SNDR: 61.630 -> 93.433 dB, +31.804 dB, self-cal only
SNDR: 61.630 -> 95.437 dB, +33.807 dB, self-cal + expected SRM
INLpp: 108.505 -> 2.732 LSB, self-cal only
INLpp: 108.505 -> 1.909 LSB, self-cal + expected SRM
missing: 1061 -> 4 -> 0
```

因此结论明确：

> 在当前 6+4+5+5 physical-CDAC proxy 和 Q8 RTL contract 下，本项目 16 位 P/N 递归片上自校准能够非常显著地消除静态失配造成的非线性和动态失真。

但它还没有完全到达 oracle：self-cal no-SRM 比 exact-residue oracle 低约 4.62 dB；expected SRM 后仍低约 2.62 dB。剩余误差来自有限 6-bit reference、校准搜索量化、Q8 写回、32-pair measurement noise 和有限 SRM LUT，而不是 ordinary normal-conversion noise。

### 8.4 权重误差与全局增益

| 指标 | Nominal | On-chip self-cal | External sine fit |
|---|---:|---:|---:|
| Direct weight RMSE, LSB | 11.071 | 141.263 | 1.304 |
| Gain-aligned weight RMSE, LSB | 9.286 | 0.2286 | 0.0261 |

片上自校准的 gain-aligned RMSE 改善 `40.63x`。Direct RMSE 反而较大不是校准发散，而是整个 calibrated vector 相对 physical truth 存在约 1.369% 的比例差；best alignment factor 为 `1.0136904`。该比例主要由低 6 位 nominal reference anchor 定义。

全局 gain 可以通过系统 gain trim 或数字 normalization 处理；DNL/INL 与 SNDR 更关注权重之间的相对关系。因此 direct RMSE 和 gain-aligned RMSE 必须同时报告，不能只挑一个有利数字。

### 8.5 无噪声 residue-information 对照

```text
Expected SRM increment over self-cal no-SRM = +2.003 dB
Stochastic 22-decision penalty vs expected = -0.530 dB
```

这组数字解释“无普通转换噪声时，为什么不开 SRM 仍会下降”：

- no-SRM case 没有加入 sampling/comparator/reference noise；
- no-SRM 丢失的是 segmented redundant conversion 结束后的 analog residue 信息；
- expected SRM 恢复其中一部分信息；
- 真实 22 次观察存在 finite-count variance，所以比 expected-count 上限低 0.53 dB；
- 这里主要验证 residue recovery，**不应称为论文 SRM 降噪能力验证**；
- 这个数值属于当前 proxy model，不能直接等同论文芯片 SS/SRM on-off 差值。

### 8.6 带比较器噪声的 SRM 降噪结果

32 次独立噪声重复的正式结果如下；每个 repeat 内 SRM on/off 使用相同 noisy raw bits：

| Weight path | No SRM SNDR mean±std | 22-SRM SNDR mean±std | Paired gain mean±std | Error RMS no-SRM -> SRM | RMS reduction |
|---|---:|---:|---:|---:|---:|
| Oracle physical weights | 90.532±0.054 dB | 95.888±0.044 dB | 5.356±0.056 dB | 0.6203 -> 0.3348 LSB | 1.853× |
| Project self-cal weights | 89.716±0.059 dB | 93.888±0.049 dB | 4.172±0.079 dB | 0.6722 -> 0.4158 LSB | 1.617× |

`ORACLE_SRM_EXPECTED_NOISY` 使用期望 count 而非 22 次随机 count，得到 `96.759±0.033 dB`，是相同 LUT 与比较器噪声假设下的 finite-count 上界。真实 22-decision SRM 低于它约 0.87 dB，但相对 no-SRM 仍有明确正收益。

该结果支持以下工程结论：

1. SRM 没有改变正常 20 次 SAR 判决，而是在转换结束后估计 held residue；
2. 22 次 noisy observations 的有限统计误差小于它所消除的 comparator-decision/quantization-residue 误差；
3. 对当前 project self-cal weights，SRM 把平均 SNDR 提高 4.17 dB，方向与论文 SS 已开启时 `89.1 -> 93.7 dB`、约 4.6 dB 的实测趋势一致；
4. 这只是量级和机制上的一致，不能视为论文数值复现，因为当前模型没有 SS kT/C cancellation、AZ aliasing、前放频谱和晶体管噪声预算。

论文中 SS 关闭时，SRM 只把 SNDR 从 85.72 dB 提高到 87.22 dB（1.5 dB），原因是 kT/C noise 仍占主导；这也说明 SRM 不能消除输入源噪声或所有采样噪声。当前成对消融故意将 sampling noise 设为 0，只回答“SRM 对其目标的 comparator/residue 路径是否降噪”。

完整逐 repeat 数据在 `outputs/srm_noise_ablation.csv`，配对图在 `outputs/fig_srm_noise_ablation.png`，配置和分位数在 `outputs/summary.json`。

### 8.7 外部 baseline 为什么更高

ADCToolbox 外部拟合得到 matrix rank `20`、rank-with-offset `21`、condition number `19.45`，没有 rank patch、constant column 或 unmapped bit。它在独立 test frequency 上达到约 98.03 dB。

原因是外部 solver 使用 16384 个已知正弦样本和浮点全局最小二乘，同时估计全部权重；片上方案每 bit 只有 32 对局部比较，受 LSB reference range、Q8、递归传播和硬件开销约束。外部结果是离线 identification 上限，不是片上实现目标。

### 8.8 为什么未校准与校准结果相差三十多 dB

这个跨度经过三组对照后是可解释的，但需要区分“有效”与“完美”。

第一，16 位线性度对大权重的相对误差极敏感。本样本的 effective-weight RMS relative mismatch 为 0.5919%，看起来不大，但按最终 code LSB 衡量，nominal 高 14 位的 gain-aligned weight RMSE 为 `11.099 LSB`，最大误差为 `34.397 LSB`。它形成约 `108.5 LSBpp` 的 INL 台阶，因此 SNDR 落到 61.63 dB 并不违反量化理论。

第二，exact residue 不能修复错误 digital weights：

```text
Nominal, no SRM        = 61.6297 dB
Nominal, exact residue = 61.6319 dB
```

两者只差 0.0022 dB，说明未校准失真主要来自 weight mismatch，而不是 residue estimator。

第三，oracle 权重不开 SRM 已经达到 95.1808 dB，expected SRM 后达到 98.0205 dB：

```text
Oracle residue-information gain = 2.8397 dB
```

这约 2.84 dB 属于当前 segmented/redundant converter 的 residue information；余下从 61.63 到 95.18 dB 的大部分差距属于 weight mismatch。

第四，片上自校准并没有完全达到 oracle：

```text
No SRM:       self-cal 93.4333 vs oracle 95.1808 dB, gap -1.7475 dB
Expected SRM: self-cal 95.4368 vs oracle 98.0205 dB, gap -2.5837 dB
Exact-residue self-cal = 95.4411 dB
```

expected 与 exact residue 在 self-cal weights 下只差 0.0043 dB，说明当前剩余差距主要是片上 weight-estimate residual，而不是 SRM LUT 本身。换言之，自校准非常有效，但还没有把 16 位权重恢复到 oracle 精度。

第五，chip 17 不是证明总体分布的唯一证据。既有 512-chip revalidation 在其冻结配置下得到：

| Decoder | Mean SNDR | Median | P5 | P95 |
|---|---:|---:|---:|---:|
| Nominal + SRM | 58.598 | 58.327 | 53.405 | 64.795 |
| Current on-chip self-cal + SRM | 94.761 | 95.256 | 94.062 | 95.944 |
| Oracle + SRM | 97.139 | 97.139 | 97.031 | 97.245 |

这说明大幅改善是该 mismatch proxy 下的普遍趋势，不是只挑出 chip 17 才出现；但尾部仍有一个严重 outlier，校准最差 SNDR 为 55.619 dB。因此不能把单颗 `+31.8 dB` 或总体 mean 当作 silicon yield 保证。

## 9. 图形解读

### 9.1 `fig_weight_error.png`

显示 nominal、on-chip self-cal 和 external sine-fit 相对 physical weight 的逐 bit 百分比误差。bit0..5 是 reference section，不被片上算法更新；bit6..19 的片上误差形状显著变平，但带有 reference-anchor 导致的整体 gain shift。

### 9.2 `fig_spectrum_compare.png`

所有 decoder 使用同一个独立 test-tone raw-bit stream。Nominal 曲线存在明显失配 spur；片上自校准把 spur 和 broadband quantization error 压低；oracle/external 接近理想 16 位 floor。

### 9.3 `fig_inl_compare.png`

Nominal 曲线呈现由 split/redundant weight mismatch 引起的大台阶；片上自校准后压缩到约 +/-1.4 LSB；SRM expected 后进一步收敛到约 +/-0.96 LSB。

### 9.4 `fig_calibration_trace.png`

逐 target bit 显示 physical weight 与 recursive Q8 estimate。它用于检查 bit6..19 全部被访问、weight magnitude 单调、top-bit protection 后仍有合理结果。

### 9.5 `fig_srm_noise_ablation.png`

左图是 32 次 paired repeats 的 SNDR，右图是 affine-aligned error RMS。每条细线连接同一次 noisy normal conversion 的 no-SRM 与 22-SRM 解码；oracle 和 project self-cal 两组的所有连线都分别朝更高 SNDR、更低 RMS 方向移动。该图直接展示降噪方向，同时避免用两个独立噪声样本制造虚假差异。

## 10. 与 Huang 论文的联系和差距

### 10.1 已复现的数字边界

- 6-bit LSB reference 测量 14 个高位权重；
- P/N polarity offset cancellation；
- 32 pairs averaging；
- bit6..bit19 recursive update；
- b18/b19 protection；
- 20-decision weighted reconstruction；
- 22-decision SRM count-to-residue；
- 同一 noisy raw-bit stream 上的 SRM on/off 成对降噪消融；
- Q8 writeback 和 signed 16-bit saturation；
- 校准前后 SNDR/SFDR/INL/DNL 对比。

### 10.2 尚未复现的 mixed-signal 内容

- 真实 VCM switching sequence 和首次 VCM phase；
- split-sampling analog signal path；
- comparator reset/AZ/evaluate/READYN 时序；
- reference settling、kickback、charge injection 和 switch nonlinearity；
- SS 降噪的 transistor mechanism；
- VM schematic 的真实 CDAC/bridge/parasitic extraction；
- PVT、PDK Monte Carlo、PEX、DRC/LVS、GDS；
- 论文的硅片功耗、噪声和 93.7 dB 实测复现。

所以当前最准确的学术表述是：

> 完成了项目片上数字自校准算法及 SRM/Q8 重构边界的独立行为级闭环验证；尚未完成 Huang 芯片 mixed-signal 物理实现和硅片结果复现。

## 11. FPGA 与 ASIC 风险

### 11.1 FPGA

- 三个核心 RTL 已有 Vivado 2018.3 综合和 XSIM 证据；
- 行为模型证明算法数值方向成立；
- 仍需实现真实 top、atomic raw-code capture、EOC CDC、calibration/normal/SRM arbitration；
- `weights_ready` 前必须禁止 normal reconstruction；
- 外部 ADCToolbox baseline 不应进入 FPGA datapath。

### 11.2 ASIC

- `dac_p_force/dac_n_force` 仍是抽象控制，尚无 calibration PHY sequencer；
- P/N comparator polarity 和 VCM sequence 必须在 transistor AMS 中重新验证；
- 32 pairs 的校准时间、energy 和 timeout 必须纳入系统预算；
- Q8 register width、accumulator overflow、negative rounding 和 reset/X behavior 需要 formal/GLS；
- 22 SRM decisions 必须与同一 conversion residue 建立 transaction ownership；
- 需要 ASIC SDC/MMMC、CDC/RDC、LEC、DFT、PnR、DRC/LVS/PEX 和 post-layout AMS。

## 12. 可复现运行

使用冻结环境：

```powershell
$py = "C:\Users\Administrator\Desktop\ADCToolbox_EVAL_20260728\envs\upstream-main\Scripts\python.exe"

& $py -m py_compile `
  analysis\self_cal_adctoolbox_behavioral_20260830\run_self_cal_behavioral.py `
  analysis\self_cal_adctoolbox_behavioral_20260830\test_self_cal_behavioral.py

& $py -m pytest `
  analysis\self_cal_adctoolbox_behavioral_20260830\test_self_cal_behavioral.py -q

& $py `
  analysis\self_cal_adctoolbox_behavioral_20260830\run_self_cal_behavioral.py
```

依赖文件把 ADCToolbox 固定到审计 commit；`summary.json` 同时记录 package version、module path、模型条件、真实 mismatch realization、train/test bin、全部 decoder metrics 和证据边界。

## 13. 最终工程判断

1. **16 位定义：VERIFIED。** 最终输出是 signed 16 bit；20 仅是冗余判决数。
2. **片上自校准身份：VERIFIED。** 主模型执行 6-bit reference、P/N、32 pair、bit6..19 recursion、top-bit protection 和 Q8 writeback。
3. **理想基准：PASS。** direct ideal quantizer 达到 98.093 dB，与 16 位理论 98.080 dB 对齐。
4. **失配校准有效性：PASS within behavioral model。** 同一失配样本 SNDR 提升 31.80 dB，gain-aligned weight RMSE 改善 40.63 倍。
5. **SRM 数字行为：PASS within the qualified model。** 同一 noisy raw-bit stream 上，22-decision SRM 使 oracle/self-cal 平均 SNDR 分别提高 5.36/4.17 dB，并使误差 RMS 分别降低 1.85/1.62 倍。
6. **ADCToolbox：VERIFIED as analysis/external baseline。** 不属于片上主校准算法。
7. **FPGA/ASIC 集成：GAP。** adapter、CDC、mode arbiter、calibration PHY 和 SRM transaction 尚未闭合。
8. **GDS/硅片：NO CLAIM。** 本报告没有把行为结果升级成 tapeout 或 measured-silicon 结论。

最终结论：当前项目的 **16 位片上前景自校准数字算法在行为级物理失配模型中确实有效**；当前 SRM 数字行为模型也在公平成对带噪声实验中显示明确降噪收益。两者已经用理想 16 位锚点、独立 test frequency、full-range ramp、expected/stochastic SRM、paired noisy ablation 和外部 toolbox baseline 多重交叉验证。尚未闭合的是 SS、AZ、VCM/CDAC/comparator 真实时序与噪声谱，因此下一步必须进入 VM 原理图的 AMS、CDC、ASIC 和 physical signoff，不能把当前结果写成 `111 -> 38 uVrms` 或 93.7 dB 硅片复现。
