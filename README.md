# SAR ADC V3 Digital Process

本仓库是 16-bit split-sampling SAR ADC 数字后端工程的整理版，主线目标是让 Vivado 工程、RTL、验证资料、MATLAB 辅助脚本和历史归档有清晰边界，便于后续保存、复现和继续开发。

## 当前结论

- 主工程入口：`Digital_process/Digital_process.xpr`
- Vivado 版本来源：项目文件标注为 Vivado 2018.3
- FPGA 器件：`xc7a35tfgg484-2`
- 顶层模块：`fpga_top_wrapper`
- 主要验证入口：`tb_sar_adc_top`
- 旧工程与大压缩包已移入 `archive/`
- MATLAB 辅助脚本已移入 `matlab/`

## 顶层结构

```text
sar_adc_v3/
├── Digital_process/       # 当前主 Vivado 工程，保持原路径以兼容 .xpr
├── archive/               # 历史工程、二进制快照和归档说明
├── docs/                  # 新整理的工程化说明文档
├── matlab/                # MATLAB 建模、查表和噪声分析脚本
├── MOC.md                 # 项目内容地图
├── README.md              # 顶层入口说明
└── .gitignore             # Vivado/仿真产物忽略规则
```

## 主要源码

```text
Digital_process/Digital_process.srcs/sources_1/new/
├── sar_calib_ctrl_serial.sv   # 前景递归校准控制器
├── sar_reconstruction.sv      # 加权重构与饱和输出
├── sar_adc_controller.sv      # SAR 转换控制器
├── flash_decoder_adder.sv     # 3-bit thermometer 到 binary 译码
└── virtual_adc_phy.v          # 仿真用电容权重/比较器模型
```

```text
Digital_process/Digital_process.srcs/sim_1/new/
├── tb_sar_adc_top.sv
├── tb_sar_recon.sv
├── tb_gain_comp_check_lsb.sv
├── tb_flash_decoder.sv
└── fpga_top_wrapper.sv
```

## 本次整理重点

1. 将可维护源码和 Vivado 生成产物分离，避免把 `.runs/.sim/.cache/.hw` 作为仓库核心内容。
2. 保持 `Digital_process.xpr` 的原工程结构，降低 Vivado 打开失败风险。
3. 重构校准和重构模块的低 6 位权重初始化逻辑，去掉 testbench 对 DUT 内部 RAM 的手动初始化依赖。
4. 将 `virtual_adc_phy` 的端口、数组和循环统一参数化到 `CAP_NUM`。
5. 补充 MOC、需求、架构、验证和目录规范文档。

## 快速使用

1. 用 Vivado 2018.3 打开 `Digital_process/Digital_process.xpr`。
2. 检查 active simulation set 为 `sim_1`，顶层为 `tb_sar_adc_top`。
3. 运行 behavioral simulation 做功能回归。
4. 如需综合/实现，先确认约束文件 `Digital_process/Digital_process.srcs/constrs_1/new/sar_calib_fpga.xdc` 与实际板卡一致。

## 文档入口

- [MOC.md](MOC.md)
- [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/VERIFICATION.md](docs/VERIFICATION.md)
- [docs/PROJECT_ORGANIZATION.md](docs/PROJECT_ORGANIZATION.md)
