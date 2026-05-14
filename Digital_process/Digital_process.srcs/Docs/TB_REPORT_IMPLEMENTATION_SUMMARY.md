# TB 报告自动保存功能实施总结

## 📋 项目概述

**任务目标**：将所有 Testbench (TB) 文件的运行报告从终端输出改为自动保存到专门的文件报告文件夹中。

**实施日期**：2026-03-05  
**实施者**：Zhao Yi

---

## ✅ 完成的工作

### 1. 创建报告输出文件夹

**位置**：`test_reports/`

**文件夹结构**：
```
Digital_process.srcs/
└── test_reports/
    ├── README.md                 # 文件夹使用说明
    ├── TB_REPORT_SPEC.md         # TB 报告输出规范
    └── *.txt                     # 测试报告文件
```

**特点**：
- ✅ 集中管理所有 TB 测试报告
- ✅ 不纳入 Git 版本控制（大文件、频繁变化）
- ✅ 包含完整的说明文档

---

### 2. 修改 TB 文件 - tb_gain_comp_check_lsb.sv

**修改内容**：

#### 2.1 添加文件报告功能

```systemverilog
// 文件句柄声明
integer report_file;
string report_filename;

// 初始化时打开文件
initial begin
    $srandom($time);
    report_filename = $sformatf("test_reports/calib_report_%0t.txt", $time);
    report_file = $fopen(report_filename, "w");
    // 写入报告头部
    $fdisplay(report_file, "====================================");
    $fdisplay(report_file, "  SAR ADC CALIBRATION VERIFICATION REPORT");
    $fdisplay(report_file, "  Generated: %t", $time);
end

// 仿真结束时关闭文件
final begin
    if (report_file != 0) begin
        $fclose(report_file);
        $display("|  [INFO]   | Report file saved: %s", report_filename);
    end
end
```

#### 2.2 同步输出到终端和文件

```systemverilog
// 终端输出
$display(" %2d | %12.2f | %13.2f | %12.4f   | %s", 
         i+1, display_phy, display_restored, abs_err_lsb,
         (abs_err_lsb < LIMIT) ? "PASS" : "BAD");

// 文件输出（完全相同的内容）
if (report_file != 0) begin
    $fdisplay(report_file, " %2d | %12.2f | %13.2f | %12.4f   | %s", 
              i+1, display_phy, display_restored, abs_err_lsb,
              (abs_err_lsb < LIMIT) ? "PASS" : "BAD");
end
```

#### 2.3 报告内容

生成的报告包含：
- ✅ 报告头部（测试名称、时间、判定标准）
- ✅ 测试配置（CAP_NUM, MC_RUNS, ABS_ERR_LIMIT）
- ✅ 每次 MC 运行的详细分析
  - 系统增益补偿因子 K
  - 每个电容位的物理值、恢复值、误差、状态
- ✅ 最大残差 INL 误差
- ✅ 最终判定（PASS/FAIL）
- ✅ 测试总结

**报告文件示例**：
```
test_reports/calib_report_12345.txt
```

---

### 3. 同步修改 organized_code 文件夹

**同步规则**：
> sim_1/ 和 organized_code/ 中的 TB 文件必须保持**完全一致**！

**同步的 TB 文件**：

| TB 文件 | sim_1 位置 | organized_code 位置 | 同步状态 |
|---------|------------|---------------------|----------|
| tb_gain_comp_check_lsb.sv | sim_1/new/ | organized_code/testbenches/calibration/ | ✅ 已同步 |
| tb_sar_recon.sv | sim_1/new/ | organized_code/testbenches/reconstruction/ | ✅ 已同步 |
| tb_sar_adc_top.sv | sim_1/new/ | organized_code/testbenches/top_level/ | ✅ 已同步 |
| tb_flash_decoder.sv | sim_1/new/ | organized_code/testbenches/decoder/ | ✅ 已同步 |

**同步脚本**：
```powershell
Get-ChildItem -Path "sim_1\new" -Filter "tb_*.sv" | ForEach-Object {
    $destPath = $_.FullName -replace 'sim_1\\new', 'organized_code\testbenches'
    $destDir = Split-Path $destPath -Parent
    if (!(Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Copy-Item $_.FullName -Destination $destPath -Force
    Write-Host "Copied $($_.Name) to $destPath"
}
```

---

### 4. 创建规范文档

#### 4.1 TB 报告输出规范 (TB_REPORT_SPEC.md)

**内容**：
- ✅ 核心要求（报告位置、命名规范、内容要求）
- ✅ 代码实现规范（文件句柄、打开/关闭、数据写入）
- ✅ 已实施的 TB 文件列表
- ✅ 同步规范（重要规则、同步流程、同步脚本）
- ✅ 验证清单
- ✅ 示例报告
- ✅ 未来改进方向

**作用**：
- 为所有 TB 文件提供统一的报告输出标准
- 确保 sim_1 和 organized_code 文件夹的 TB 文件保持一致
- 方便新成员快速了解报告输出规范

#### 4.2 test_reports 文件夹说明 (README.md)

**内容**：
- ✅ 文件夹说明
- ✅ 文件组织（报告类型、命名规则）
- ✅ 报告格式（标准结构、示例）
- ✅ 使用说明（运行 TB、查看报告、管理文件）
- ✅ 数据分析（MATLAB/Python导入示例）
- ✅ 相关文档链接
- ✅ 注意事项
- ✅ 自动化脚本示例

**作用**：
- 帮助用户了解 test_reports 文件夹的用途
- 提供报告管理和分析的指导
- 包含实用的命令行脚本

---

## 📊 报告文件命名规则

**格式**：
```
<类型>_<时间戳>.txt
```

**具体实现**：

| TB 文件 | 报告前缀 | 完整命名示例 |
|---------|----------|--------------|
| tb_gain_comp_check_lsb.sv | `calib_report_` | `calib_report_12345.txt` |
| tb_sar_recon.sv | `recon_data_` | `recon_data_67890.txt` |
| tb_sar_adc_top.sv | `top_level_` | `top_level_11223.txt` |
| tb_flash_decoder.sv | `decoder_` | `decoder_44556.txt` |

**时间戳**：使用 SystemVerilog 的 `$time` 系统函数，确保唯一性。

---

## 🔧 技术实现细节

### 文件操作流程

```
┌─────────────┐
│ initial 块  │
│ 打开文件    │
│ 写入头部    │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 测试执行    │
│ $display    │───► 终端输出
│ $fdisplay   │───► 文件输出
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ final 块    │
│ 关闭文件    │
│ 显示保存信息│
└─────────────┘
```

### 关键代码模式

```systemverilog
// 1. 声明文件句柄
integer report_file;
string report_filename;

// 2. initial 块打开文件
initial begin
    $srandom($time);
    report_filename = $sformatf("test_reports/<type>_%0t.txt", $time);
    report_file = $fopen(report_filename, "w");
    if (report_file == 0) begin
        $display("|  [ERROR]  | Cannot create report file");
    end else begin
        $display("|  [INFO]   | Report file created");
        // 写入头部
    end
end

// 3. 测试过程中写入数据
if (report_file != 0) begin
    $fdisplay(report_file, "数据行");
end

// 4. final 块关闭文件
final begin
    if (report_file != 0) begin
        $fclose(report_file);
        $display("|  [INFO]   | Report file saved");
    end
end
```

---

## 📈 报告示例

### 校准测试报告

```
==========================================================================
  SAR ADC CALIBRATION VERIFICATION REPORT
  Generated: 12345
  Criterion: Absolute Error < 0.5 LSB
==========================================================================

Test Configuration:
  CAP_NUM: 20
  MC_RUNS: 5
  ABS_ERR_LIMIT: 0.50 LSB

==========================================================================
Run 0 Analysis
==========================================================================
System Gain Compensation Factor (K): 1.023456
--------------------------------------------------------------------------
Bit | Phy Val(LSB) | Restored(LSB) | Abs Error(LSB) | Status
----|--------------|---------------|----------------|--------
  7 |        33.53 |         33.51 |         0.0200   | PASS
  8 |        67.05 |         67.08 |         0.0300   | PASS
  9 |       134.10 |        134.15 |         0.0500   | PASS
 10 |       268.20 |        268.18 |         0.0200   | PASS
...
--------------------------------------------------------------------------
Max Residual INL Error: 0.0450 LSB
RESULT: PASS (Design is Production Ready)

==========================================================================
FINAL SUMMARY
==========================================================================
All 5 MC runs completed
```

### 重构数据报告

```
12345
-6789
23456
-1234
56789
...
```
（每行一个 16-bit ADC 输出样本，便于 MATLAB 导入）

---

## 🎯 验证方法

### 1. 运行 TB 测试

在 Vivado 中运行仿真：
```tcl
launch_simulation
run all
```

### 2. 检查报告文件

```powershell
# 查看生成的报告文件
Get-ChildItem test_reports\ -OrderDescending

# 打开最新报告
notepad test_reports\calib_report_*.txt
```

### 3. 验证内容

- ✅ 报告头部完整
- ✅ 测试数据齐全
- ✅ 格式正确对齐
- ✅ PASS/FAIL 标识清晰
- ✅ 总结信息完整

---

## ⚠️ 注意事项

### 1. 文件夹存在性

确保 `test_reports/` 文件夹存在，否则 TB 会报错：
```powershell
if (!(Test-Path "test_reports")) {
    New-Item -ItemType Directory -Path "test_reports"
}
```

### 2. 文件权限

确保有写入权限，避免文件打开失败。

### 3. 磁盘空间

大量测试可能生成大量报告文件，定期清理：
```powershell
# 保留最近 10 个报告
Get-ChildItem test_reports\*.txt | Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 | Remove-Item
```

### 4. Git 版本控制

`test_reports/` 文件夹不纳入 Git 版本控制：
```
# .gitignore
test_reports/
*.txt
```

---

## 🚀 后续工作

### 1. 完善其他 TB 文件

- [ ] tb_sar_adc_top.sv - 添加完整报告输出
- [ ] tb_flash_decoder.sv - 添加报告输出功能

### 2. 自动化分析

- [ ] 开发 Python 脚本自动解析报告
- [ ] 生成 INL/DNL 统计图表
- [ ] 自动对比不同版本结果

### 3. CI/CD 集成

- [ ] 与 Jenkins/GitLab CI 集成
- [ ] 自动生成测试报告
- [ ] 邮件通知测试结果

### 4. 报告格式优化

- [ ] 支持 HTML 格式报告
- [ ] 添加图表和可视化
- [ ] 支持 PDF 导出

---

## 📞 联系信息

**项目负责人**：Zhao Yi  
**邮箱**：717880671@qq.com  
**更新日期**：2026-03-05

---

## 📄 相关文档

- **TB 报告输出规范**：`test_reports/TB_REPORT_SPEC.md`
- **test_reports 使用说明**：`test_reports/README.md`
- **项目报告**：`Reports/project_report_v1.0.md`
- **代码组织**：`organized_code/README.md`

---

**实施状态**：✅ 完成  
**测试状态**：待验证  
**文档状态**：✅ 完整
