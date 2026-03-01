# SAR ADC 数字处理系统

## 📋 项目简介

本工程实现了 **Split-Sampling SAR ADC 的数字后端处理系统**，包含两大核心功能：

- **校准 (Calibration)**：递归测量电容权重，实现高精度校准
- **重构 (Reconstruction)**：使用校准权重对 SAR 原始数据进行加权求和，输出 16 位数字码

## 🏗️ 目录结构

```
├── rtl/                    # 核心 RTL 代码（可综合）
│   ├── calibration/       # 校准模块
│   ├── reconstruction/    # 重构模块
│   ├── sar_logic/         # SAR 逻辑控制
│   ├── decoder/           # Flash 译码器
│   └── top/               # 顶层模块
│
├── sim_models/            # 仿真模型（不可综合）
│
├── testbenches/           # 测试平台
│   ├── top_level/         # 顶层系统测试
│   ├── calibration/       # 校准模块测试
│   ├── reconstruction/    # 重构模块测试
│   ├── decoder/           # 译码器测试
│   └── common/            # 公共测试文件
│
├── constraints/           # 约束文件
├── scripts/               # 工具脚本
├── docs/                  # 技术文档
└── vivado_project/        # Vivado 工程文件
```

## 🚀 快速开始

### 1. 打开 Vivado 工程
```bash
# 在 Vivado 中打开工程
Digital_process.xpr
```

### 2. 运行仿真
```bash
# 进入仿真目录
cd testbenches/top_level

# 在 Vivado 中运行 tb_sar_adc_top
```

### 3. 综合与实现
```bash
# 在 Vivado 中运行综合和实现
# 约束文件位于 constraints/
```

## 📦 核心模块说明

### 校准控制器 (rtl/calibration/)
- **文件**：`sar_calib_ctrl_serial.sv`
- **功能**：实现递归校准算法，测量各比特权重
- **关键特性**：
  - 串行累加优化时序
  - MSB 保护逻辑
  - 偏移消除技术
  - ASIC 安全初始化

### 重构引擎 (rtl/reconstruction/)
- **文件**：`sar_reconstruction.sv`
- **功能**：使用校准权重对 raw_bits 加权求和
- **关键特性**：
  - 两级流水线设计
  - 40 位动态范围
  - 0.5 LSB 偏移补偿
  - 动态权重更新

### SAR 控制器 (rtl/sar_logic/)
- **文件**：`sar_adc_controller.sv`
- **功能**：SAR 转换控制逻辑

### Flash 译码器 (rtl/decoder/)
- **文件**：`flash_decoder_adder.sv`
- **功能**：热码转二进制 + 加法器

## 📊 技术参数

| 参数 | 值 | 说明 |
|------|-----|------|
| CAP_NUM | 20 | 电容总位数 |
| WEIGHT_WIDTH | 30 | 权重位数（有符号） |
| OUTPUT_WIDTH | 16 | 输出数据位数 |
| FRAC_BITS | 8 | 权重小数位数 |
| AVG_LOOPS | 32 | 校准平均次数 |

## 📚 文档

- **项目分析**：[docs/PROJECT_ANALYSIS.md](docs/PROJECT_ANALYSIS.md)
- **AI 指南**：[.github/copilot-instructions.md](.github/copilot-instructions.md)

## 🔧 使用指南

### 校准流程
1. 启动 FPGA，按下复位按钮
2. 打开启动开关 (start_sw)，开始校准
3. 等待完成指示灯 (done_led) 亮起

### 正常工作模式
1. 提供真实 ADC 的 raw_bits 输入
2. 重构模块使用已校准权重计算输出
3. 观察 adc_dout 输出

## 📝 版本信息

- **版本**：v3.0
- **更新日期**：2026-02-22
- **适用工程**：SAR ADC 数字处理系统

## 👥 作者

- Zhao Yi <717880671@qq.com>

## 📄 许可证

本项目用于学术研究和教学目的。
