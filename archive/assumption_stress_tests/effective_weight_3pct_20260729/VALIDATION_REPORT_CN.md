# 无噪声正常转换下的失配校准验证报告

## 1. 结论

在本工程当前的抽象 20 次差分 SAR 判决模型中，前台权重校准能够非常显著地抑制静态有效权重失配，但不能把失配影响严格降为零。

512 颗失配芯片的中位结果如下：

| 解码权重 | SNDR | 权重 RMSE | 相对 Oracle 仿射码 RMSE |
| --- | ---: | ---: | ---: |
| `NOMINAL` | 34.961 dB | 157.8854 LSB | 366.3735 LSB |
| `CAL_CURRENT_MEAS` | 92.040 dB | 0.1878 LSB | 0.4718 LSB |
| `CAL_NOISELESS_MEAS` | 91.137 dB | 0.2588 LSB | 0.5296 LSB |
| `ORACLE` | 93.364 dB | 0 LSB | 0 LSB |

相对于未校准 nominal 解码，当前校准实现获得：

- SNDR 中位数提升 57.079 dB；
- 权重 RMSE 降低约 840.9 倍，即 58.49 dB；
- 相对 Oracle 的仿射码 RMSE 降低约 776.6 倍，即 57.80 dB；
- 校准后 SNDR 中位数距离 Oracle 仍有 1.324 dB。

因此工程判断为：**校准有效且改善幅度很大，但仍存在低位参考失配、递归搜索量化和 Q8 写回等残余误差，不能声称完全消除失配。**

## 2. 隔离实验设计

本实验只保留静态有效权重失配。正常转换路径关闭：

- sampling noise；
- normal comparator noise 和 offset；
- reference noise；
- DAC settling error；
- stochastic SRM；
- SRM residue 注入。

物理权重失配设置保持与当前工程主模型一致：

- bit0 至 bit5：0.15% 高斯有效权重失配；
- bit6 至 bit19：3% 高斯有效权重失配。

每颗芯片生成一次物理失配权重和一组无噪声 raw bits。四种解码器共享同一组 raw bits，因此输出差别只来自重构权重。

## 3. 样本与指标

- Monte Carlo 芯片数：512；
- 解码结果行数：2048；
- 动态测试：每芯片 8192 点相干正弦；
- 采样率：5 MS/s；
- 输入频率：约 1.000366 MHz；
- 输入幅度：0.82 FS；
- 静态测试：完整 signed-16 ramp，每个输入码 2 个采样点。

核心判据为：

1. 相干 SNDR/SFDR/ENOB；
2. 去除整体增益后的权重 RMSE；
3. 相对 Oracle 输出去除最佳增益和偏置后的码 RMSE；
4. P1、P99 和最差样本，用于观察 Monte Carlo 尾部。

## 4. 分布结果

### 4.1 当前校准

- SNDR：P1 = 90.436 dB，中位数 = 92.040 dB，最小值 = 88.690 dB；
- SFDR 中位数：108.056 dB；
- 权重 RMSE：中位数 = 0.1878 LSB，P99 = 0.2598 LSB；
- 仿射码 RMSE：中位数 = 0.4718 LSB，P99 = 0.5735 LSB；
- 512 颗芯片均无输出饱和。

### 4.2 未校准 nominal

- SNDR 中位数仅 34.961 dB，最小值 24.672 dB；
- 权重 RMSE 中位数 157.885 LSB，P99 达 423.639 LSB；
- 仿射码 RMSE 中位数 366.374 LSB，P99 达 992.310 LSB；
- 说明 3% 高位有效权重失配会造成严重谐波和码形畸变，不能依靠理想 nominal 权重解码。

### 4.3 Oracle 上限

Oracle 直接使用物理权重，中位 SNDR 为 93.364 dB。它不是理想 16-bit 量化极限，原因是本实验明确关闭 SRM residue，而且仍使用当前 Q8 输出舍入和抽象 20 次判决路径。Oracle 的作用是给出同一 raw-bit 模型内的权重解码上限。

## 5. 为什么无噪声校准测量反而略差

`CAL_NOISELESS_MEAS` 的中位结果略低于 `CAL_CURRENT_MEAS`。当前 FSM 的每相搜索、Q8 权重和最终平均均为离散量。当前 0.5 LSB calibration comparator noise 在 P/N 两相和 32 次平均后具有类似阈值抖动的作用，部分芯片上可减轻确定性搜索量化偏差。

这只是当前离散行为模型中的统计现象，不能解释为“增加比较器噪声有利于芯片”。正式设计仍应以减小测量噪声、增加有效平均次数、提高参考 DAC 和写回分辨率为目标。

## 6. 残余误差来源

当前校准与 Oracle 仍有约 1.32 dB 中位 SNDR 差距，主要来源包括：

- bit0 至 bit5 作为参考权重，不参与校准，但模型仍为其加入 0.15% 失配；
- 递归校准使用前一级 shadow weights，早期误差会传递到后续高位；
- SAR 搜索只能得到离散低位组合；
- 校准结果写回为 Q8 整数；
- `AVG_LOOPS=32` 仍有有限平均误差；
- bit18、bit19 的 protection 逻辑会改变可搜索组合；
- 当前 normal-conversion 模型尚未加入论文 2-bit flash 初始化和 VCM/AZ 电荷状态。

## 7. Missing-code 指标说明

不同权重集合会改变整体增益和有效输出码域。当前 ramp 仅使用每码 2 个输入点，因而不同解码器之间的 missing-code 数量会同时受到码域覆盖和采样密度影响。该指标只作辅助检查，不能替代相对 Oracle 的仿射码误差。

## 8. 证据文件

- `run_mismatch_only.py`：独立验证脚本；
- `test_mismatch_only.py`：配置和误差计算单元测试；
- `outputs/per_chip_metrics.csv`：512 颗芯片、四种解码器的完整结果；
- `outputs/summary.json`：聚合统计和实验配置；
- `outputs/fig_mismatch_only_summary.png`：结果图。

代码检查结果：

- `py_compile` 通过；
- `pytest`：3 项测试全部通过；
- 重新以单 worker 运行 chip0 和 chip1，所得 8 行解码结果与 512 芯片主运行逐字段一致；
- `git diff --check` 通过。

结果文件 SHA256：

- `summary.json`: `5510A6992170AA1DE427ECCBD81B09DE6B4195FBA72F2C37682532B7512FCC91`
- `per_chip_metrics.csv`: `2278A823D6A05A91290B56AA2805984BBAD6B0E0503BC6361A877E325033917E`

## 9. 最终判定

当前前台校准已经把高位有效权重失配从“决定性能的主导误差”降低到亚 LSB 级残余，是有效的失配校准方案。它在本行为模型中恢复了约 57 dB 的 SNDR，并将码误差降低约 776.6 倍。

但本结果只证明当前数字权重校准在抽象失配模型中的有效性，不证明 split-sampling/VCM/AZ 前端、2-bit flash、真实 CDAC 电荷重分配和晶体管噪声下仍能获得同样结果。后续完整论文复现仍必须补齐这些前端状态。
