# =============================================================================
# 脚本名称      : sync_backup_vivado.ps1
# 功能描述      : 同步备份文件夹（中文注释）和 Vivado 文件夹（英文注释）
# 作者          : Zhao Yi
# 日期          : 2026-03-05
# =============================================================================

param(
    [Parameter(Mandatory=$false)]
    [switch]$BackupToVivado,  # 从备份同步到 Vivado
    [Parameter(Mandatory=$false)]
    [switch]$VivadoToBackup   # 从 Vivado 同步到备份
)

$ErrorActionPreference = "Stop"

# 路径定义
$ScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
$BackupPath = Join-Path $ScriptRoot "..\backup_chinese"
$VivadoSourcesPath = Join-Path $ScriptRoot "..\sources_1\new"
$VivadoSimPath = Join-Path $ScriptRoot "..\sim_1\new"
$VivadoConstrsPath = Join-Path $ScriptRoot "..\constrs_1\new"

# 文件映射表
$FileMapping = @{
    "rtl\calibration\sar_calib_ctrl_serial.sv" = "sar_calib_ctrl_serial.sv"
    "rtl\reconstruction\sar_reconstruction.sv" = "sar_reconstruction.sv"
    "rtl\sar_logic\sar_adc_controller.sv" = "sar_adc_controller.sv"
    "rtl\decoder\flash_decoder_adder.sv" = "flash_decoder_adder.sv"
    "rtl\top\fpga_top_wrapper.sv" = "fpga_top_wrapper.sv"
    "sim_models\virtual_adc_phy.v" = "virtual_adc_phy.v"
    "testbenches\calibration\tb_gain_comp_check_lsb.sv" = "tb_gain_comp_check_lsb.sv"
    "testbenches\reconstruction\tb_sar_recon.sv" = "tb_sar_recon.sv"
    "testbenches\top_level\tb_sar_adc_top.sv" = "tb_sar_adc_top.sv"
    "testbenches\decoder\tb_flash_decoder.sv" = "tb_flash_decoder.sv"
    "constraints\sar_calib_fpga.xdc" = "sar_calib_fpga.xdc"
}

# 注释映射表（中文 -> 英文）
$ChineseToEnglish = @{
    "文件名" = "File Name"
    "模块名称" = "Module Name"
    "功能描述" = "Description"
    "版本" = "Version"
    "日期" = "Date"
    "作者" = "Author"
    "测试平台" = "Testbench"
    "测试描述" = "Test Description"
    "预期结果" = "Expected Result"
    "设计规范" = "Design Rules"
    "时序约束" = "Timing Constraints"
    "时钟域" = "Clock Domain"
    "复位逻辑" = "Reset Logic"
    "输入端口" = "Input Ports"
    "输出端口" = "Output Ports"
    "参数" = "Parameters"
    "本地参数" = "Local Parameters"
    "寄存器" = "Registers"
    "连线" = "Wires"
    "状态机" = "State Machine"
    "控制逻辑" = "Control Logic"
    "数据通路" = "Data Path"
}

# 英文 -> 中文
$EnglishToChinese = @{}
foreach ($key in $ChineseToEnglish.Keys) {
    $EnglishToChinese[$ChineseToEnglish[$key]] = $key
}

# 转换注释函数
function Convert-Comments {
    param(
        [string]$Content,
        [hashtable]$Mapping,
        [switch]$ToEnglish
    )
    
    foreach ($key in $Mapping.Keys) {
        if ($ToEnglish) {
            $Content = $Content -replace [regex]::Escape($key), $Mapping[$key]
        } else {
            $Content = $Content -replace [regex]::Escape($Mapping[$key]), $key
        }
    }
    return $Content
}

# 显示帮助信息
function Show-Help {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  备份与 Vivado 同步工具" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "用法：" -ForegroundColor Yellow
    Write-Host "  .\sync_backup_vivado.ps1 -BackupToVivado   # 备份 -> Vivado" -ForegroundColor White
    Write-Host "  .\sync_backup_vivado.ps1 -VivadoToBackup   # Vivado -> 备份" -ForegroundColor White
    Write-Host ""
    Write-Host "说明：" -ForegroundColor Yellow
    Write-Host "  -BackupToVivado:  将备份文件夹的更改同步到 Vivado（中文注释转英文）" -ForegroundColor Gray
    Write-Host "  -VivadoToBackup:  将 Vivado 的更改同步到备份文件夹（英文注释转中文）" -ForegroundColor Gray
    Write-Host ""
    Write-Host "示例：" -ForegroundColor Yellow
    Write-Host "  .\sync_backup_vivado.ps1 -BackupToVivado" -ForegroundColor White
    Write-Host "  .\sync_backup_vivado.ps1 -VivadoToBackup" -ForegroundColor White
    Write-Host ""
}

# 主同步逻辑
if ($BackupToVivado) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  从备份同步到 Vivado（中文 -> 英文）" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $sync_count = 0
    $error_count = 0
    
    foreach ($backupSubPath in $FileMapping.Keys) {
        $backupFile = Join-Path $BackupPath $backupSubPath
        $vivadoFile = Join-Path $ScriptRoot "..\" $FileMapping[$backupSubPath]
        
        if (Test-Path $backupFile) {
            Write-Host "处理：$backupSubPath" -ForegroundColor Yellow
            
            try {
                # 读取备份文件
                $content = Get-Content $backupFile -Raw -Encoding UTF8
                
                # 转换注释为英文
                $content = Convert-Comments -Content $content -Mapping $ChineseToEnglish -ToEnglish
                
                # 确定目标路径
                $targetPath = if ($backupSubPath -like "testbenches\*") {
                    $VivadoSimPath
                } elseif ($backupSubPath -like "rtl\*" -or $backupSubPath -like "sim_models\*") {
                    $VivadoSourcesPath
                } else {
                    $VivadoConstrsPath
                }
                
                $targetFile = Join-Path $targetPath (Split-Path $backupFile -Leaf)
                
                # 保存到 Vivado 路径
                Set-Content $targetFile -Value $content -Encoding UTF8
                Write-Host "  ✓ 已同步到：$targetFile" -ForegroundColor Green
                $sync_count++
            } catch {
                Write-Host "  ✗ 同步失败：$($_.Exception.Message)" -ForegroundColor Red
                $error_count++
            }
        } else {
            Write-Host "  ℹ 文件不存在：$backupFile" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  同步完成" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  成功：$sync_count 个文件" -ForegroundColor Green
    Write-Host "  失败：$error_count 个文件" -ForegroundColor $(if ($error_count -eq 0) {"Green"} else {"Red"})
    Write-Host ""
}
elseif ($VivadoToBackup) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  从 Vivado 同步到备份（英文 -> 中文）" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $sync_count = 0
    $error_count = 0
    
    foreach ($backupSubPath in $FileMapping.Keys) {
        $vivadoFile = Join-Path $ScriptRoot "..\" $FileMapping[$backupSubPath]
        $backupFile = Join-Path $BackupPath $backupSubPath
        
        if (Test-Path $vivadoFile) {
            Write-Host "处理：$backupSubPath" -ForegroundColor Yellow
            
            try {
                # 读取 Vivado 文件
                $content = Get-Content $vivadoFile -Raw -Encoding UTF8
                
                # 转换注释为中文
                $content = Convert-Comments -Content $content -Mapping $EnglishToChinese -ToEnglish
                
                # 创建目标目录
                $targetDir = Split-Path $backupFile -Parent
                if (!(Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
                
                # 保存到备份路径
                Set-Content $backupFile -Value $content -Encoding UTF8
                Write-Host "  ✓ 已同步到：$backupFile" -ForegroundColor Green
                $sync_count++
            } catch {
                Write-Host "  ✗ 同步失败：$($_.Exception.Message)" -ForegroundColor Red
                $error_count++
            }
        } else {
            Write-Host "  ℹ 文件不存在：$vivadoFile" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  同步完成" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  成功：$sync_count 个文件" -ForegroundColor Green
    Write-Host "  失败：$error_count 个文件" -ForegroundColor $(if ($error_count -eq 0) {"Green"} else {"Red"})
    Write-Host ""
}
else {
    Show-Help
}
