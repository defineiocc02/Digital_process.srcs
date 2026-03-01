# 公共测试文件

## 功能描述

本目录用于存放公共测试文件、测试工具函数和测试数据。

## 目录内容

### 测试数据文件
- `adc_recon_sim_data.txt` - ADC 重构仿真数据
- 其他测试数据文件

### 测试工具
- 公共测试函数
- 测试辅助模块
- 测试配置脚本

### 波形配置
- `wave_config.tcl` - 波形查看配置
- 其他仿真配置文件

## 使用说明

### 添加测试数据
将测试数据文件放在本目录下，并在测试平台中引用：
```systemverilog
$readmemh("testbenches/common/adc_recon_sim_data.txt", data_array);
```

### 使用公共函数
在测试平台中包含公共函数文件：
```systemverilog
`include "testbenches/common/test_utils.svh"
```

## 文件组织建议

- 按功能分类存放测试文件
- 使用清晰的命名约定
- 添加必要的注释说明

## 相关文档

- [项目分析文档](../../docs/PROJECT_ANALYSIS.md)
