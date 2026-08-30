# Huang 2024/2025 论文事实与项目关系证据

## 1. 来源与边界

本文件只记录本轮实际读取的论文事实及其与工程的关系，不替代完整文献综述，也不构成新颖性检索结论。

- Huang et al., JSSC 2025, `A 5-MS/s 16-bit Low-Noise and Low-Power Split Sampling SAR ADC With Eased Driving Burden`。
  本地 PDF：`D:/Academic/Zotero/files/07_在读/0849 - Huang 等 - 2025 - A 5-MSs 16-bit low-noise and low-power split sampling SAR ADC with eased driving burden.pdf`。
- Q. Huang, PhD thesis, HKUST, 2024, Chapter 4。
  本地 PDF：`D:/Academic/Zotero/files/03_ADC各领域文献/031_高精度SAR_ADC领域/0764 - Huang - 2024 - Advanced clock multiplier and SAR ADC design techniques for high-resolution signal chain systems.pdf`。
- 公开元数据页：<https://researchportal.hkust.edu.hk/en/publications/a-5-mss-16-bit-low-noise-and-low-power-split-sampling-sar-adc-wit/>。

## 2. 可核实的论文事实

| 论文事实 | 位置 | 对本项目的意义 |
|---|---|---|
| 16 bit、5 MS/s；2 x 20 pF sampling capacitors 配合 1 pF CDAC | JSSC 2025 abstract；thesis Ch.4 | 项目 VM 的 split-sampling/CDAC 方向相关，但不能据此认定拓扑、位权或时序等价 |
| 20-bit redundant DAC；2-bit flash 处理高位，后接异步 SAR | JSSC Fig.6 周边；thesis Ch.4 | VM 的 20 路 CDAC decision 与异步逻辑在架构上相近；实际位映射必须由网表核实 |
| 额外 22 次 comparator decisions 用于 SRM，论文报告 SRM 带来约 4.6 dB SNDR 改善 | JSSC abstract/measurement section | 当前行为模型已在同一 noisy raw-bit stream 上得到 project-self-cal `+4.17 dB` 的 paired 改善；VM 仍无同一 residue 的 22 次物理比较序列，不能据此宣称论文实测复现 |
| 1 pF CDAC 的 mismatch/寄生使未校准线性约 11 bit，需要 bit-weight calibration | thesis 4.5, pp.86-87；JSSC calibration section | 说明前景权重校准的必要性；项目行为模型必须由物理电容/bridge/parasitic 导出 effective weights |
| 6 个 LSB capacitors 复用为 calibration DAC，测量 14 个高位权重 | thesis 4.5；JSSC calibration section | 与当前 `MAX_CALIB_BIT=5`、bit6 至 bit19 递归更新意图一致 |
| 每个目标位进行正、负两个方向测量以消除前放/比较器 offset | thesis Eq.4.17-Eq.4.19 | 与当前 P/N 两相 RTL 意图一致，但真实 sampling/VCM/reference switching 尚未实现 |
| 每个 P/N pair 重复 32 次，等效 64 个噪声样本，权重测量噪声标准差降为原来的 1/8 | thesis pp.88-89 | 当前 `AVG_LOOPS=32` 与此关系相符；报告中不得把 32 loops 和 64 scalar samples 混写 |
| 校准 b18 时强制 b17 反向；校准 b19 时强制 b17、b18 反向，使顶板 swing 约为 +/-W17 | thesis pp.89-90 | 与当前 top-bit protection RTL 意图一致；必须在真实差分 CDAC switching 上验证 |
| 6-bit LSB 校准 DAC 的 3-sigma INL 约 +/-0.39 LSB | thesis p.90；JSSC calibration section | 构成静态参考误差地板；当前行为代理的独立高斯近似不能代替真实相关码误差 |
| SS+SRM 使短输入 IRN 约从 111 uVrms 降至 38 uVrms，并使校准平均时间约降低 10 倍 | thesis pp.86,90；JSSC calibration section | 该结果属于论文既有贡献；本项目若复现，必须提供 calibration-mode 物理采样与 SRM 证据 |
| 论文报告 averaging=64 时约 94 dB SNDR、108 dBc SFDR，3-sigma worst-case SFDR >100 dBc | JSSC Fig.16 周边 | 可作为参考目标，不是当前 surrogate/RTL 结果的验收替代品 |
| 芯片实测 93.7 dB SNDR、5.31 mW、FoMs 180.4 dB；校准后 INL 约 -0.9/+0.9 LSB | JSSC abstract/measurement | 当前工程无对应 GDS、芯片和原始测量数据，不得声称已复现这些实测值 |

## 3. 数学关系

对目标位 `k`，论文中的两次测量可写为：

```text
D_k,+ = +W_k + V_os + n_+
D_k,- = -W_k + V_os + n_-
W_hat_k = (D_k,+ - D_k,-) / 2
        = W_k + (n_+ - n_-) / 2
```

若 `n_+`、`n_-` 独立同分布且标准差均为 `sigma_n`，一组 P/N pair 的误差标准差为 `sigma_n/sqrt(2)`。再独立平均 `M=32` 组 pair：

```text
sigma(W_hat_k) = sigma_n / sqrt(2M) = sigma_n / 8
```

递归校准关系是：先用可信的 6-bit LSB reference section 测 `W6`，再把 `W6` 加入已知参考集合测 `W7`，依次直到 `W19`。该递归使低位偏差、量化和 switching error 可能向高位传播，因此必须报告逐位误差和最终 code-domain 误差，而不能只看一个平均权重 RMSE。

## 4. 项目复现距离

| 层级 | 当前状态 | 与论文距离 |
|---|---|---|
| Q8 weighted reconstruction | 已有 RTL、bit-exact TB | 已覆盖数字算术边界；未证明与 VM 物理位权一一对应 |
| P/N recursive calibration | RTL intent + 行为模型 | 已覆盖递归/平均/protection 意图；缺真实 sampling/VCM/reference/READYN switching |
| 22-decision SRM estimator | LUT/counter 单测通过；8192 点 × 32 repeats paired noisy behavior PASS | 已覆盖 digital estimator、raw-bit identity 和 comparator/residue 降噪方向；仍缺 VM residue hold、22 次物理比较及时序 transaction pairing |
| split-sampling noise cancellation | VM 有相关电路层次 | 尚未形成可重复、成功的 AMS/PEX 测量证据 |
| 1 pF physical mismatch | 项目物理代理模型已做 512-chip 行为验证 | 仍是项目假设的 segmented network，不是 VM PDK-extracted CDAC |
| layout/GDS | 仅一个 9-instance、0-shape OA 视图 | 距完整布局、DRC/LVS/PEX、stream-out 和 foundry signoff 很远 |
| silicon measurement | 无 | 不能复现论文实测 SNDR、INL、功耗或 FoM |

## 5. 创新边界

以下内容已由 Huang 论文覆盖，不能原样作为本项目新贡献：split sampling、1 pF CDAC、6-bit LSB reference 测 14 个高位、P/N offset cancellation、32 pair averaging、b18/b19 over-range protection、22-decision SRM 及其 10x calibration-time benefit。

本项目可研究的空间必须落在论文未闭合或新问题上，例如：异步 20-CDAC/21-latched-decision 的确定性 transaction ownership、VCM-aware shared calibration PHY、SRM/校准联合的自适应停止与硬件代价优化、可量产观测/DFT，以及用真实 PEX/silicon 证明的能耗或良率优势。
