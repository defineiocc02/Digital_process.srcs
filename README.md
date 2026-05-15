# SAR ADC V3 Minimal Core

这是当前仓库的最小核心版，只保留两个核心功能块及其对应 testbench：

- 数字重构：`sar_reconstruction.sv` + `tb_sar_recon.sv`
- 前景校准：`sar_calib_ctrl_serial.sv` + `tb_gain_comp_check_lsb.sv`

旧的系统顶层、SAR 控制器、flash decoder、virtual PHY、系统闭环 TB、MATLAB 脚本和历史工程均已从主线移除；需要时通过 Git 历史恢复。

## 版本

- Version: `v3.3.0-minimal`
- Previous core commit: `039c478`
- Full organized archive tag: `archive/full-project-before-core-prune`

## 文件结构

```text
sar_adc_v3/
├── Digital_process/
│   ├── Digital_process.xpr
│   └── Digital_process.srcs/
│       ├── sources_1/new/
│       │   ├── sar_calib_ctrl_serial.sv
│       │   └── sar_reconstruction.sv
│       ├── sim_1/new/
│       │   ├── tb_gain_comp_check_lsb.sv
│       │   └── tb_sar_recon.sv
│       └── constrs_1/new/
│           └── sar_calib_fpga.xdc
├── docs/
├── MOC.md
└── README.md
```

## Vivado 默认入口

- Project: `Digital_process/Digital_process.xpr`
- Default synthesis top: `sar_reconstruction`
- Default simulation top: `tb_sar_recon`
- Calibration simulation top: switch to `tb_gain_comp_check_lsb` in Vivado when needed.

## 本轮进一步精简

- 删除 `fpga_top_wrapper`、`sar_adc_controller`、`flash_decoder_adder`、`virtual_adc_phy`。
- 删除 `tb_sar_adc_top`、`tb_flash_decoder`。
- `.xpr` 只引用两份核心 RTL 和两份对应 TB。
- `sar_calib_ctrl_serial` 进一步合并 P/N 相 DAC drive 组合逻辑。
