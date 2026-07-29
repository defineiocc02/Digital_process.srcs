# 已撤回：3% Effective-Weight 压力测试

> 本目录不是项目正式失配验证。失配百分比是历史 regression TB 的人工 effective-weight 扰动，不是物理电容、论文或 PDK 失配模型。详见 `WITHDRAWN.md`。

## 目的

本实验只回答一个问题：在正常转换不加入采样噪声、比较器噪声、参考噪声和建立误差时，当前工程的前台权重校准能否消除静态 CDAC 有效权重失配。

所有解码器使用完全相同的失配物理权重和 raw bit 判决。实验不向解码结果注入 SRM residue，因此结果差异只来自数字权重：

| 解码器 | 含义 |
| --- | --- |
| `NOMINAL` | 理想 nominal 权重，代表不校准 |
| `CAL_CURRENT_MEAS` | 当前 RTL 等效前台校准，保留 5 LSB offset、0.5 LSB calibration noise 和 32 次平均 |
| `CAL_NOISELESS_MEAS` | 校准比较器 offset/noise 均为零，用于观察算法及定点量化上限 |
| `ORACLE` | 直接使用真实物理权重，作为当前抽象模型上限 |

## 失配条件

- bit0 至 bit5：`0.15%` 独立高斯有效权重失配；
- bit6 至 bit19：`3%` 独立高斯有效权重失配；
- Monte Carlo：512 颗芯片；
- 每颗芯片动态记录：8192 点相干采样；
- 每颗芯片静态记录：全 16-bit ramp，每码 2 个输入点；
- 正常转换随机噪声：全部关闭；
- SRM residue：不参与本实验解码。

## 运行

```powershell
$py = "C:\Users\Administrator\Desktop\ADCToolbox_EVAL_20260728\envs\upstream-main\Scripts\python.exe"
& $py -m pytest -q analysis/mismatch_only_noiseless_20260729/test_mismatch_only.py
& $py -m analysis.mismatch_only_noiseless_20260729.run_mismatch_only --chips 512 --workers 8
```

## 判定方法

除 SNDR、SFDR、DNL、INL 和 missing code 外，实验直接比较每种权重解码与 `ORACLE` 解码：

- `code_rmse_to_oracle_raw_lsb`：包含整体增益差的码均方根误差；
- `code_rmse_to_oracle_affine_lsb`：去除最佳增益和偏置后的码均方根误差；
- `weight_rmse_gain_aligned_lsb`：去除整体权重增益后的权重均方根误差。

只有经过校准后这些误差相对 `NOMINAL` 显著下降，才能说明失配影响确实被数字权重校准抑制，而不是仅由 FFT 输入或 SRM 掩盖。

`missing_codes` 仅作为辅助观察量。由于各权重集合会产生不同的整体增益和有效输出码域，而且 ramp 仅使用每码 2 个输入点，不能用不同解码器之间的 missing-code 数量单独判断优劣。主要判据是相对 `ORACLE` 的仿射码误差、权重误差和相干 SNDR。

## 边界

本实验仍使用工程当前的抽象 20 次差分判决模型。它不包含论文 split-sampling/VCM/AZ/2-bit flash 前端时序，也不是晶体管级或流片 sign-off。
