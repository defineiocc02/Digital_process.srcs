# 测试平台目录

## 📋 目录概览

本目录包含所有模块的**测试平台和验证环境**，按照被测模块的功能进行分类。

## 🏗️ 测试分类

```
testbenches/
├── top_level/         # 顶层系统测试 - 完整信号链验证
├── calibration/       # 校准模块测试 - 校准算法精度验证
├── reconstruction/    # 重构模块测试 - 重构功能验证
├── decoder/           # 译码器测试 - 译码器功能测试
└── common/            # 公共测试文件 - 测试数据和工具
```

## 📦 测试平台说明

### 1. 顶层系统测试 (top_level/)
**测试平台**：[tb_sar_adc_top.sv](top_level/tb_sar_adc_top.sv)

**测试内容**：
- ✅ 完整系统功能验证
- ✅ 校准 + 重构联合测试
- ✅ 线性度测试（INL/DNL）
- ✅ 性能指标评估

**测试方法**：
1. 运行校准算法
2. 使用校准后的权重进行重构
3. 扫描输入电压范围
4. 分析输出码的线性度

**详细说明**：[top_level/README.md](top_level/README.md)

### 2. 校准模块测试 (calibration/)
**测试平台**：[tb_gain_comp_check_lsb.sv](calibration/tb_gain_comp_check_lsb.sv)

**测试内容**：
- ✅ 校准算法精度验证
- ✅ 权重测量误差分析
- ✅ 蒙特卡洛分析
- ✅ 残差统计

**测试方法**：
1. 模拟物理误差（基准误差）
2. 运行 RTL 校准算法
3. 提取校准后的权重
4. 计算增益和偏移系数
5. 应用校正并分析残差

**判定标准**：残差 < 0.5 LSB

**详细说明**：[calibration/README.md](calibration/README.md)

### 3. 重构模块测试 (reconstruction/)
**测试平台**：[tb_sar_recon.sv](reconstruction/tb_sar_recon.sv)

**测试内容**：
- ✅ 重构功能验证
- ✅ 线性度测试
- ✅ 权重更新灵敏度测试
- ✅ 流水线吞吐测试

**测试方法**：
1. 生成理想 SAR 码（`generate_ideal_bits(vin)`）
2. 灌入理想权重（W[i] ∝ 2^(i+4)）
3. 验证输出与理论值的偏差
4. 测试连续输入场景

**详细说明**：[reconstruction/README.md](reconstruction/README.md)

### 4. 译码器测试 (decoder/)
**测试平台**：[tb_flash_decoder.sv](decoder/tb_flash_decoder.sv)

**测试内容**：
- ✅ 正常热码转换测试
- ✅ 气泡错误纠正测试
- ✅ 边界条件测试

**测试用例**：
- 正常热码：000, 001, 011, 111
- 气泡错误：101, 010, 100
- 边界条件：全 0, 全 1

**详细说明**：[decoder/README.md](decoder/README.md)

### 5. 公共测试文件 (common/)
**文件**：
- [adc_recon_sim_data.txt](common/adc_recon_sim_data.txt) - ADC 重构仿真数据

**用途**：
- 存储测试数据
- 提供公共测试函数
- 共享测试配置

**详细说明**：[common/README.md](common/README.md)

## 🔧 使用指南

### 运行仿真

#### Vivado 仿真
1. 打开 Vivado
2. 选择对应的测试平台作为顶层
3. 运行仿真
4. 观察波形和结果

#### 命令行仿真
```bash
# 使用 xsim
xsim work.tb_sar_adc_top -view wave_config.tcl

# 或使用 Tcl 脚本
xsct -exec "source run_simulation.tcl"
```

### 添加新测试平台

#### 目录结构
```
testbenches/
└── <module_name>/
    ├── README.md              # 测试说明
    ├── tb_<module_name>.sv    # 测试平台
    └── wave_config.tcl        # 波形配置
```

#### 测试平台模板
```systemverilog
`timescale 1ns/1ps

module tb_<module_name>;
    // 参数定义
    parameter CLK_PERIOD = 20;
    
    // 信号声明
    reg clk;
    reg rst_n;
    // ... 其他信号
    
    // 被测模块实例化
    <module_name> #(
        .PARAM1(VALUE1),
        .PARAM2(VALUE2)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        // ... 其他端口
    );
    
    // 时钟生成
    always #CLK_PERIOD clk = ~clk;
    
    // 测试任务
    task reset_dut;
        begin
            rst_n = 1'b0;
            repeat(10) @(posedge clk);
            rst_n = 1'b1;
        end
    endtask
    
    // 主测试流程
    initial begin
        // 初始化
        clk = 0;
        rst_n = 0;
        
        // 复位
        reset_dut();
        
        // 测试用例
        // ...
        
        // 结束仿真
        $finish;
    end
    
    // 波形输出
    initial begin
        $dumpfile("tb_<module_name>.vcd");
        $dumpvars(0, tb_<module_name>);
    end
endmodule
```

### 仿真数据导出

#### 导出波形数据
```systemverilog
initial begin
    // 打开 VCD 文件
    $dumpfile("waveform.vcd");
    $dumpvars(0, tb_top);
end
```

#### 导出内存数据
```systemverilog
final begin
    // 写入文件
    $writememh("output_data.txt", data_array);
end
```

#### 导出文本日志
```systemverilog
initial begin
    $display("========================================");
    $display("Simulation Started");
    $display("========================================");
end

always @(posedge clk) begin
    if (data_valid_out) begin
        $display("Time=%0t, Output=%d", $time, adc_dout);
    end
end
```

## 📊 测试覆盖

### 功能覆盖
- ✅ 所有模块都有对应的测试平台
- ✅ 关键功能有专门的测试用例
- ✅ 边界条件测试
- ✅ 异常场景测试

### 代码覆盖
- ✅ 行覆盖（Line Coverage）
- ✅ 条件覆盖（Condition Coverage）
- ✅ 状态机覆盖（FSM Coverage）
- ✅ 翻转覆盖（Toggle Coverage）

### 性能覆盖
- ✅ 时序裕量测试
- ✅ 最大工作频率测试
- ✅ 功耗评估（仿真）

## 🎯 测试最佳实践

### 1. 测试平台设计
- 模块化设计，便于复用
- 参数化配置，适应不同场景
- 自动化验证，减少人工干预
- 详细的日志输出

### 2. 测试用例编写
- 覆盖正常场景和异常场景
- 包含边界条件测试
- 添加性能测试用例
- 使用断言（assertion）验证

### 3. 结果验证
- 自动比对理论值和实际值
- 记录测试通过率
- 生成测试报告
- 保存关键波形

### 4. 回归测试
- 每次修改后运行相关测试
- 维护测试用例库
- 记录历史测试结果
- 跟踪问题修复

## 🔍 调试技巧

### 波形调试
1. 使用 `wave_config.tcl` 加载波形
2. 添加关键信号到波形窗口
3. 设置合适的缩放比例
4. 使用标记（Markers）测量时间

### 数据调试
1. 导出关键数据到文件
2. 使用脚本分析数据
3. 对比理论值和实际值
4. 绘制误差曲线

### 性能调试
1. 测量关键路径延迟
2. 分析时序报告
3. 优化关键代码段
4. 重新运行测试验证

## 📈 测试报告

### 报告内容
- 测试环境说明
- 测试用例列表
- 测试结果统计
- 覆盖率分析
- 问题列表
- 改进建议

### 报告模板
```
========================================
测试报告：<模块名称>
日期：YYYY-MM-DD
版本：vX.X
========================================

1. 测试概述
   - 测试目的
   - 测试范围
   - 测试环境

2. 测试结果
   - 通过用例：X/Y (Z%)
   - 失败用例：详细列表

3. 覆盖率分析
   - 代码覆盖率：X%
   - 功能覆盖率：X%

4. 性能指标
   - 工作频率：X MHz
   - 延迟：X 周期
   - 吞吐率：X 样本/周期

5. 问题列表
   - 问题 1：描述 + 状态
   - 问题 2：描述 + 状态

6. 结论
   - 是否通过测试
   - 后续改进建议
========================================
```

## 📚 相关文档

- [项目总览](../README.md)
- [代码结构](../docs/CODE_STRUCTURE.md)
- [RTL 代码](../rtl/README.md)
- [仿真模型](../sim_models/README.md)

## 📝 版本信息

- **版本**：v3.0
- **更新日期**：2026-03-01
- **适用工程**：SAR ADC 数字处理系统

## 👥 作者

Zhao Yi <717880671@qq.com>
