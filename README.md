# SAR ADC V3 Core

这是 16-bit split-sampling SAR ADC 数字后端的核心工程版。当前主线只保留能打开、能综合/仿真、能继续开发的最小文件集；历史工程、旧备份、MATLAB 辅助脚本和重复文档已经从工作树移除，归档通过 Git 历史和标签完成。

## 当前版本

- Version: `v3.2.0-core`
- Archive tag: `archive/full-project-before-core-prune`
- Main commit goal: core RTL, core testbench, Vivado project, concise docs only

## 工程入口

- Vivado project: `Digital_process/Digital_process.xpr`
- Vivado version: 2018.3 project format
- FPGA part: `xc7a35tfgg484-2`
- RTL top: `fpga_top_wrapper`
- Main simulation top: `tb_sar_adc_top`

## 核心文件

```text
Digital_process/
├── Digital_process.xpr
└── Digital_process.srcs/
    ├── sources_1/new/
    │   ├── fpga_top_wrapper.sv
    │   ├── sar_calib_ctrl_serial.sv
    │   ├── sar_reconstruction.sv
    │   ├── sar_adc_controller.sv
    │   ├── flash_decoder_adder.sv
    │   └── virtual_adc_phy.v
    ├── sim_1/new/
    │   ├── tb_sar_adc_top.sv
    │   ├── tb_sar_recon.sv
    │   ├── tb_gain_comp_check_lsb.sv
    │   └── tb_flash_decoder.sv
    └── constrs_1/new/
        └── sar_calib_fpga.xdc
```

## 模块职责

- `sar_calib_ctrl_serial.sv`: 前景递归校准控制器，负责 DAC force、比较器反馈搜索、权重写回。
- `sar_reconstruction.sv`: 根据校准权重重构 16-bit signed 输出。
- `sar_adc_controller.sv`: SAR 转换控制器，用于系统级闭环验证。
- `flash_decoder_adder.sv`: thermometer code 到 binary 的小型译码器。
- `virtual_adc_phy.v`: 仿真用电容权重与比较器模型。
- `fpga_top_wrapper.sv`: FPGA 工程顶层包装。

## 本轮核心化改动

1. 删除重复 RTL/TB 备份、旧 Vivado 工程、MATLAB 辅助目录和历史文档目录。
2. 将 `fpga_top_wrapper.sv` 从仿真目录移动到 RTL 源码目录。
3. 合并 `sar_calib_ctrl_serial.sv` 中 P/N 两相重复的 setup、SAR、calc 顺序逻辑。
4. 保留顶层 `docs/` 作为唯一版本说明和工程说明入口。

## 使用方式

1. 打开 `Digital_process/Digital_process.xpr`。
2. 运行 `tb_sar_adc_top` 做系统闭环验证。
3. 运行 `tb_sar_recon`、`tb_gain_comp_check_lsb`、`tb_flash_decoder` 做模块级回归。
4. 需要恢复旧资料时使用 Git 标签：`archive/full-project-before-core-prune`。
