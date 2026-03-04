# SAR ADC 数字处理系统 - 整理后的代码

## � 目录说明

本目录包含**完整整理后的 SAR ADC 数字处理系统代码**，所有文件按照功能模块清晰组织，方便整体迁移和新项目使用。

## 📁 目录结构

```
organized_code/
│
├── README.md                          # 项目总览和快速入门
│
├── rtl/                               # 可综合 RTL 代码
│   ├── README.md                      # RTL 代码使用说明
│   ├── calibration/                   # 校准模块
│   │   ├── README.md
│   │   └── sar_calib_ctrl_serial.sv
│   ├── reconstruction/                # 重构模块
│   │   ├── README.md
│   │   └── sar_reconstruction.sv
│   ├── sar_logic/                     # SAR 逻辑控制
│   │   ├── README.md
│   │   └── sar_adc_controller.sv
│   ├── decoder/                       # Flash 译码器
│   │   ├── README.md
│   │   └── flash_decoder_adder.sv
│   └── top/                           # 顶层模块
│       ├── README.md
│       └── fpga_top_wrapper.sv
│
├── sim_models/                        # 仿真模型（不可综合）
│   ├── README.md
│   └── virtual_adc_phy.v
│
├── testbenches/                       # 测试平台
│   ├── README.md
│   ├── top_level/                     # 顶层系统测试
│   │   ├── README.md
│   │   └── tb_sar_adc_top.sv
│   ├── calibration/                   # 校准模块测试
│   │   ├── README.md
│   │   └── tb_gain_comp_check_lsb.sv
│   ├── reconstruction/                # 重构模块测试
│   │   ├── README.md
│   │   └── tb_sar_recon.sv
│   ├── decoder/                       # 译码器测试
│   │   ├── README.md
│   │   └── tb_flash_decoder.sv
│   └── common/                        # 公共测试文件
│       └── README.md
│
├── constraints/                       # 约束文件
│   ├── README.md
│   └── sar_calib_fpga.xdc
│
├── scripts/                           # 工具脚本
│   ├── README.md
│   └── fix_git_config.ps1
│
└── docs/                              # 技术文档
    ├── PROJECT_ANALYSIS.md            # 项目分析文档
    ├── CODE_STRUCTURE.md              # 代码结构指南
    └── MIGRATION_COMPLETE.md          # 重组完成报告
```

## 🚀 快速开始

### 方法 1：直接复制整个目录（推荐）

将整个 `organized_code` 目录复制到你的项目位置：

```bash
# Windows PowerShell
Copy-Item -Path "organized_code" -Destination "D:\Your\Project\Path\" -Recurse

# 或使用文件资源管理器
# 1. 右键点击 organized_code 文件夹
# 2. 选择"复制"
# 3. 导航到目标位置
# 4. 选择"粘贴"
```

### 方法 2：在 Vivado 中创建新工程

1. **打开 Vivado**
   ```bash
   vivado
   ```

2. **创建新工程**
   - File → New Project
   - 选择工程路径和名称
   - 选择 RTL Project

3. **添加源文件**
   ```tcl
   # 在 Tcl 控制台中运行
   add_files -norecurse rtl/calibration/sar_calib_ctrl_serial.sv
   add_files -norecurse rtl/reconstruction/sar_reconstruction.sv
   add_files -norecurse rtl/sar_logic/sar_adc_controller.sv
   add_files -norecurse rtl/decoder/flash_decoder_adder.sv
   add_files -norecurse rtl/top/fpga_top_wrapper.sv
   ```

4. **添加约束文件**
   ```tcl
   add_files -fileset constrs_1 constraints/sar_calib_fpga.xdc
   ```

5. **设置顶层模块**
   ```tcl
   set_property top fpga_top_wrapper [current_fileset]
   ```

6. **运行综合和实现**
   ```tcl
   launch_runs synth_1
   wait_on_run synth_1
   launch_runs impl_1
   wait_on_run impl_1
   ```

### 方法 3：使用 Tcl 脚本自动创建

创建 `create_project.tcl` 脚本：

```tcl
# 工程配置
set project_name "SAR_ADC_Digital"
set project_path "D:/Your/Project/Path"

# 创建工程
create_project $project_name $project_path -part xc7a35ticsg324-1L

# 添加源文件
add_files -norecurse [glob ../organized_code/rtl/*/*.sv]
add_files -norecurse ../organized_code/sim_models/virtual_adc_phy.v

# 添加约束
add_files -fileset constrs_1 ../organized_code/constraints/sar_calib_fpga.xdc

# 设置顶层
set_property top fpga_top_wrapper [current_fileset]

# 完成
puts "Project created successfully!"
```

运行脚本：
```bash
vivado -source create_project.tcl
```

## 📋 文件清单

### 核心 RTL 模块（5 个文件）

| 文件 | 功能 | 行数 | 说明 |
|------|------|------|------|
| `sar_calib_ctrl_serial.sv` | 校准控制器 | ~500 | 递归校准算法 |
| `sar_reconstruction.sv` | 重构引擎 | ~300 | 加权求和输出 |
| `sar_adc_controller.sv` | SAR 控制器 | ~200 | 逐次逼近逻辑 |
| `flash_decoder_adder.sv` | Flash 译码器 | ~150 | 热码转二进制 |
| `fpga_top_wrapper.sv` | 顶层包装器 | ~100 | 系统集成 |

### 仿真模型（1 个文件）

| 文件 | 功能 | 说明 |
|------|------|------|
| `virtual_adc_phy.v` | 虚拟 ADC 物理模型 | FPGA 板级验证 |

### 测试平台（4 个文件）

| 文件 | 测试对象 | 测试内容 |
|------|----------|----------|
| `tb_sar_adc_top.sv` | 完整系统 | 端到端功能验证 |
| `tb_gain_comp_check_lsb.sv` | 校准模块 | 校准精度验证 |
| `tb_sar_recon.sv` | 重构模块 | 重构功能验证 |
| `tb_flash_decoder.sv` | 译码器 | 译码器功能测试 |

### 约束文件（1 个文件）

| 文件 | 类型 | 说明 |
|------|------|------|
| `sar_calib_fpga.xdc` | XDC | 时序和引脚约束 |

### 文档（14 个文件）

| 目录 | README 数量 | 说明 |
|------|------------|------|
| 根目录 | 1 | 项目总览 |
| rtl/ | 6 | 模块详细说明 |
| testbenches/ | 6 | 测试平台说明 |
| sim_models/ | 1 | 仿真模型说明 |
| constraints/ | 1 | 约束文件说明 |
| scripts/ | 1 | 脚本说明 |
| docs/ | 3 | 技术文档 |

**总计**：约 30 个文件（包括代码、测试和文档）

## 🎯 使用场景

### 场景 1：新项目开发
直接使用 `organized_code` 目录作为起点：
- 复制整个目录到新项目位置
- 根据需求修改参数
- 添加新的功能模块

### 场景 2：代码复用
选择性使用模块：
- 仅使用校准模块
- 仅使用重构模块
- 组合使用多个模块

### 场景 3：学习和研究
参考代码和文档学习：
- 阅读技术文档了解原理
- 运行仿真验证功能
- 修改参数观察效果

### 场景 4：教学演示
用于课堂教学：
- 展示完整的 FPGA 设计流程
- 讲解 SAR ADC 工作原理
- 演示仿真和验证方法

## 📊 技术参数

### 系统参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 分辨率 | 16-bit | 输出数据位数 |
| 输入位数 | 20-bit | SAR 原始数据 |
| 校准位数 | 20-bit | 电容总位数 |
| 权重格式 | Q22.8 | 30-bit 有符号定点数 |

### 性能指标

| 指标 | 值 | 说明 |
|------|-----|------|
| 校准时间 | ~ms 级 | 取决于 AVG_LOOPS |
| 重构延迟 | 2 周期 | 两级流水线 |
| 工作频率 | >50MHz | 取决于 FPGA 器件 |

### 资源占用（估计）

| 资源 | 用量 | 说明 |
|------|------|------|
| LUT | ~2000 | 组合逻辑 |
| FF | ~1500 | 时序逻辑 |
| BRAM | ~4 | 权重 RAM |
| DSP | ~8 | 乘法累加 |

*注：实际资源占用取决于综合工具和 FPGA 器件*

## 🔧 定制开发

### 修改分辨率
编辑 `rtl/reconstruction/sar_reconstruction.sv`：
```systemverilog
parameter int OUTPUT_WIDTH = 16,  // 修改为 14 或 18
```

### 修改校准精度
编辑 `rtl/calibration/sar_calib_ctrl_serial.sv`：
```systemverilog
parameter int AVG_LOOPS = 32,  // 修改为 16 或 64
```

### 添加新功能
1. 在对应模块目录创建新文件
2. 在顶层模块中实例化
3. 添加对应的测试平台
4. 更新文档说明

## 📚 文档导航

### 快速入门
1. 阅读 [README.md](README.md) 了解项目概览
2. 查看 [rtl/README.md](rtl/README.md) 了解代码结构
3. 运行仿真验证功能

### 深入学习
1. 阅读 [docs/PROJECT_ANALYSIS.md](docs/PROJECT_ANALYSIS.md) 了解技术细节
2. 查看 [docs/CODE_STRUCTURE.md](docs/CODE_STRUCTURE.md) 了解组织方式
3. 参考各模块的 README.md 了解具体实现

### 开发参考
1. 查看测试平台了解使用方法
2. 参考约束文件了解 FPGA 配置
3. 阅读技术文档了解设计决策

## ⚠️ 注意事项

### 1. 文件完整性
确保复制所有文件，包括：
- 源代码文件（.sv, .v）
- 约束文件（.xdc）
- 文档文件（.md）
- 测试平台文件

### 2. Vivado 版本
推荐使用 Vivado 2020.1 或更高版本：
- 支持 SystemVerilog 特性
- 更好的综合优化
- 改进的调试工具

### 3. FPGA 器件
根据实际使用的 FPGA 修改约束文件：
- 引脚分配
- 时钟频率
- IO 标准

### 4. 仿真工具
确保仿真工具支持 SystemVerilog：
- Vivado XSIM
- ModelSim
- VCS

## � 技术支持

### 常见问题

**Q1: 如何修改工作频率？**
修改约束文件 `constraints/sar_calib_fpga.xdc` 中的时钟约束：
```xdc
create_clock -period 20.000 -name sys_clk_pin [get_ports clk]
# 将 20.000 改为你需要的周期（ns）
```

**Q2: 如何添加 ILA 调试核？**
在顶层模块中添加 ILA 实例，参考 `rtl/top/fpga_top_wrapper.sv` 中的注释。

**Q3: 校准结果如何保存？**
校准完成后，通过 `w_wr_data` 接口读取权重值，保存到外部存储器。

### 联系方式

**作者**：Zhao Yi  
**邮箱**：717880671@qq.com

## 📝 版本信息

- **当前版本**：v3.0.0
- **发布日期**：2026-03-01
- **状态**：Stable (稳定版)

## 📄 许可证

本项目用于学术研究和教学目的。

## 📅 时间戳规范

- **日期格式**：YYYY-MM-DD (ISO 8601)
- **时区**：CST (China Standard Time, UTC+8)

---

*最后更新时间：2026-03-01*

## 🎉 开始使用

现在你可以：
1. 复制整个 `organized_code` 目录到你的项目位置
2. 按照快速开始指南创建 Vivado 工程
3. 运行仿真验证功能
4. 开始你的开发工作！

**祝你使用愉快！** 🚀
