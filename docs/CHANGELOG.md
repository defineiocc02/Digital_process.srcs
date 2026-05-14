# 整理记录

## 2026-05-15

### 目录整理

- 新增顶层 `README.md` 和 `MOC.md`。
- 新增 `docs/` 工程化说明文档。
- 将旧工程 `sar_adc_project`、`Verifiy` 移入 `archive/legacy_vivado_projects/`。
- 将 `sar_adc_v3.rar` 移入 `archive/binary_snapshots/`。
- 将顶层 MATLAB/查表脚本移入 `matlab/`。
- 新增顶层 `.gitignore`，过滤 Vivado 和仿真生成产物。

### RTL 重构

- `sar_reconstruction.sv`：低 6 位权重改为 reset path 初始化，写权重接口增加地址边界保护。
- `sar_calib_ctrl_serial.sv`：计数器宽度和 MSB 保护位从参数推导，补偿逻辑集中到 `compensated_meas`。
- `virtual_adc_phy.v`：端口、数组和循环改为跟随 `CAP_NUM`。
- `tb_sar_adc_top.sv`：移除对 `u_recon.weight_ram[0:5]` 的手动初始化。
