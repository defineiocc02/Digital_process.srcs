# Verification

## Testbench Entry Points

| Testbench | Purpose |
| --- | --- |
| `tb_sar_adc_top.sv` | 系统闭环：校准、SAR 转换、重构、INL 检查 |
| `tb_sar_recon.sv` | 重构模块：线性、权重更新、流水线吞吐 |
| `tb_gain_comp_check_lsb.sv` | 校准残差与增益补偿 |
| `tb_flash_decoder.sv` | thermometer code 译码 |

## Suggested Order

1. `tb_flash_decoder`
2. `tb_sar_recon`
3. `tb_gain_comp_check_lsb`
4. `tb_sar_adc_top`

## Local Status

当前命令行环境未发现 `vivado`、`xsim`、`verilator` 或 `iverilog`，所以本轮仅完成静态引用检查和 Git 文件集检查。HDL 编译/波形验证需要在 Vivado GUI 或安装了仿真器的 shell 中运行。
