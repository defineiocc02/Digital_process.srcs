# SAR ADC 数字处理系统

## 📋 项目简介

本工程实现了 **Split-Sampling SAR ADC 的数字后端处理系统**，包含两大核心功能：

- **校准 (Calibration)**：递归测量电容权重，实现高精度校准
- **重构 (Reconstruction)**：使用校准权重对 SAR 原始数据进行加权求和，输出 16 位数字码

## 🏗️ 目录结构

```
Digital_process.srcs/
├── README.md                    # 项目主说明
├── Docs/                        # 项目文档
│   ├── README.md                # 文档索引
│   ├── FILE_STRUCTURE_EXPLANATION.md
│   ├── MIGRATION_GUIDE.md
│   ├── MIGRATION_REPORT.md
│   └── TB_REPORT_IMPLEMENTATION_SUMMARY.md
├── Reports/                     # 项目报告
│   ├── project_report_v1.0.md
│   └── VERSION_MANAGEMENT.md
├── test_reports/                # 测试报告输出
│   ├── README.md
│   └── TB_REPORT_SPEC.md
├── REFERENCE/                   # 参考文献
│   └── README.md
├── scripts/                     # 脚本工具
│   ├── README.md
│   ├── automated_migration.ps1
│   ├── sync_backup_vivado.ps1
│   └── verify_consistency.ps1
├── backup_chinese/              # 备份文件夹（中文注释）
│   ├── rtl/                     # RTL 代码
│   ├── testbenches/             # TB 文件
│   ├── sim_models/              # 仿真模型
│   └── constraints/             # 约束文件
├── sources_1/                   # Vivado RTL 源文件（英文注释）
├── sim_1/                       # Vivado 仿真源文件（英文注释）
├── constrs_1/                   # Vivado 约束文件（英文注释）
└── vivado_project/              # Vivado 工程文件
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

### 文档索引
- **完整文档索引**：[Docs/README.md](Docs/README.md) - 📋 所有文档的分类索引

### 核心文档
- **文件结构说明**：[Docs/FILE_STRUCTURE_EXPLANATION.md](Docs/FILE_STRUCTURE_EXPLANATION.md) - 🌳 完整的文件结构和使用指南
- **项目报告**：[Reports/project_report_v1.0.md](Reports/project_report_v1.0.md) - 📊 详细的技术报告
- **迁移指南**：[Docs/MIGRATION_GUIDE.md](Docs/MIGRATION_GUIDE.md) - 🚀 项目迁移步骤
- **TB 报告规范**：[test_reports/TB_REPORT_SPEC.md](test_reports/TB_REPORT_SPEC.md) - 📝 TB 测试报告规范

### 快速参考
- **脚本工具**：[scripts/README.md](scripts/README.md) - 🛠️ 自动化脚本使用说明
- **版本管理**：[Reports/VERSION_MANAGEMENT.md](Reports/VERSION_MANAGEMENT.md) - 📋 版本管理规范
- **参考文献**：[REFERENCE/README.md](REFERENCE/README.md) - 📚 学术参考资料

## 🔧 使用指南

### 校准流程
1. 启动 FPGA，按下复位按钮
2. 打开启动开关 (start_sw)，开始校准
3. 等待完成指示灯 (done_led) 亮起

### 正常工作模式
1. 提供真实 ADC 的 raw_bits 输入
2. 重构模块使用已校准权重计算输出
3. 观察 adc_dout 输出

## 📝 版本管理

### 当前版本
- **版本号**：v3.1.0
- **发布日期**：2026-03-05
- **状态**：Stable (稳定版)
- **适用工程**：SAR ADC 数字处理系统

### 版本历史

#### v3.1.0 (2026-03-05) - 注释优化版
- ✅ 完成所有 Vivado 相关文件的注释英文转换
- ✅ 防止 Vivado 打开文件时出现乱码问题
- ✅ 转换 sources_1/new/ 中 5 个 RTL 文件
- ✅ 转换 sim_1/new/ 中 6 个仿真文件
- ✅ 验证所有文件无中文注释
- ✅ 删除临时脚本 fix_git_config.ps1

#### v3.0.0 (2026-03-01) - 代码重组版
- ✅ 完成代码结构重组，按功能模块分类
- ✅ 创建 organized_code 目录，方便整体迁移
- ✅ 添加完整的文档说明（17 个 README 文件）
- ✅ 保留原有目录结构，确保向后兼容
- ✅ 规范化版本管理和时间戳

#### v2.0.0 (2026-02-22) - 功能优化版
- ✅ 添加串行累加优化，改善时序收敛
- ✅ 增强 ASIC 兼容性，添加复位初始化
- ✅ 优化权重计算逻辑
- ✅ 完善测试平台

#### v1.0.0 (2026-02-15) - 初始版本
- ✅ 实现基本校准算法
- ✅ 实现重构引擎
- ✅ 完成 FPGA 板级验证

### 版本命名规范
采用语义化版本号：`主版本号。次版本号.修订号`
- **主版本号**：不兼容的 API 修改
- **次版本号**：向下兼容的功能性新增
- **修订号**：向下兼容的问题修正

## 👥 作者

**Zhao Yi**  
邮箱：717880671@qq.com

## 📄 许可证

本项目用于学术研究和教学目的。

## 📅 时间戳规范

本项目所有文档和代码文件的时间戳遵循以下规范：
- **格式**：YYYY-MM-DD (ISO 8601)
- **时区**：CST (China Standard Time, UTC+8)
- **更新记录**：在文档末尾或版本历史中记录

---

*最后更新时间：2026-03-05*
