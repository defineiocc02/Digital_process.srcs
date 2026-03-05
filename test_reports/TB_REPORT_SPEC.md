# TB 报告输出规范

## 📋 规范说明

本规范定义了所有 Testbench (TB) 文件的报告输出行为，确保测试报告统一保存到指定文件夹，便于管理和追溯。

**创建时间**：2026-03-05  
**适用范围**：`sim_1/` 和 `organized_code/testbenches/` 中的所有 TB 文件

---

## 🎯 核心要求

### 1. 报告输出位置

所有 TB 运行报告必须保存到 `test_reports/` 文件夹中，该文件夹位于项目根目录下。

```
Digital_process.srcs/
├── sim_1/
│   └── new/
│       └── tb_*.sv          # TB 源文件
├── organized_code/
│   └── testbenches/
│       └── tb_*.sv          # TB 源文件（同步）
└── test_reports/            # ✅ 统一报告输出目录
    ├── calib_report_*.txt   # 校准测试报告
    ├── recon_data_*.txt     # 重构数据报告
    ├── top_level_*.txt      # 顶层测试报告
    └── decoder_*.txt        # 译码器测试报告
```

### 2. 文件命名规范

报告文件名应包含以下信息：
- **测试类型标识**（calib/recon/top_level/decoder）
- **时间戳**（使用仿真时间 `$time`）
- **文件扩展名**（.txt）

**命名格式**：
```
<test_type>_<timestamp>.txt
```

**示例**：
- `calib_report_12345.txt`
- `recon_data_67890.txt`
- `top_level_sim_11223.txt`

### 3. 报告内容要求

每个报告文件应包含：

#### 3.1 报告头部
```
==========================================================================
  <测试名称> VERIFICATION REPORT
  Generated: <仿真时间>
  Criterion: <判定标准>
==========================================================================
```

#### 3.2 测试配置
```
Test Configuration:
  参数 1: 值 1
  参数 2: 值 2
  ...
```

#### 3.3 测试过程数据
- 每次运行的详细数据
- 表格格式对齐
- PASS/FAIL 状态标识

#### 3.4 测试总结
```
==========================================================================
FINAL SUMMARY
==========================================================================
所有测试完成情况
```

### 4. 代码实现规范

#### 4.1 文件句柄声明

```systemverilog
integer report_file;
string report_filename;
```

#### 4.2 文件打开（initial 块）

```systemverilog
initial begin
    $srandom($time);
    report_filename = $sformatf("test_reports/<type>_%0t.txt", $time);
    report_file = $fopen(report_filename, "w");
    if (report_file == 0) begin
        $display("|  [ERROR]  | Cannot create report file: %s", report_filename);
    end else begin
        $display("|  [INFO]   | Report file created: %s", report_filename);
        // 写入报告头部
        $fdisplay(report_file, "====================================");
        $fdisplay(report_file, "  <TEST NAME> VERIFICATION REPORT");
        $fdisplay(report_file, "  Generated: %t", $time);
        $fdisplay(report_file, "====================================");
    end
end
```

#### 4.3 文件关闭（final 块）

```systemverilog
final begin
    if (report_file != 0) begin
        $fclose(report_file);
        $display("|  [INFO]   | Report file saved: %s", report_filename);
    end
end
```

#### 4.4 数据写入

```systemverilog
// 写入表格数据
if (report_file != 0) begin
    $fdisplay(report_file, " %2d | %12.2f | %13.2f | %12.4f   | %s", 
              i+1, display_phy, display_restored, abs_err_lsb,
              (abs_err_lsb < LIMIT) ? "PASS" : "FAIL");
end
```

---

## 📝 已实施的 TB 文件

### 1. tb_gain_comp_check_lsb.sv

**功能**：SAR ADC 校准算法验证  
**报告类型**：校准测试报告  
**报告文件**：`test_reports/calib_report_<timestamp>.txt`

**报告内容**：
- 测试配置（CAP_NUM, MC_RUNS, ABS_ERR_LIMIT）
- 每次 MC 运行的详细分析
  - 系统增益补偿因子 K
  - 每个电容位的物理值、恢复值、误差、状态
- 最大残差 INL 误差
- 最终判定（PASS/FAIL）

**同步状态**：
- ✅ `sim_1/new/tb_gain_comp_check_lsb.sv`
- ✅ `organized_code/testbenches/calibration/tb_gain_comp_check_lsb.sv`

### 2. tb_sar_recon.sv

**功能**：重构引擎单元测试  
**报告类型**：重构数据报告  
**报告文件**：`test_reports/recon_data_<timestamp>.txt`

**报告内容**：
- 16-bit ADC 输出数据（每行一个样本）
- 用于 MATLAB 后续分析

**同步状态**：
- ✅ `sim_1/new/tb_sar_recon.sv`
- ✅ `organized_code/testbenches/reconstruction/tb_sar_recon.sv`

### 3. tb_sar_adc_top.sv

**功能**：顶层系统验证  
**报告类型**：顶层测试报告  
**报告文件**：`test_reports/top_level_<timestamp>.txt`

**待实施**：需要添加报告输出功能

### 4. tb_flash_decoder.sv

**功能**：Flash 译码器验证  
**报告类型**：译码器测试报告  
**报告文件**：`test_reports/decoder_<timestamp>.txt`

**待实施**：需要添加报告输出功能

---

## 🔄 同步规范

### 重要规则

> **sim_1/** 和 **organized_code/** 中的 TB 文件必须保持**完全一致**！

### 同步流程

1. **修改源文件**：在 `sim_1/new/` 中修改 TB 文件
2. **自动同步**：使用脚本自动复制到 `organized_code/testbenches/`
3. **验证一致性**：检查两个位置的文件是否完全相同

### 同步脚本

```powershell
# 同步所有 TB 文件
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

## ✅ 验证清单

在提交 TB 修改前，请确认：

- [ ] 报告输出路径为 `test_reports/`
- [ ] 文件名包含时间戳
- [ ] 报告头部包含测试名称和时间
- [ ] 报告内容包含配置、数据、总结
- [ ] 使用 `initial` 打开文件
- [ ] 使用 `final` 关闭文件
- [ ] 所有 `$display` 都有对应的 `$fdisplay`
- [ ] sim_1 和 organized_code 文件已同步
- [ ] 测试运行后报告文件正确生成

---

## 📊 示例报告

### 校准测试报告示例

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
 ...
--------------------------------------------------------------------------
Max Residual INL Error: 0.0450 LSB
RESULT: PASS (Design is Production Ready)

==========================================================================
FINAL SUMMARY
==========================================================================
All 5 MC runs completed
```

---

## 🚀 未来改进

1. **自动化报告分析**：开发脚本自动解析报告并生成统计图表
2. **HTML 格式报告**：支持生成可读性更好的 HTML 报告
3. **回归测试对比**：自动对比不同版本的测试结果
4. **CI/CD 集成**：与持续集成系统集成，自动生成测试报告

---

## 📞 联系方式

如有疑问或建议，请联系：
- **维护者**：Zhao Yi
- **邮箱**：717880671@qq.com
- **更新日期**：2026-03-05
