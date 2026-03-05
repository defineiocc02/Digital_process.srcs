# Test Reports - 测试报告文件夹

## 📋 文件夹说明

本文件夹专门用于存放所有 Testbench (TB) 仿真运行生成的**测试报告**。

**创建时间**：2026-03-05  
**维护者**：Zhao Yi (717880671@qq.com)

---

## 📁 文件组织

### 报告类型

| 报告前缀 | 测试类型 | 来源 TB 文件 | 内容说明 |
|----------|----------|--------------|----------|
| `calib_report_*.txt` | 校准测试 | `tb_gain_comp_check_lsb.sv` | 校准算法验证，INL 误差分析 |
| `recon_data_*.txt` | 重构数据 | `tb_sar_recon.sv` | 16-bit ADC 输出数据（MATLAB 格式） |
| `top_level_*.txt` | 顶层测试 | `tb_sar_adc_top.sv` | 完整系统验证报告 |
| `decoder_*.txt` | 译码器测试 | `tb_flash_decoder.sv` | Flash 译码器功能验证 |

### 命名规则

所有报告文件使用时间戳命名，确保唯一性：
```
<类型>_<时间戳>.txt
```

示例：
- `calib_report_12345.txt`
- `recon_data_67890.txt`

---

## 📊 报告格式

### 标准结构

每个报告文件包含以下部分：

1. **报告头部**
   - 测试名称
   - 生成时间
   - 判定标准

2. **测试配置**
   - 参数设置
   - 测试条件

3. **测试数据**
   - 详细测试过程
   - 表格格式数据
   - PASS/FAIL 状态

4. **测试总结**
   - 最大误差统计
   - 最终判定结果
   - 测试完成情况

### 示例

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

--------------------------------------------------------------------------
Bit | Phy Val(LSB) | Restored(LSB) | Abs Error(LSB) | Status
----|--------------|---------------|----------------|--------
  7 |        33.53 |         33.51 |         0.0200   | PASS
  8 |        67.05 |         67.08 |         0.0300   | PASS
...
--------------------------------------------------------------------------
Max Residual INL Error: 0.0450 LSB
RESULT: PASS (Design is Production Ready)
```

---

## 🔧 使用说明

### 运行 TB 生成报告

1. **在 Vivado 中运行仿真**
   ```tcl
   launch_simulation
   run all
   ```

2. **查看生成的报告**
   ```powershell
   Get-ChildItem test_reports\ -OrderDescending | Select-Object -First 5
   ```

3. **分析报告**
   - 使用文本编辑器打开
   - 导入 MATLAB 进行进一步分析
   - 生成统计图表

### 管理报告文件

**查看最新报告**：
```powershell
Get-ChildItem test_reports\calib_report_*.txt | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Notepad
```

**清理旧报告**（保留最近 10 个）：
```powershell
Get-ChildItem test_reports\*.txt | Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 | Remove-Item
```

**统计报告数量**：
```powershell
Get-ChildItem test_reports\*.txt | Measure-Object | Select-Object -ExpandProperty Count
```

---

## 📈 数据分析

### MATLAB 导入示例

```matlab
% 导入重构数据
data = importdata('test_reports/recon_data_12345.txt');

% 绘制 INL 曲线
plot(data);
xlabel('Sample Index');
ylabel('ADC Output (LSB)');
title('Reconstruction Output');

% 计算 INL/DNL
inl = calculate_inl(data);
dnl = calculate_dnl(data);
```

### Python 导入示例

```python
import numpy as np
import matplotlib.pyplot as plt

# 导入数据
data = np.loadtxt('test_reports/recon_data_12345.txt')

# 绘制波形
plt.plot(data)
plt.xlabel('Sample Index')
plt.ylabel('ADC Output (LSB)')
plt.title('Reconstruction Output')
plt.show()
```

---

## 📝 相关文档

- **TB 报告输出规范**：`test_reports/TB_REPORT_SPEC.md`
- **项目报告**：`Reports/project_report_v1.0.md`
- **TB 源文件**：`sim_1/new/` 或 `organized_code/testbenches/`

---

## ⚠️ 注意事项

1. **不要手动编辑报告文件**
   - 报告由 TB 自动生成
   - 手动修改会导致数据不一致

2. **定期备份重要报告**
   - 测试报告可能被新仿真覆盖
   - 重要测试结果应及时归档

3. **报告文件不纳入 Git 版本控制**
   - 报告文件较大且频繁变化
   - 仅保留 TB 源代码的版本管理

4. **确保 test_reports 文件夹存在**
   - TB 运行前检查文件夹是否创建
   - 如不存在，TB 会报错无法创建文件

---

## 🚀 自动化脚本

### 批量生成报告

```powershell
# 运行所有 TB 并生成报告
$tb_files = Get-ChildItem "sim_1\new\tb_*.sv"
foreach ($tb in $tb_files) {
    Write-Host "Running $($tb.Name)..."
    # 添加 Vivado 仿真命令
}
```

### 自动生成统计图表

```python
# 自动分析所有校准报告
import glob
import pandas as pd

reports = glob.glob('test_reports/calib_report_*.txt')
for report in reports:
    # 解析报告
    # 生成图表
    # 保存分析结果
```

---

## 📞 联系信息

如有问题或建议，请联系：
- **维护者**：Zhao Yi
- **邮箱**：717880671@qq.com
- **更新日期**：2026-03-05

---

**最后更新**：2026-03-05
