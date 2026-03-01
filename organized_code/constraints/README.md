# 约束文件

## 功能描述

本目录包含 FPGA 综合和实现所需的约束文件。

## 文件列表

### sar_calib_fpga.xdc
FPGA 校准模块的约束文件，包含：

1. **时序约束**
   - 时钟约束：20ns (50MHz)
   - 输入/输出延迟约束

2. **引脚约束**
   - 时钟引脚分配
   - 复位按键引脚
   - 开关输入引脚
   - LED 输出引脚

3. **ILA 调试约束**
   - ILA 核心配置
   - 探针信号定义
   - 触发条件设置

4. **FPGA 配置约束**
   - 配置电压设置
   - CFGBVS 设置

## 约束详解

### 时钟约束
```xdc
create_clock -period 20.000 -name sys_clk_pin [get_ports clk]
```
- 时钟周期：20ns (50MHz)
- 时钟名称：sys_clk_pin

### 引脚分配
| 信号 | 引脚 | IOSTANDARD | 说明 |
|------|------|------------|------|
| clk | Y18 | LVCMOS33 | 系统时钟 |
| rst_n_btn | F15 | LVCMOS33 | 复位按键 |
| start_sw | G22 | LVCMOS33 | 启动开关 |
| done_led | M22 | LVCMOS33 | 完成指示灯 |

### ILA 调试配置
- 数据深度：1024
- 探针数量：多个（根据需求配置）
- 触发类型：数据和控制触发

## 使用方法

### 在 Vivado 中使用
1. 打开 Vivado 工程
2. 添加约束文件到工程
3. 运行综合和实现
4. 生成比特流

### 修改约束
根据实际 FPGA 板卡修改引脚分配：
```xdc
set_property PACKAGE_PIN <PIN_NUMBER> [get_ports <PORT_NAME>]
set_property IOSTANDARD <IO_STANDARD> [get_ports <PORT_NAME>]
```

## 注意事项

1. **引脚兼容性**：确保引脚分配与 FPGA 板卡兼容
2. **时序收敛**：检查时序报告，确保满足时序要求
3. **ILA 资源**：ILA 会占用 FPGA 资源，合理配置探针数量
4. **电压标准**：确保 IOSTANDARD 与外部电路匹配

## 调试技巧

- 使用 ILA 观察关键信号
- 添加必要的时序例外约束
- 对高速信号添加时序约束
- 检查电源和地引脚配置

## 相关文档

- [顶层模块文档](../rtl/top/README.md)
- [项目分析文档](../docs/PROJECT_ANALYSIS.md)
