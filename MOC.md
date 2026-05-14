# MOC

## 必读

- [README.md](README.md): 工程入口和核心文件说明
- [docs/VERSION.md](docs/VERSION.md): 当前版本和归档标签
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): 核心链路说明
- [docs/VERIFICATION.md](docs/VERIFICATION.md): 仿真入口和验证顺序
- [docs/CHANGELOG.md](docs/CHANGELOG.md): 整理记录

## RTL

- `Digital_process/Digital_process.srcs/sources_1/new/fpga_top_wrapper.sv`
- `Digital_process/Digital_process.srcs/sources_1/new/sar_calib_ctrl_serial.sv`
- `Digital_process/Digital_process.srcs/sources_1/new/sar_reconstruction.sv`
- `Digital_process/Digital_process.srcs/sources_1/new/sar_adc_controller.sv`
- `Digital_process/Digital_process.srcs/sources_1/new/flash_decoder_adder.sv`
- `Digital_process/Digital_process.srcs/sources_1/new/virtual_adc_phy.v`

## Verification

- `Digital_process/Digital_process.srcs/sim_1/new/tb_sar_adc_top.sv`
- `Digital_process/Digital_process.srcs/sim_1/new/tb_sar_recon.sv`
- `Digital_process/Digital_process.srcs/sim_1/new/tb_gain_comp_check_lsb.sv`
- `Digital_process/Digital_process.srcs/sim_1/new/tb_flash_decoder.sv`

## Constraint

- `Digital_process/Digital_process.srcs/constrs_1/new/sar_calib_fpga.xdc`

## Archive

历史完整整理版不再保留在工作树中，使用 Git 标签查看：

```bash
git checkout archive/full-project-before-core-prune
```
