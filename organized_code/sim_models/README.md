# 仿真模型

## 功能描述

本目录包含仅用于仿真的模型文件，这些文件不可综合，仅供验证和测试使用。

## 文件列表

### virtual_adc_phy.v
虚拟 ADC 物理模型，用于 FPGA 上闭环验证校准算法。

**功能**：
- 接收 DAC 强制控制信号（dac_p_force/dac_n_force）
- 模拟比较器行为，输出比较结果（comp_out）
- 无需真实 ADC 模拟前端即可验证校准逻辑

**应用场景**：
- FPGA 板级验证
- 校准算法调试
- ILA 波形观察

**接口说明**：
- 输入：`clk`, `rst_n`, `dac_p_force`, `dac_n_force`
- 输出：`comp_out`

## 注意事项

⚠️ **重要**：本目录下的文件仅用于仿真，请勿将其加入综合流程！

## 使用示例

```systemverilog
// 实例化虚拟 ADC 物理模型
virtual_adc_phy #(.CAP_NUM(20)) u_phy (
    .clk(clk),
    .rst_n(rst_n),
    .dac_p_force(dac_p_force),
    .dac_n_force(dac_n_force),
    .comp_out(comp_out)
);
```

## 相关文档

- [校准模块文档](../rtl/calibration/README.md)
- [项目分析文档](../../docs/PROJECT_ANALYSIS.md)
