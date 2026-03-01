# 校准模块

## 功能描述

实现 Split-Sampling SAR ADC 的前台递归校准算法，测量各比特权重并存储到 Shadow RAM 中。

## 核心文件

- `sar_calib_ctrl_serial.sv` - 校准控制器主模块

## 工作原理

### 校准流程
1. **初始化**：设置目标校准比特，初始化累加器和计数器
2. **P 相测量**：
   - 设置 P 相输入（dac_p_force[target_bit] = 1）
   - 执行 SAR 搜索，找到平衡码
   - 串行计算 P 相权重值
3. **N 相测量**：
   - 设置 N 相输入（dac_n_force[target_bit] = 1）
   - 执行 SAR 搜索，找到平衡码
   - 串行计算 N 相权重值
4. **累加与平均**：累加 P 相和 N 相测量值，重复 AVG_LOOPS 次求平均
5. **更新权重**：计算平均值并写入外部接口和阴影 RAM
6. **迭代**：目标比特递增，重复上述过程直到所有比特校准完成

## 关键特性

- ✅ **递归测量**：从低位到高位依次校准
- ✅ **串行累加**：优化权重计算，减少时序瓶颈
- ✅ **偏移消除**：使用 (P+N)/2 方法消除偏移
- ✅ **MSB 保护**：防止高位校准溢出
- ✅ **ASIC 安全初始化**：复位时初始化默认权重

## 参数配置

| 参数 | 默认值 | 说明 |
|------|--------|------|
| CAP_NUM | 20 | 电容总位数（Bit 0 ~ Bit 19） |
| WEIGHT_WIDTH | 30 | 权重存储位数（Q18.12 格式） |
| COMP_WAIT_CYC | 16 | 比较器/DAC 稳定等待周期 |
| AVG_LOOPS | 32 | 平均次数（必须为 2 的幂） |
| MAX_CALIB_BIT | 5 | 预校准 LSB 最高位 |

## 接口说明

### 输入信号
- `clk` - 系统时钟
- `rst_n` - 异步复位（低电平有效）
- `start_calib` - 校准启动信号
- `comp_out` - 比较器输出结果

### 输出信号
- `calib_done` - 校准完成标志
- `calib_mode_en` - 校准模式使能指示
- `dac_p_force` - P 路 DAC 强制控制信号
- `dac_n_force` - N 路 DAC 强制控制信号
- `w_wr_en` - 权重写使能
- `w_wr_addr` - 权重写地址
- `w_wr_data` - 权重写数据（30-bit 有符号）

## 设计注意事项

1. **MSB 保护**：对于 Bit 18/19 的校准，需要额外添加低位权重以防止溢出
2. **时序优化**：权重计算在 S_PHASE_x_CALC 状态中串行完成，避免 CAP_NUM 级加法器时序瓶颈
3. **权重初始化**：Shadow RAM 在复位时自动加载标准权重值，确保 ASIC 兼容性

## 测试平台

- `testbenches/calibration/tb_gain_comp_check_lsb.sv` - 校准精度验证

## 相关文档

- [项目分析文档](../../docs/PROJECT_ANALYSIS.md)
