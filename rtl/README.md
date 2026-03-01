# RTL 代码目录

## 📋 目录概览

本目录包含所有**可综合的 RTL 代码**，按照功能模块进行分类组织。

## 🏗️ 模块分类

```
rtl/
├── calibration/       # 校准模块 - 递归测量电容权重
├── reconstruction/    # 重构模块 - 使用校准权重进行加权求和
├── sar_logic/         # SAR 逻辑 - 逐次逼近控制
├── decoder/           # 译码器 - 热码转二进制
└── top/               # 顶层模块 - 系统集成
```

## 📦 核心模块说明

### 1. 校准模块 (calibration/)
**功能**：实现 Split-Sampling SAR ADC 的前台递归校准算法

- **核心文件**：[sar_calib_ctrl_serial.sv](calibration/sar_calib_ctrl_serial.sv)
- **关键特性**：
  - ✅ 递归测量（从低位到高位）
  - ✅ 串行累加（优化时序）
  - ✅ 偏移消除（(P+N)/2 方法）
  - ✅ MSB 保护（防止溢出）
  - ✅ ASIC 安全初始化

**详细说明**：[calibration/README.md](calibration/README.md)

### 2. 重构模块 (reconstruction/)
**功能**：使用校准后的权重对 SAR 原始数据进行加权求和

- **核心文件**：[sar_reconstruction.sv](reconstruction/sar_reconstruction.sv)
- **关键特性**：
  - ✅ 两级流水线设计
  - ✅ 40 位动态范围
  - ✅ 0.5 LSB 偏移补偿
  - ✅ 动态权重更新
  - ✅ 每时钟周期一个样本

**详细说明**：[reconstruction/README.md](reconstruction/README.md)

### 3. SAR 逻辑 (sar_logic/)
**功能**：SAR ADC 的逐次逼近控制逻辑

- **核心文件**：[sar_adc_controller.sv](sar_logic/sar_adc_controller.sv)
- **关键特性**：
  - ✅ 逐次逼近算法（二分搜索）
  - ✅ 可配置位数
  - ✅ 低延迟设计
  - ✅ 结果验证

**详细说明**：[sar_logic/README.md](sar_logic/README.md)

### 4. 译码器 (decoder/)
**功能**：热码到二进制码的转换 + 加法器

- **核心文件**：[flash_decoder_adder.sv](decoder/flash_decoder_adder.sv)
- **关键特性**：
  - ✅ 高速译码（组合逻辑）
  - ✅ 气泡容错（自动纠正）
  - ✅ 集成加法
  - ✅ 可配置位宽

**详细说明**：[decoder/README.md](decoder/README.md)

### 5. 顶层模块 (top/)
**功能**：FPGA 顶层包装器，集成所有模块

- **核心文件**：[fpga_top_wrapper.sv](top/fpga_top_wrapper.sv)
- **关键特性**：
  - ✅ 独立校准验证
  - ✅ 调试友好（ILA 支持）
  - ✅ 板级验证（引脚映射）
  - ✅ 模块化设计

**详细说明**：[top/README.md](top/README.md)

## 🔧 使用指南

### 在 Vivado 中使用

1. **添加文件到工程**
   ```tcl
   add_files -norecurse rtl/calibration/sar_calib_ctrl_serial.sv
   add_files -norecurse rtl/reconstruction/sar_reconstruction.sv
   add_files -norecurse rtl/sar_logic/sar_adc_controller.sv
   add_files -norecurse rtl/decoder/flash_decoder_adder.sv
   add_files -norecurse rtl/top/fpga_top_wrapper.sv
   ```

2. **设置顶层模块**
   ```tcl
   set_property top fpga_top_wrapper [current_fileset]
   ```

3. **运行综合**
   ```tcl
   launch_runs synth_1
   ```

### 模块实例化示例

```systemverilog
// 校准控制器实例化
sar_calib_ctrl_serial #(
    .CAP_NUM(20),
    .WEIGHT_WIDTH(30),
    .COMP_WAIT_CYC(16),
    .AVG_LOOPS(32)
) u_calib_ctrl (
    .clk(clk),
    .rst_n(rst_n),
    .start_calib(start_calib),
    .calib_done(calib_done),
    .comp_out(comp_out),
    .dac_p_force(dac_p_force),
    .dac_n_force(dac_n_force),
    .w_wr_en(w_wr_en),
    .w_wr_addr(w_wr_addr),
    .w_wr_data(w_wr_data)
);

// 重构引擎实例化
sar_reconstruction #(
    .CAP_NUM(20),
    .WEIGHT_WIDTH(30),
    .OUTPUT_WIDTH(16),
    .FRAC_BITS(8)
) u_recon (
    .clk(clk),
    .rst_n(rst_n),
    .data_valid_in(data_valid),
    .raw_bits(raw_bits),
    .w_wr_en(w_wr_en),
    .w_wr_addr(w_wr_addr),
    .w_wr_data(w_wr_data),
    .adc_dout(adc_dout),
    .data_valid_out(data_valid_out)
);
```

## 📊 设计参数

### 全局参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| CAP_NUM | 20 | 电容总位数 |
| WEIGHT_WIDTH | 30 | 权重位数（有符号，Q22.8 格式） |
| OUTPUT_WIDTH | 16 | 输出数据位数 |
| FRAC_BITS | 8 | 权重小数位数 |

### 校准模块参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| COMP_WAIT_CYC | 16 | 比较器/DAC 稳定等待周期 |
| AVG_LOOPS | 32 | 平均次数（2 的幂） |
| MAX_CALIB_BIT | 5 | 预校准 LSB 最高位 |

### 重构模块参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| GROUP_SIZE | 5 | 部分累加分组大小 |
| TOTAL_SHIFT | FRAC_BITS | 总移位数 |

## 🎯 设计最佳实践

### 1. 参数化设计
- 使用 `parameter` 定义可配置参数
- 便于模块复用和扩展
- 保持参数命名一致性

### 2. 同步设计
- 所有时序逻辑使用同一时钟域
- 使用同步复位或异步复位同步释放
- 避免门控时钟

### 3. 时序优化
- 关键路径插入流水线寄存器
- 使用串行累加减少组合逻辑
- 合理约束时序

### 4. 可测试性
- 添加必要的调试信号
- 预留 ILA 探针接口
- 编写完整的测试平台

### 5. 代码规范
- 遵循 SystemVerilog 编码规范
- 添加清晰的注释
- 使用有意义的信号命名

## 🔍 调试技巧

### 仿真调试
1. 使用对应的测试平台
2. 观察关键内部信号
3. 对比理论值和实际值
4. 检查边界条件

### FPGA 调试
1. 添加 ILA 探针
2. 设置合适的触发条件
3. 捕获关键波形
4. 分析时序关系

### 常见问题

#### Q1: 校准不收敛
- 检查比较器稳定时间（COMP_WAIT_CYC）
- 验证 DAC 设置是否正确
- 观察 comp_out 信号是否有毛刺

#### Q2: 重构输出错误
- 检查权重 RAM 是否正确写入
- 验证 raw_bits 输入格式
- 检查流水线延迟

#### Q3: 时序不收敛
- 添加流水线寄存器
- 优化关键路径
- 调整时序约束

## 📚 相关文档

- [项目总览](../README.md)
- [代码结构](../docs/CODE_STRUCTURE.md)
- [项目分析](../docs/PROJECT_ANALYSIS.md)
- [约束文件](../constraints/README.md)

## 📝 版本信息

- **版本**：v3.0
- **更新日期**：2026-03-01
- **适用工程**：SAR ADC 数字处理系统

## 👥 作者

Zhao Yi <717880671@qq.com>
