# 验证说明

## 当前验证入口

| 层级 | Testbench | 目的 |
| --- | --- | --- |
| 系统级 | `tb_sar_adc_top.sv` | 校准、SAR 转换、重构闭环，检查 INL |
| 重构单元 | `tb_sar_recon.sv` | 线性、权重更新、流水线吞吐 |
| 校准单元 | `tb_gain_comp_check_lsb.sv` | Monte Carlo 权重误差与增益补偿 |
| 译码单元 | `tb_flash_decoder.sv` | thermometer code 到 binary 的容错译码 |

## 建议回归顺序

1. 在 Vivado 2018.3 中打开 `Digital_process/Digital_process.xpr`。
2. 运行 `tb_flash_decoder`，快速确认基础译码逻辑。
3. 运行 `tb_sar_recon`，确认重构模块 reset 默认权重与写权重接口。
4. 运行 `tb_gain_comp_check_lsb`，确认校准残差。
5. 运行 `tb_sar_adc_top`，确认系统闭环。

## 本次本地验证状态

当前命令行环境未发现 `vivado`、`xsim`、`verilator` 或 `iverilog` 可执行命令，因此本轮无法在终端直接跑 HDL 编译或仿真。已完成的验证包括：

- 源码入口和 Vivado `.xpr` 引用检查。
- 低位权重手动初始化依赖搜索。
- Vivado 生成目录与源码目录分离检查。
- Git 忽略规则配置。

## 后续建议

- 在 Vivado GUI 中运行 behavioral simulation，并保存 `tb_sar_adc_top` 的关键输出。
- 若要 CI 化，建议增加批处理脚本 `vivado -mode batch -source scripts/run_sim.tcl`。
- 若后续引入 Verilator，需要先处理 testbench 中的 SystemVerilog task、real 和层次化访问兼容性。
