# 代码组织结构指南

## 📁 完整目录结构

```
Digital_process.srcs/
│
├── README.md                          # 项目总览和快速入门指南
│
├── rtl/                               # 可综合的 RTL 代码
│   ├── README.md                      # RTL 代码组织说明
│   ├── calibration/                   # 校准模块
│   │   ├── README.md
│   │   └── sar_calib_ctrl_serial.sv   # 校准控制器（核心）
│   │
│   ├── reconstruction/                # 重构模块
│   │   ├── README.md
│   │   └── sar_reconstruction.sv      # 重构引擎（核心）
│   │
│   ├── sar_logic/                     # SAR 逻辑控制
│   │   ├── README.md
│   │   └── sar_adc_controller.sv      # SAR 控制器
│   │
│   ├── decoder/                       # Flash 译码器
│   │   ├── README.md
│   │   └── flash_decoder_adder.sv     # 译码器 + 加法器
│   │
│   └── top/                           # 顶层模块
│       ├── README.md
│       └── fpga_top_wrapper.sv        # FPGA 顶层包装器
│
├── sim_models/                        # 仿真模型（不可综合）
│   ├── README.md
│   └── virtual_adc_phy.v              # 虚拟 ADC 物理模型
│
├── testbenches/                       # 测试平台
│   ├── README.md                      # 测试指南
│   ├── top_level/                     # 顶层系统测试
│   │   ├── README.md
│   │   └── tb_sar_adc_top.sv
│   │
│   ├── calibration/                   # 校准模块测试
│   │   ├── README.md
│   │   └── tb_gain_comp_check_lsb.sv
│   │
│   ├── reconstruction/                # 重构模块测试
│   │   ├── README.md
│   │   └── tb_sar_recon.sv
│   │
│   ├── decoder/                       # 译码器测试
│   │   ├── README.md
│   │   └── tb_flash_decoder.sv
│   │
│   └── common/                        # 公共测试文件
│       ├── README.md
│       └── adc_recon_sim_data.txt
│
├── constraints/                       # 约束文件
│   ├── README.md
│   └── sar_calib_fpga.xdc             # FPGA 约束
│
├── scripts/                           # 工具脚本
│   ├── README.md
│   └── fix_git_config.ps1             # Git 配置修复脚本
│
├── docs/                              # 技术文档
│   ├── PROJECT_ANALYSIS.md            # 项目分析文档
│   └── CODE_STRUCTURE.md              # 本文件
│
├── vivado_project/                    # Vivado 工程文件
│   └── (Digital_process.xpr 等)
│
└── 原始目录 (保留，向后兼容)
    ├── sources_1/new/
    ├── sim_1/new/
    └── constrs_1/new/
```

## 📋 文件分类说明

### 1. 核心 RTL 代码 (rtl/)

#### 校准模块 (calibration/)
- **功能**：递归测量电容权重
- **关键文件**：`sar_calib_ctrl_serial.sv`
- **设计特点**：
  - 串行累加优化时序
  - MSB 保护逻辑
  - 偏移消除技术
  - ASIC 安全初始化

#### 重构模块 (reconstruction/)
- **功能**：使用校准权重进行加权求和
- **关键文件**：`sar_reconstruction.sv`
- **设计特点**：
  - 两级流水线设计
  - 40 位动态范围
  - 0.5 LSB 偏移补偿
  - 动态权重更新

#### SAR 逻辑 (sar_logic/)
- **功能**：SAR 转换控制
- **关键文件**：`sar_adc_controller.sv`
- **设计特点**：
  - 逐次逼近算法
  - 可配置位数
  - 低延迟设计

#### 译码器 (decoder/)
- **功能**：热码转二进制
- **关键文件**：`flash_decoder_adder.sv`
- **设计特点**：
  - 高速译码
  - 气泡容错
  - 集成加法

#### 顶层模块 (top/)
- **功能**：系统集成
- **关键文件**：`fpga_top_wrapper.sv`
- **设计特点**：
  - 独立校准验证
  - 调试友好
  - ILA 支持

### 2. 仿真模型 (sim_models/)

#### 虚拟 ADC 物理模型
- **功能**：模拟比较器行为
- **关键文件**：`virtual_adc_phy.v`
- **用途**：
  - FPGA 板级验证
  - 校准算法调试
  - 无需真实 ADC

### 3. 测试平台 (testbenches/)

#### 顶层系统测试 (top_level/)
- **测试内容**：完整系统功能验证
- **测试平台**：`tb_sar_adc_top.sv`
- **验证项目**：
  - 端到端功能
  - 性能指标
  - 线性度测试

#### 校准模块测试 (calibration/)
- **测试内容**：校准算法精度
- **测试平台**：`tb_gain_comp_check_lsb.sv`
- **验证项目**：
  - 权重测量精度
  - 蒙特卡洛分析
  - 残差分析

#### 重构模块测试 (reconstruction/)
- **测试内容**：重构功能验证
- **测试平台**：`tb_sar_recon.sv`
- **验证项目**：
  - 线性度测试
  - 权重更新测试
  - 流水线吞吐测试

#### 译码器测试 (decoder/)
- **测试内容**：译码器功能
- **测试平台**：`tb_flash_decoder.sv`
- **验证项目**：
  - 正常热码转换
  - 气泡错误纠正
  - 边界条件测试

### 4. 约束文件 (constraints/)

#### FPGA 约束
- **功能**：时序和引脚约束
- **关键文件**：`sar_calib_fpga.xdc`
- **约束类型**：
  - 时钟约束
  - 引脚分配
  - ILA 调试
  - FPGA 配置

### 5. 工具脚本 (scripts/)

#### Git 配置脚本
- **功能**：修复 Git 作者信息
- **关键文件**：`fix_git_config.ps1`
- **用途**：
  - 设置用户名和邮箱
  - 验证配置

### 6. 技术文档 (docs/)

#### 项目分析文档
- **功能**：详细技术分析
- **关键文件**：`PROJECT_ANALYSIS.md`
- **内容**：
  - 系统架构
  - 模块说明
  - 设计细节
  - 使用指南

## 🎯 使用指南

### 快速开始

1. **查看项目概览**
   ```bash
   cat README.md
   ```

2. **打开 Vivado 工程**
   ```bash
   # 在 Vivado 中打开
   vivado Digital_process.xpr
   ```

3. **运行仿真**
   ```bash
   # 在 Vivado 中选择测试平台
   # tb_sar_adc_top (顶层)
   # tb_gain_comp_check_lsb (校准)
   # tb_sar_recon (重构)
   # tb_flash_decoder (译码器)
   ```

4. **综合与实现**
   ```bash
   # 在 Vivado 中运行
   # 综合 → 实现 → 生成比特流
   ```

### 开发流程

#### 添加新模块
1. 在 `rtl/` 下创建相应子目录
2. 添加模块源文件
3. 创建 README.md 说明文档
4. 在 `testbenches/` 下创建对应测试平台

#### 修改现有模块
1. 查看模块 README.md 了解功能
2. 修改源文件
3. 运行对应测试平台验证
4. 更新文档

#### 调试流程
1. 添加 ILA 探针（在顶层模块中）
2. 重新生成比特流
3. 下载到 FPGA
4. 使用 Hardware Manager 观察波形

## 📊 设计层次

```
系统级 (System Level)
├── fpga_top_wrapper.sv (顶层集成)
│
模块级 (Module Level)
├── sar_calib_ctrl_serial.sv (校准)
├── sar_reconstruction.sv (重构)
├── sar_adc_controller.sv (SAR 控制)
└── flash_decoder_adder.sv (译码)
│
测试级 (Test Level)
├── tb_sar_adc_top.sv (系统测试)
├── tb_gain_comp_check_lsb.sv (校准测试)
├── tb_sar_recon.sv (重构测试)
└── tb_flash_decoder.sv (译码器测试)
```

## 🔧 维护建议

### 代码管理
- ✅ 使用 Git 版本控制
- ✅ 每次提交添加清晰的注释
- ✅ 定期备份重要文件
- ✅ 保持目录结构清晰

### 文档维护
- ✅ 及时更新 README.md
- ✅ 记录重要设计决策
- ✅ 添加使用示例
- ✅ 维护变更日志

### 测试覆盖
- ✅ 为每个模块编写测试平台
- ✅ 定期运行回归测试
- ✅ 记录测试结果
- ✅ 维护测试用例库

## 📝 版本历史

### v3.0 (2026-03-01)
- ✅ 完成代码结构重组
- ✅ 添加完整的文档说明
- ✅ 保留原有目录结构（向后兼容）
- ✅ 创建分层目录体系

### v2.0
- ✅ 添加串行累加优化
- ✅ 增强 ASIC 兼容性
- ✅ 优化时序收敛

### v1.0
- ✅ 初始版本
- ✅ 基本校准和重构功能

## 📞 联系方式

- **作者**：Zhao Yi
- **邮箱**：717880671@qq.com
- **项目**：SAR ADC 数字处理系统

## 📄 许可证

本项目用于学术研究和教学目的。
