# 分段 CDAC 物理失配与片上校准验证报告

## 1. 结论摘要

本轮撤回了“直接给高位 effective weights 注入 3% rms”的正式结论，改用项目原
MATLAB 拓扑建立物理电容网络。失配先施加到 bit capacitor、bridge capacitor、
节点寄生和比较器输入电容，再通过 4 节点电容矩阵求解最终 decision weights。

正式结果表明：

1. 测试平台能够复现理想 16-bit 满幅相干正弦的 `98.079 dB` SNDR。
2. 零失配分段 CDAC 加确定性期望计数 SRM 得到 `98.045 dB`，算术链路闭合。
3. 论文对应的 22 次随机 SRM 在理想 CDAC 上约为 `97.15 dB`。这约 0.9 dB
   的差异来自有限二项样本的 residue 估计方差，不是普通转换噪声被偷偷打开。
4. 在 512 颗、1.2% unit-cap rms 中心实验中，未校准 nominal+SRM 中位 SNDR
   为 `58.327 dB`，当前 RTL 前景校准+SRM 为 `95.256 dB`，oracle+SRM 为
   `97.139 dB`。校准对失配线性误差显著有效。
5. 当前结果不是 100% 良率闭合。512 颗中当前校准有 504 颗达到 90 dB 以上、
   491 颗达到 94 dB 以上。最差尾部由全局增益偏高后的满幅饱和主导；当前 RTL
   校准相对权重，但没有独立的最终 gain normalization 或输入 backoff 管理。

## 2. 为什么原 3% 实验被撤回

原实验直接对最终 reconstruction-domain weights 施加：低 6 位 0.15% rms、
高 14 位 3% rms。该数值来自历史回归压力条件，不是用户指定条件、论文参数、
PDK mismatch card 或物理 CDAC Monte Carlo。它跳过了桥接电容与寄生耦合，因而
不能解释“某个物理电容失配如何传播到全部有效权重”。

旧文件没有删除，已归档到：

```text
archive/assumption_stress_tests/effective_weight_3pct_20260729/
```

并通过 `WITHDRAWN.md` 标明仅可作为历史压力测试。

## 3. 外部项目对失配的共同理解

### 3.1 ADCToolbox

ADCToolbox 的 `sar_apply_cap_mismatch()` 明确要求物理 `cap_units`，并使用：

\[
\sigma_{C_i,rel}=\frac{\sigma_{Cu}}{\sqrt{N_i}}
\]

其中 `sigma_unit` 是单个 unit capacitor 的 RMS 相对失配。其代码同时把“对最终
weights 直接乘相同比例随机数”的接口标为 legacy。因此本实验只复用其 FFT、
INL/DNL 评价思路，不复用错误的直接权重扰动方式。

来源：<https://github.com/Arcadia-1/ADCToolbox/blob/a8995cf4faf73dde9918589bfeb866c6a77db12d/python/src/adctoolbox/models/sar.py>

### 3.2 circuit-optimization-lab

该项目同样先复制真实电路拓扑，再按 `sigma_Cu/sqrt(C/Cu)` 扰动物理电容，随后
完整扫 code center，检查 monotonicity、missing code、DNL、INL 与 yield。它支持
本实验采用“先物理扰动、后求权重、最后做全码域评价”的顺序。

来源：<https://github.com/751K/circuit-optimization-lab/blob/cf60ff174354a5e4291682d42824383bae6ee6c7/circuitopt/sar_mc.py>

## 4. 项目物理拓扑

物理参数来自归档 MATLAB：

```text
target resolution          16 bit
VREF                       3.3 V
unit capacitor             8 fF
segments                   6 + 4 + 5 + 5
segment 1                  [1, 2, 4, 8, 16, 32] Cu
segment 2                  [2, 4, 8, 16] Cu
segment 3                  [2, 2, 4, 8, 16] Cu
segment 4                  [8, 8, 16, 32, 64] Cu
bridge capacitors          [4, 4, 12] Cu
node parasitic             0.05 Cu = 0.4 fF
comparator input cap       5 fF
unit-cap mismatch center   1.2% rms
node/parasitic variation   2% rms
```

来源文件：`archive/deleted-in-039c478/matlab/cap_array_calib_16b.m`。

### 4.1 物理失配生成

对名义为 `N_i` 个单位电容的物理电容：

\[
C_i=C_{u}N_i\left(1+\frac{\sigma_u}{\sqrt{N_i}}z_i\right),
\quad z_i\sim\mathcal N(0,1)
\]

bridge capacitor 使用相同面积律。节点寄生和比较器输入电容按原 MATLAB 方式各
抽取一个芯片固定高斯比例误差。没有任何一步直接扰动最终 Q8 weights。

### 4.2 电容矩阵求解

四段顶板节点构成 4 x 4 电容矩阵 `A`。对每一个物理 bit 单独施加 `VREF`，求：

\[
\mathbf A\mathbf v_i=\mathbf b_i
\]

最终比较节点电压即该 bit 的有效 decision weight。名义求解器复现项目权重表，
包括 `32 -> 33.525` 的冗余边界以及重复权重段；单元测试容差为 `1e-9`。

## 5. 前景校准与重构

当前算法源仍是本工程 `sar_calib_ctrl_serial.sv`，不是开源库：

1. bit0 至 bit5 作为低位参考；
2. bit6 至 bit19 递归校准；
3. 每个目标位做 P/N 两相搜索；
4. P/N 相加抵消固定 comparator offset；
5. `AVG_LOOPS=32`，测量结果递归写回 shadow weights；
6. 最高两位使用 protection bits；
7. Q8 权重写入 reconstruction RAM。

重构为：

\[
D=\operatorname{sat}_{16}\left\{\operatorname{round}\left[
\frac{\sum_i s_iW_i}{2\cdot 2^8}+\frac{R_{SRM}}{2^8}
\right]\right\}
\]

其中 `s_i` 为正负决策。`/2` 来自差分 `+W/-W` 码制。

## 6. SRM 问题与修复

论文说明 DAC 在 SRM 阶段保持不动，锁存器额外进行 22 次比较，计数概率 `P`
再经 inverse-normal LUT 估计 residue：

\[
\hat v_{res}=\sigma_n\Phi^{-1}(P)
\]

### 6.1 不开 SRM 为什么下降约 3 dB

不开 SRM 相当于将 SAR bit cycling 后的 residue 丢弃。理想满幅结果为：

| 路径 | SNDR |
| --- | ---: |
| 理想 16-bit 均匀量化器 | 98.079 dB |
| 分段 CDAC，不加 residue | 95.087 dB |
| 分段 CDAC，确定性期望计数 SRM | 98.045 dB |

额外 residue 误差与最终量化误差量级相近，误差功率近似翻倍，对应
`10log10(2)=3.01 dB`。

### 6.2 原实验的问题

原正式实验使用 `round(22P)`，这是无限重复统计意义下的确定性传递函数，不是
单次转换可实现的 22 个 Bernoulli decisions。该问题已经修复：

- 动态 FFT：`stochastic_srm=True`，真实生成 22 次二项计数；
- 静态 ramp：保留期望计数，避免随机空码污染 DNL/INL；
- summary 同时报告理想量化器、确定性 SRM 上限与 RTL-22 随机结果。

### 6.3 22 次能否达到 98.08 dB

不能在零其他噪声条件下严格达到。22 次二项估计本身有不可消除的有限样本方差。
本实验得到：

| Profile | 决策数 | 平均 SNDR |
| --- | ---: | ---: |
| 当前 RTL inverse-normal LUT | 22 | 97.145 dB |
| 均匀 ramp 先验 posterior-mean LUT，仅分析 | 22 | 97.396 dB |
| posterior-mean precision profile，仅分析 | 128 | 97.926 dB |

因此现有 LUT 并非唯一问题：仅优化 22-entry LUT 可改善约 0.25 dB，但不能消除
有限样本方差；增加到 128 次才越过本实验 `97.9 dB` 门槛。128 次会把 SRM 延迟、
counter 位宽与 LUT 大小一起改变，不属于无风险 bug fix，因此没有擅自修改核心 RTL。

候选扫描脚本：`analyze_srm_precision_profiles.py`。

## 7. 512 颗主实验

### 7.1 条件

- 512 个稳定随机种子的独立物理芯片；
- 1.2% unit-cap rms，2% 寄生参数 rms；
- 满幅相干正弦，8192 点 FFT；
- sampling、normal comparator、reference、settling noise 全部为 0；
- 动态路径使用真实 22 次随机 SRM；
- full 16-bit ramp，每码 2 点；
- 四个解码器使用完全相同的 SAR raw decisions。

### 7.2 中位结果

| Decoder | SNDR | Weight RMSE | Code RMSE to oracle |
| --- | ---: | ---: | ---: |
| NOMINAL_SRM | 58.327 dB | 13.0891 LSB | 30.0367 LSB |
| CAL_CURRENT_SRM | 95.256 dB | 0.2004 LSB | 0.4505 LSB |
| CAL_ZERO_COMP_ERROR_SRM | 92.621 dB | 0.2685 LSB | 0.5827 LSB |
| ORACLE_SRM | 97.139 dB | 0 | 0 |

`CAL_ZERO_COMP_ERROR` 反而略差不是因为噪声有益于模拟电路，而是 comparator noise
在 32 次平均中对离散 SAR 搜索阈值形成 dither，使 Q8 结果可以逼近阈值间的分数
位置。完全确定性搜索会停在固定离散边界。该现象属于校准量化问题，应在后续通过
更高内部精度、明确 dithering 或多阈值平均处理，而不是依赖未定义噪声。

### 7.3 静态中位结果

| Decoder | DNL min/max | INL min/max | Missing codes |
| --- | --- | --- | ---: |
| NOMINAL_SRM | -1 / +2.998 LSB | -68.698 / +68.697 LSB | 991 |
| CAL_CURRENT_SRM | -0.509 / +0.968 LSB | -1.000 / +0.993 LSB | 0 |
| ORACLE_SRM | 0 / 0 LSB | 0 / 0 LSB | 0 |

静态结果使用确定性期望计数 SRM，只评价 transfer curve，不包含随机 SRM noise。

### 7.4 尾部与满幅饱和

当前校准路径：

- 504/512 芯片达到 90 dB；
- 491/512 芯片达到 94 dB；
- 357/512 芯片达到 95 dB；
- 20/512 芯片达到 96 dB。

最差芯片 SNDR 约 55.6 dB，但 gain-aligned weight RMSE 仍约 0.18 LSB。逐芯片
追踪表明其校准权重整体同比偏高，满幅输出约 7.2% 样本饱和。由此可知当前校准
能恢复相对权重，却没有闭合绝对增益。建议后续增加以下任一系统策略：

1. 独立 full-scale gain coefficient；
2. 校准后按可用总权重做数字归一化；
3. 保留明确输入 backoff；
4. 在 CDAC/保护位设计中增加 over-range margin。

## 8. 失配强度敏感度

每个 sigma 点 128 颗，动态路径为真实 22 次 SRM：

| Unit-cap sigma | Nominal median | Current cal median | Oracle median |
| ---: | ---: | ---: | ---: |
| 0.5% | 65.906 dB | 95.306 dB | 97.158 dB |
| 1.0% | 59.931 dB | 95.326 dB | 97.157 dB |
| 1.2% | 58.358 dB | 95.231 dB | 97.137 dB |
| 1.5% | 56.424 dB | 95.217 dB | 97.143 dB |
| 2.0% | 53.937 dB | 95.129 dB | 97.147 dB |
| 3.0% | 50.404 dB | 94.756 dB | 97.160 dB |

校准后的 gain-aligned weight RMSE 中位约 0.19 至 0.20 LSB，说明递归相对权重
估计对本扫描范围内的物理电容失配有效。满幅尾部仍需结合饱和率判断。

## 9. 文件操作与验证记录

### 新增

- `physical_cdac.py`：物理拓扑、面积律失配、电容矩阵、Q8 映射；
- `run_physical_mismatch.py`：512 颗主实验、sigma sweep、FFT/ramp；
- `analyze_srm_precision_profiles.py`：22/128 次有限样本设计扫描；
- `test_physical_cdac.py`：名义权重、零失配、seed、面积律、98 dB gate；
- `README.md` 与本报告；
- `outputs/` 下 CSV、JSON、PNG、PDF 证据。

### 归档

- `analysis/mismatch_only_noiseless_20260729/` 移入
  `archive/assumption_stress_tests/effective_weight_3pct_20260729/`；
- 未直接删除任何历史实验。

### 已运行

```text
Python py_compile                         PASS
pytest test_physical_cdac.py              5 passed
4-chip smoke campaign                     PASS
512-chip physical campaign                512/512 complete
sigma sensitivity                         6 x 128 complete
SRM finite-sample profile study           complete
ideal 16-bit arithmetic gate              PASS
```

## 10. 证据边界

本报告能证明：在当前物理代理拓扑与随机假设下，片上前景校准能显著消除 CDAC
相对失配；行为模型的理想 16-bit 算术链路闭合；当前 22 次随机 SRM 存在可量化的
有限样本噪声。

本报告不能证明：

- 1.2%/2% 等同于目标工艺 PDK；
- split sampling 的 VCM、AZ、flash、charge injection 时序已复现；
- 128 次候选 profile 可直接替换当前 RTL；
- FPGA 综合通过等同于 ASIC 流片 signoff；
- 512 个行为样本等同于硅后良率。

下一步应使用目标 PDK Monte Carlo 或 schematic-extracted CDAC 参数替换本报告的
MATLAB 假设，并单独设计全局增益归一化与 SRM latency/noise 预算。
