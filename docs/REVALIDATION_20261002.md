# 指标修复后的独立重跑 · 2026-10-02

## 可复核证据

代码提交：`1655d303fdc6627c506a7b46fb294c92972ec331`。完整数值、行为集成、旧检查点拒绝、直接脚本入口、物理电容模型对照及以下批处理均通过本轮 [自动检查](https://github.com/defineiocc02/Digital_process.srcs/actions/runs/37002707969)。完整原始结果、配置和图表保存在该运行的 artifacts；核心物理重跑快照永久收录于 [JSON 记录](REVALIDATION_20261002.json)。Artifacts 按 GitHub 保留期到期，长期引用前需下载归档；命令和源文件身份可用于重新生成。

- 完整行为模型：512 个芯片样本，全新目录、无旧缓存，含采样与正常转换噪声。
- 物理 CDAC：512 个主样本；每个失配点 128 个样本，7 个失配点；128 个样本的 5 个幅度点。普通转换噪声关闭，动态 SRM 随机噪声保留，静态采用期望计数。
- 主矩阵每个解码器/样本的满幅和回退指标都检查 SNR ≥ SNDR；并非只检查中位数。

## 满幅理想量化器对照

新 SNR **98.079781 dB**，SNDR **98.079113 dB**。历史结果的 SNR 95.639 dB 小于 SNDR 98.079 dB 矛盾已在一致功率分区下消除。

## 物理 CDAC 主矩阵

下表均为同一条件矩阵的中位数。回退幅度约为满幅的 0.82；两种输入幅度不能混作一个指标。

| 解码器 | 满幅 SNDR (dB) | 满幅 SNR (dB) | 回退 SNDR (dB) |
|---|---:|---:|---:|
| NOMINAL_SRM | 58.327 | 61.108 | 56.525 |
| CAL_CURRENT_SRM | 95.256 | 95.383 | 93.577 |
| CAL_SUM_NORM_SRM | 95.282 | 95.390 | 93.640 |
| CAL_HEADROOM_GUARD_SRM | 95.277 | 95.394 | 93.577 |
| CAL_ZERO_COMP_ERROR_SRM | 92.621 | 93.009 | 90.936 |
| ORACLE_SRM | 97.139 | 97.147 | 95.428 |

当前校准满幅 SNDR ≥90 dB 为 **504/512**，≥95 dB 为 **357/512**；回退条件 ≥90 dB 为 **512/512**，≥95 dB 为 **0/512**。分析中的 headroom guard 满幅 ≥90 dB 为 512/512，但这是后处理研究结果，不代表已加入当前 RTL。应优先定位饱和/增益尾部，并在硬件可实现的接口下验证保护策略。

完整含噪行为模型另得 CAL_SRM SNDR 中位数 **91.018 dB**；它与上述普通转换零噪声矩阵条件不同，不构成结果冲突。

## 复现

```bash
python -m pip install -r analysis/full_sar_behavioral_20260729/requirements.txt
python analysis/full_sar_behavioral_20260729/run_campaign.py --chips 512 --workers 2 --no-resume --outdir campaign-full-recheck
python analysis/physical_cdac_mismatch_20260729/run_revalidation.py --chips 512 --sensitivity-chips 128 --amplitude-chips 128 --workers 2 --outdir physical-cdac-recheck
```

依赖版本与源码 SHA-256 见 JSON 快照；默认配置和种子与记录一并保存。完整行为批处理现已拒绝配置、代码、依赖或 Python 版本不匹配的检查点；不要从历史结果目录拼接新旧数字。

## 仍待完成

本次没有重新制作冻结交付 PDF，也没有重跑所有后续自校准/消融变体或 MATLAB 平台。历史 PDF/JSON 保留原字节并继续作为历史证据，当前数字请引用本记录。芯片参数仍是模型假设，尚无 PDK 失配卡、全电路 PVT、PEX、真实 ADC 接入或硅片结论。
