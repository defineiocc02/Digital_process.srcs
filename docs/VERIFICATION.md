# Verification

## Kept Testbenches

| Testbench | Target |
| --- | --- |
| `tb_sar_recon.sv` | `sar_reconstruction` |
| `tb_gain_comp_check_lsb.sv` | `sar_calib_ctrl_serial` |

## Vivado

默认 simulation top 为 `tb_sar_recon`。校准验证时，在 Vivado 中切换 simulation top 到 `tb_gain_comp_check_lsb`。

## Local Status

当前命令行环境未发现 `vivado`、`xsim`、`verilator` 或 `iverilog`，本轮执行的是静态引用检查：

- `.xpr` 引用文件存在性检查。
- RTL/TB 文件集检查。
- Git 跟踪文件集检查。
