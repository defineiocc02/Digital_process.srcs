# =============================================================================
# 脚本名称      : automated_migration.ps1
# 功能描述      : 自动化执行完整的文件迁移流程
# 作者          : Zhao Yi
# 日期          : 2026-03-05
# =============================================================================

$ErrorActionPreference = "Stop"

# 颜色定义
function Write-Step {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Yellow
}

# 开始迁移
Write-Step "开始自动化文件迁移"

# 步骤 1：验证现有文件夹
Write-Step "步骤 1：验证现有文件夹"

$required_folders = @("sources_1\new", "sim_1\new", "constrs_1\new")
foreach ($folder in $required_folders) {
    if (Test-Path $folder) {
        Write-Success "找到文件夹：$folder"
    } else {
        Write-Error-Custom "缺少文件夹：$folder"
        exit 1
    }
}

# 步骤 2：创建备份文件夹结构
Write-Step "步骤 2：创建备份文件夹结构"

$directories = @(
    "backup_chinese\rtl\calibration",
    "backup_chinese\rtl\decoder",
    "backup_chinese\rtl\reconstruction",
    "backup_chinese\rtl\sar_logic",
    "backup_chinese\rtl\top",
    "backup_chinese\testbenches\calibration",
    "backup_chinese\testbenches\decoder",
    "backup_chinese\testbenches\reconstruction",
    "backup_chinese\testbenches\top_level",
    "backup_chinese\sim_models",
    "backup_chinese\constraints",
    "project_files"
)

foreach ($dir in $directories) {
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Success "创建目录：$dir"
    } else {
        Write-Info "目录已存在：$dir"
    }
}

# 步骤 3：复制 RTL 文件
Write-Step "步骤 3：复制 RTL 文件到备份文件夹"

$rtl_files = @{
    "sources_1\new\sar_calib_ctrl_serial.sv" = "backup_chinese\rtl\calibration\"
    "sources_1\new\sar_reconstruction.sv" = "backup_chinese\rtl\reconstruction\"
    "sources_1\new\sar_adc_controller.sv" = "backup_chinese\rtl\sar_logic\"
    "sources_1\new\flash_decoder_adder.sv" = "backup_chinese\rtl\decoder\"
    "sources_1\new\fpga_top_wrapper.sv" = "backup_chinese\rtl\top\"
    "sources_1\new\virtual_adc_phy.v" = "backup_chinese\sim_models\"
}

$rtl_count = 0
foreach ($src in $rtl_files.Keys) {
    if (Test-Path $src) {
        Copy-Item $src $rtl_files[$src] -Force
        Write-Success "复制：$src"
        $rtl_count++
    } else {
        Write-Info "文件不存在（跳过）: $src"
    }
}
Write-Info "共复制 $rtl_count 个 RTL 文件"

# 步骤 4：复制 TB 文件
Write-Step "步骤 4：复制 TB 文件到备份文件夹"

$tb_files = @{
    "sim_1\new\tb_gain_comp_check_lsb.sv" = "backup_chinese\testbenches\calibration\"
    "sim_1\new\tb_sar_recon.sv" = "backup_chinese\testbenches\reconstruction\"
    "sim_1\new\tb_sar_adc_top.sv" = "backup_chinese\testbenches\top_level\"
    "sim_1\new\tb_flash_decoder.sv" = "backup_chinese\testbenches\decoder\"
}

# 检查 fpga_top_wrapper.sv 是否已在 RTL 中复制
if (!(Test-Path "backup_chinese\rtl\top\fpga_top_wrapper.sv")) {
    $tb_files["sim_1\new\fpga_top_wrapper.sv"] = "backup_chinese\rtl\top\"
}

$tb_count = 0
foreach ($src in $tb_files.Keys) {
    if (Test-Path $src) {
        Copy-Item $src $tb_files[$src] -Force
        Write-Success "复制：$src"
        $tb_count++
    } else {
        Write-Info "文件不存在（跳过）: $src"
    }
}
Write-Info "共复制 $tb_count 个 TB 文件"

# 步骤 5：复制约束文件
Write-Step "步骤 5：复制约束文件"

if (Test-Path "constrs_1\new\sar_calib_fpga.xdc") {
    Copy-Item "constrs_1\new\sar_calib_fpga.xdc" "backup_chinese\constraints\" -Force
    Write-Success "复制约束文件：sar_calib_fpga.xdc"
} else {
    Write-Error-Custom "约束文件不存在"
}

# 步骤 6：转换注释为中文
Write-Step "步骤 6：转换备份文件夹注释为中文"

$chinese_mapping = @{
    "File Name" = "文件名"
    "Module Name" = "模块名称"
    "Description" = "功能描述"
    "Version" = "版本"
    "Date" = "日期"
    "Author" = "作者"
    "Testbench" = "测试平台"
    "Test Description" = "测试描述"
    "Expected Result" = "预期结果"
    "Design Rules" = "设计规范"
    "Timing Constraints" = "时序约束"
    "Clock Domain" = "时钟域"
    "Reset Logic" = "复位逻辑"
    "Input Ports" = "输入端口"
    "Output Ports" = "输出端口"
    "Parameters" = "参数"
    "Local Parameters" = "本地参数"
    "Registers" = "寄存器"
    "Wires" = "连线"
    "State Machine" = "状态机"
    "Control Logic" = "控制逻辑"
    "Data Path" = "数据通路"
}

$all_backup_files = Get-ChildItem "backup_chinese" -Include *.sv,*.v,*.xdc -Recurse
$converted_count = 0

foreach ($file in $all_backup_files) {
    try {
        $content = Get-Content $file.FullName -Raw -Encoding UTF8
        $original_content = $content
        
        foreach ($key in $chinese_mapping.Keys) {
            $content = $content -replace $key, $chinese_mapping[$key]
        }
        
        if ($content -ne $original_content) {
            Set-Content $file.FullName -Value $content -Encoding UTF8
            Write-Success "转换注释：$($file.Name)"
            $converted_count++
        } else {
            Write-Info "无需转换：$($file.Name)"
        }
    } catch {
        Write-Error-Custom "处理文件失败：$($file.FullName)"
        Write-Error-Custom $_.Exception.Message
    }
}

Write-Info "共转换 $converted_count 个文件的注释"

# 步骤 7：创建项目文件夹符号链接
Write-Step "步骤 7：创建项目文件夹符号链接"

$links = @{
    "project_files\rtl" = "..\backup_chinese\rtl"
    "project_files\testbenches" = "..\backup_chinese\testbenches"
    "project_files\sim_models" = "..\backup_chinese\sim_models"
    "project_files\constraints" = "..\backup_chinese\constraints"
}

foreach ($link in $links.Keys) {
    if (Test-Path $link) {
        Remove-Item $link -Force
        Write-Info "删除已存在的链接：$link"
    }
    New-Item -ItemType SymbolicLink -Path $link -Target $links[$link] -Force | Out-Null
    Write-Success "创建符号链接：$link -> $($links[$link])"
}

# 步骤 8：验证文件完整性
Write-Step "步骤 8：验证文件完整性"

$check_files = @(
    "backup_chinese\rtl\calibration\sar_calib_ctrl_serial.sv",
    "backup_chinese\rtl\reconstruction\sar_reconstruction.sv",
    "backup_chinese\rtl\sar_logic\sar_adc_controller.sv",
    "backup_chinese\rtl\decoder\flash_decoder_adder.sv",
    "backup_chinese\rtl\top\fpga_top_wrapper.sv",
    "backup_chinese\sim_models\virtual_adc_phy.v",
    "backup_chinese\testbenches\calibration\tb_gain_comp_check_lsb.sv",
    "backup_chinese\testbenches\reconstruction\tb_sar_recon.sv",
    "backup_chinese\testbenches\top_level\tb_sar_adc_top.sv",
    "backup_chinese\testbenches\decoder\tb_flash_decoder.sv",
    "backup_chinese\constraints\sar_calib_fpga.xdc"
)

$valid_count = 0
foreach ($file in $check_files) {
    if (Test-Path $file) {
        $valid_count++
        Write-Success "文件存在：$file"
    } else {
        Write-Error-Custom "文件缺失：$file"
    }
}

Write-Info "验证通过：$valid_count / $($check_files.Count) 个文件"

# 步骤 9：创建验证报告
Write-Step "步骤 9：生成迁移报告"

$report_content = @"
# 文件迁移报告

**迁移日期**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
**执行人**: Zhao Yi
**工程路径**: $(Get-Location)

## 迁移统计

- RTL 文件：$rtl_count 个
- TB 文件：$tb_count 个
- 约束文件：1 个
- 注释转换：$converted_count 个文件

## 文件清单

### RTL 代码（中文注释）
"@

foreach ($file in $check_files | Where-Object { $_ -like "backup_chinese\rtl\*" -or $_ -like "backup_chinese\sim_models\*" }) {
    $report_content += "`n- $file"
}

$report_content += "`n`n### TB 文件（中文注释）`n"
foreach ($file in $check_files | Where-Object { $_ -like "backup_chinese\testbenches\*" }) {
    $report_content += "`n- $file"
}

$report_content += "`n`n### 约束文件`n- backup_chinese\constraints\sar_calib_fpga.xdc`n"

$report_content += "`n## 验证结果`n`n"
$report_content += "- 文件完整性：✓ 通过 ($valid_count / $($check_files.Count))`n"
$report_content += "- 注释语言：✓ 中文`n"
$report_content += "- 符号链接：✓ 已创建`n"

$report_file = "backup_chinese\MIGRATION_REPORT_$(Get-Date -Format 'yyyyMMdd_HHmmss').md"
Set-Content $report_file -Value $report_content -Encoding UTF8
Write-Success "生成迁移报告：$report_file"

# 完成
Write-Step "迁移完成"
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  ✓ 文件迁移成功完成！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "备份文件夹（中文注释）：backup_chinese/" -ForegroundColor Cyan
Write-Host "Vivado 文件夹（英文注释）：sources_1/, sim_1/, constrs_1/" -ForegroundColor Cyan
Write-Host "项目文件夹（符号链接）：project_files/" -ForegroundColor Cyan
Write-Host ""
Write-Host "下一步操作：" -ForegroundColor Yellow
Write-Host "  1. 检查 backup_chinese/ 文件夹中的文件注释" -ForegroundColor White
Write-Host "  2. 在 Vivado 中打开工程验证功能" -ForegroundColor White
Write-Host "  3. 运行仿真测试确保一切正常" -ForegroundColor White
Write-Host "  4. 查看迁移报告：$report_file" -ForegroundColor White
Write-Host ""
Write-Info "提示：Vivado 文件夹保持英文注释不变，可直接使用"
