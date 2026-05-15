# MATLAB Scripts

此目录保存与 16-bit SAR ADC 建模、权重表生成和噪声分析相关的 MATLAB 辅助脚本。

## 文件

- `cap_array_calib_16b.m`：16-bit 电容阵列校准分析脚本。
- `gen_srm_lut.m`：SRM/LUT 生成脚本。
- `ramp_noise_analysis.m`：ramp/noise 分析脚本。
- `generated/erf_inv_lut.vh`：由脚本生成或配套使用的 Verilog header。

## 维护约定

- MATLAB 脚本输出的中间图表、临时数据和大文件不进入 Git。
- 若生成的 `.vh` 被 RTL 直接 include，应在 Vivado 工程中显式添加路径并同步更新本文档。
