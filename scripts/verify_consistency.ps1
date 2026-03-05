# =============================================================================
# 脚本名称      : verify_consistency.ps1
# 功能描述      : 验证备份系统和 Vivado 系统的代码一致性（除注释外）
# 作者          : Zhao Yi
# 日期          : 2026-03-05
# =============================================================================

$ErrorActionPreference = "Stop"

# 颜色定义
$Color_Success = "Green"
$Color_Error = "Red"
$Color_Warning = "Yellow"
$Color_Info = "Cyan"

Write-Host "========================================" -ForegroundColor $Color_Info
Write-Host "  文件一致性验证工具" -ForegroundColor $Color_Info
Write-Host "========================================" -ForegroundColor $Color_Info
Write-Host ""

# 路径定义
$BackupPath = "backup_chinese"
$VivadoPaths = @{
    "sources_1\new" = @("sar_calib_ctrl_serial.sv", "sar_reconstruction.sv", "sar_adc_controller.sv", "flash_decoder_adder.sv", "fpga_top_wrapper.sv", "virtual_adc_phy.v")
    "sim_1\new" = @("tb_gain_comp_check_lsb.sv", "tb_sar_recon.sv", "tb_sar_adc_top.sv", "tb_flash_decoder.sv", "fpga_top_wrapper.sv")
    "constrs_1\new" = @("sar_calib_fpga.xdc")
}

# 文件映射
$FileMapping = @{
    "backup_chinese\rtl\calibration\sar_calib_ctrl_serial.sv" = "sources_1\new\sar_calib_ctrl_serial.sv"
    "backup_chinese\rtl\reconstruction\sar_reconstruction.sv" = "sources_1\new\sar_reconstruction.sv"
    "backup_chinese\rtl\sar_logic\sar_adc_controller.sv" = "sources_1\new\sar_adc_controller.sv"
    "backup_chinese\rtl\decoder\flash_decoder_adder.sv" = "sources_1\new\flash_decoder_adder.sv"
    "backup_chinese\rtl\top\fpga_top_wrapper.sv" = "sources_1\new\fpga_top_wrapper.sv"
    "backup_chinese\sim_models\virtual_adc_phy.v" = "sources_1\new\virtual_adc_phy.v"
    "backup_chinese\testbenches\calibration\tb_gain_comp_check_lsb.sv" = "sim_1\new\tb_gain_comp_check_lsb.sv"
    "backup_chinese\testbenches\reconstruction\tb_sar_recon.sv" = "sim_1\new\tb_sar_recon.sv"
    "backup_chinese\testbenches\top_level\tb_sar_adc_top.sv" = "sim_1\new\tb_sar_adc_top.sv"
    "backup_chinese\testbenches\decoder\tb_flash_decoder.sv" = "sim_1\new\tb_flash_decoder.sv"
    "backup_chinese\constraints\sar_calib_fpga.xdc" = "constrs_1\new\sar_calib_fpga.xdc"
}

# 移除注释的函数
function Remove-Comments {
    param([string]$Content)
    
    # 移除单行注释
    $Content = $Content -replace '//.*$', ''
    
    # 移除多行注释
    $Content = $Content -replace '/\*[\s\S]*?\*/', ''
    
    # 移除空行
    $Content = $Content -replace '^\s*\r?\n', ''
    
    # 移除空白字符
    $Content = $Content -replace '\s+', ' '
    
    return $Content.Trim()
}

# 验证计数器
$TotalFiles = 0
$MatchedFiles = 0
$MismatchedFiles = 0
$ErrorFiles = 0

# 逐个验证文件
foreach ($backupFile in $FileMapping.Keys) {
    $vivadoFile = $FileMapping[$backupFile]
    $TotalFiles++
    
    Write-Host "[$TotalFiles/$($FileMapping.Count)] 验证：$backupFile" -ForegroundColor $Color_Info
    
    # 检查文件是否存在
    if (!(Test-Path $backupFile)) {
        Write-Host "  ✗ 备份文件不存在" -ForegroundColor $Color_Error
        $MismatchedFiles++
        continue
    }
    
    if (!(Test-Path $vivadoFile)) {
        Write-Host "  ✗ Vivado 文件不存在" -ForegroundColor $Color_Error
        $MismatchedFiles++
        continue
    }
    
    try {
        # 读取文件内容
        $backupContent = Get-Content $backupFile -Raw -Encoding UTF8
        $vivadoContent = Get-Content $vivadoFile -Raw -Encoding UTF8
        
        # 移除注释后比较
        $backupCode = Remove-Comments -Content $backupContent
        $vivadoCode = Remove-Comments -Content $vivadoContent
        
        if ($backupCode -eq $vivadoCode) {
            Write-Host "  ✓ 代码一致（注释已忽略）" -ForegroundColor $Color_Success
            $MatchedFiles++
        } else {
            Write-Host "  ✗ 代码不一致！" -ForegroundColor $Color_Error
            
            # 显示差异统计
            $backupLines = ($backupCode -split "`n").Count
            $vivadoLines = ($vivadoCode -split "`n").Count
            Write-Host "    备份代码行数：$backupLines" -ForegroundColor $Color_Warning
            Write-Host "    Vivado 代码行数：$vivadoLines" -ForegroundColor $Color_Warning
            
            # 显示前几处差异
            $backupTokens = $backupCode -split '\s+'
            $vivadoTokens = $vivadoCode -split '\s+'
            
            $diff_count = 0
            for ($i = 0; $i -lt [Math]::Min($backupTokens.Count, $vivadoTokens.Count) -and $diff_count -lt 3; $i++) {
                if ($backupTokens[$i] -ne $vivadoTokens[$i]) {
                    Write-Host "    差异 [$i]: 备份='$($backupTokens[$i])' vs Vivado='$($vivadoTokens[$i])'" -ForegroundColor $Color_Warning
                    $diff_count++
                }
            }
            
            $MismatchedFiles++
        }
    } catch {
        Write-Host "  ✗ 读取文件失败：$($_.Exception.Message)" -ForegroundColor $Color_Error
        $ErrorFiles++
    }
    
    Write-Host ""
}

# 总结
Write-Host "========================================" -ForegroundColor $Color_Info
Write-Host "  验证结果总结" -ForegroundColor $Color_Info
Write-Host "========================================" -ForegroundColor $Color_Info
Write-Host ""
Write-Host "  总文件数：$TotalFiles" -ForegroundColor White
Write-Host "  一致文件：$MatchedFiles" -ForegroundColor $(if ($MatchedFiles -eq $TotalFiles) {$Color_Success} else {$Color_Warning})
Write-Host "  不一致文件：$MismatchedFiles" -ForegroundColor $(if ($MismatchedFiles -eq 0) {$Color_Success} else {$Color_Error})
Write-Host "  读取错误：$ErrorFiles" -ForegroundColor $(if ($ErrorFiles -eq 0) {$Color_Success} else {$Color_Error})
Write-Host ""

$consistency_rate = [math]::Round(($MatchedFiles / $TotalFiles) * 100, 2)
Write-Host "  一致性比率：$consistency_rate%" -ForegroundColor $(if ($consistency_rate -eq 100) {$Color_Success} else {$Color_Warning})
Write-Host ""

if ($MismatchedFiles -eq 0 -and $ErrorFiles -eq 0) {
    Write-Host "✓ 所有文件代码完全一致！" -ForegroundColor $Color_Success
    Write-Host ""
    Write-Host "备份系统（中文注释）和 Vivado 系统（英文注释）已正确同步。" -ForegroundColor $Color_Success
    exit 0
} else {
    Write-Host "✗ 发现不一致的文件，请检查！" -ForegroundColor $Color_Error
    Write-Host ""
    Write-Host "建议操作：" -ForegroundColor $Color_Warning
    Write-Host "  1. 检查不一致的文件内容" -ForegroundColor White
    Write-Host "  2. 使用同步脚本进行同步：" -ForegroundColor White
    Write-Host "     .\sync_backup_vivado.ps1 -BackupToVivado" -ForegroundColor Gray
    Write-Host "     .\sync_backup_vivado.ps1 -VivadoToBackup" -ForegroundColor Gray
    Write-Host "  3. 重新运行验证脚本" -ForegroundColor White
    Write-Host ""
    exit 1
}
