# 工具脚本

## 功能描述

本目录包含项目开发和维护所需的工具脚本。

## 文件列表

### fix_git_config.ps1
Git 配置修复脚本，用于设置正确的 Git 作者信息。

**功能**：
- 设置全局 Git 用户名和邮箱
- 设置本地仓库 Git 配置
- 验证配置是否正确

**使用方法**：
```powershell
powershell -ExecutionPolicy Bypass -File fix_git_config.ps1
```

## 脚本说明

### fix_git_config.ps1
```powershell
# 设置 Git 全局配置
git config --global user.name "Zhao Yi"
git config --global user.email "717880671@qq.com"

# 设置本地仓库配置
git config user.name "Zhao Yi"
git config user.email "717880671@qq.com"
```

## 添加新脚本

### 仿真运行脚本 (建议添加)
创建 `run_simulation.bat`：
```batch
@echo off
echo ========================================
echo SAR ADC Simulation Runner
echo ========================================
echo.

echo Running Top Level Simulation...
xsim work.tb_sar_adc_top -view wave_config.tcl

echo.
echo Simulation completed!
pause
```

### 综合脚本 (建议添加)
创建 `run_synthesis.tcl`：
```tcl
# Vivado 综合脚本
open_project Digital_process.xpr
reset_run synth_1
launch_runs synth_1
wait_on_run synth_1
puts "Synthesis completed!"
```

### 实现脚本 (建议添加)
创建 `run_implementation.tcl`：
```tcl
# Vivado 实现脚本
open_project Digital_process.xpr
reset_run impl_1
launch_runs impl_1
wait_on_run impl_1
puts "Implementation completed!"
```

## 脚本开发指南

### 命名约定
- PowerShell 脚本：`.ps1`
- 批处理脚本：`.bat`
- Tcl 脚本：`.tcl`
- Python 脚本：`.py`

### 文档要求
每个脚本应包含：
- 功能说明
- 使用方法
- 参数说明（如有）
- 依赖项（如有）

### 错误处理
脚本应包含适当的错误处理：
```powershell
try {
    # 主要逻辑
} catch {
    Write-Error "Error occurred: $_"
    exit 1
}
```

## 安全提示

1. **执行权限**：确保脚本有适当的执行权限
2. **代码审查**：执行前审查脚本内容
3. **备份数据**：重要操作前备份相关文件
4. **环境检查**：检查脚本运行环境要求

## 相关文档

- [项目分析文档](../docs/PROJECT_ANALYSIS.md)
- [README](../README.md)
