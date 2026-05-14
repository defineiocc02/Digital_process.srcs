# SAR ADC V3 MOC

MOC 是本项目的内容地图，用来快速定位代码、文档、验证和归档资料。

## 入口

- 项目总览：[README.md](README.md)
- 需求分析：[docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)
- 架构说明：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 验证说明：[docs/VERIFICATION.md](docs/VERIFICATION.md)
- 目录规范：[docs/PROJECT_ORGANIZATION.md](docs/PROJECT_ORGANIZATION.md)
- 整理记录：[docs/CHANGELOG.md](docs/CHANGELOG.md)

## 工程入口

- 主 Vivado 工程：`Digital_process/Digital_process.xpr`
- 主源码目录：`Digital_process/Digital_process.srcs/sources_1/new/`
- 主仿真目录：`Digital_process/Digital_process.srcs/sim_1/new/`
- 约束目录：`Digital_process/Digital_process.srcs/constrs_1/new/`

## RTL 模块地图

- 校准控制：`sar_calib_ctrl_serial.sv`
- 数字重构：`sar_reconstruction.sv`
- SAR 控制：`sar_adc_controller.sv`
- Flash 译码：`flash_decoder_adder.sv`
- AFE 仿真模型：`virtual_adc_phy.v`
- FPGA 包装顶层：`fpga_top_wrapper.sv`

## 验证地图

- 系统级闭环验证：`tb_sar_adc_top.sv`
- 重构单元验证：`tb_sar_recon.sv`
- 校准增益补偿验证：`tb_gain_comp_check_lsb.sv`
- Flash 译码验证：`tb_flash_decoder.sv`

## 辅助资料

- MATLAB 脚本：`matlab/`
- 历史 Vivado 工程：`archive/legacy_vivado_projects/`
- 二进制快照：`archive/binary_snapshots/`
