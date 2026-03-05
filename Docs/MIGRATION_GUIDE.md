# 工程文件迁移实施指南

**文档版本**：v1.0  
**创建日期**：2026-03-05  
**作者**：Zhao Yi  
**工程路径**：`d:\ReedZhao\Document\ADC_Digital_PROCESS\proc_vivado\sar_adc_v3\Digital_process\Digital_process.srcs`

---

## 📋 迁移目标

### 核心要求

1. **创建备份系统**：
   - 备份文件夹：`backup_chinese/`
   - 所有注释使用**中文**
   - 用于项目备份和迁移

2. **保持 Vivado 系统**：
   - Vivado 文件夹：`sources_1/`, `sim_1/`, `constrs_1/`
   - 所有注释使用**英文**
   - 用于 Vivado 工程

3. **两套系统完全一致**：
   - 除注释语言外，代码、结构、功能完全相同
   - 通过脚本自动同步

4. **统一迁移目标**：
   - 所有文件迁移到：`project_files/`
   - 便于整体迁移和管理

---

## 🌳 迁移后文件结构

```
Digital_process.srcs/
│
├── 📁 backup_chinese/                    # ⭐ 备份文件夹（中文注释）
│   ├── rtl/                              # RTL 代码（中文注释）
│   │   ├── calibration/
│   │   ├── decoder/
│   │   ├── reconstruction/
│   │   ├── sar_logic/
│   │   └── top/
│   ├── testbenches/                      # TB 文件（中文注释）
│   │   ├── calibration/
│   │   ├── decoder/
│   │   ├── reconstruction/
│   │   └── top_level/
│   ├── sim_models/                       # 仿真模型（中文注释）
│   └── constraints/                      # 约束文件（中文注释）
│
├── 📁 project_files/                     # ⭐ 统一项目文件夹
│   ├── rtl/                              # 指向 backup_chinese/rtl/
│   ├── testbenches/                      # 指向 backup_chinese/testbenches/
│   ├── sim_models/                       # 指向 backup_chinese/sim_models/
│   └── constraints/                      # 指向 backup_chinese/constraints/
│
├── 📁 sources_1/                         # Vivado RTL 源文件（英文注释）
│   └── new/
│       ├── sar_calib_ctrl_serial.sv
│       ├── sar_reconstruction.sv
│       ├── sar_adc_controller.sv
│       ├── flash_decoder_adder.sv
│       └── virtual_adc_phy.v
│
├── 📁 sim_1/                             # Vivado 仿真源文件（英文注释）
│   └── new/
│       ├── tb_gain_comp_check_lsb.sv
│       ├── tb_sar_recon.sv
│       ├── tb_sar_adc_top.sv
│       ├── tb_flash_decoder.sv
│       └── fpga_top_wrapper.sv
│
├── 📁 constrs_1/                         # Vivado 约束文件（英文注释）
│   └── new/
│       └── sar_calib_fpga.xdc
│
├── 📁 docs/                              # 项目文档
├── 📁 Reports/                           # 项目报告
├── 📁 REFERENCE/                         # 参考文献
├── 📁 test_reports/                      # 测试报告
├── 📁 scripts/                           # 脚本工具
└── README.md                             # 项目说明
```

---

## 🔧 实施步骤

### 阶段 1：准备工作

#### 1.1 创建备份文件夹

```powershell
# 创建备份文件夹结构
New-Item -ItemType Directory -Path "backup_chinese\rtl\calibration" -Force
New-Item -ItemType Directory -Path "backup_chinese\rtl\decoder" -Force
New-Item -ItemType Directory -Path "backup_chinese\rtl\reconstruction" -Force
New-Item -ItemType Directory -Path "backup_chinese\rtl\sar_logic" -Force
New-Item -ItemType Directory -Path "backup_chinese\rtl\top" -Force

New-Item -ItemType Directory -Path "backup_chinese\testbenches\calibration" -Force
New-Item -ItemType Directory -Path "backup_chinese\testbenches\decoder" -Force
New-Item -ItemType Directory -Path "backup_chinese\testbenches\reconstruction" -Force
New-Item -ItemType Directory -Path "backup_chinese\testbenches\top_level" -Force

New-Item -ItemType Directory -Path "backup_chinese\sim_models" -Force
New-Item -ItemType Directory -Path "backup_chinese\constraints" -Force
```

#### 1.2 创建项目文件夹

```powershell
# 创建统一项目文件夹
New-Item -ItemType Directory -Path "project_files" -Force
```

---

### 阶段 2：文件迁移与注释转换

#### 2.1 迁移 RTL 代码（带中文注释）

**从 sources_1/new/ 迁移到 backup_chinese/rtl/**：

```powershell
# 复制 RTL 文件到备份文件夹
Copy-Item "sources_1\new\sar_calib_ctrl_serial.sv" "backup_chinese\rtl\calibration\"
Copy-Item "sources_1\new\sar_reconstruction.sv" "backup_chinese\rtl\reconstruction\"
Copy-Item "sources_1\new\sar_adc_controller.sv" "backup_chinese\rtl\sar_logic\"
Copy-Item "sources_1\new\flash_decoder_adder.sv" "backup_chinese\rtl\decoder\"
Copy-Item "sources_1\new\fpga_top_wrapper.sv" "backup_chinese\rtl\top\"
Copy-Item "sources_1\new\virtual_adc_phy.v" "backup_chinese\sim_models\"
```

**转换注释为中文**：

```powershell
# 读取文件内容
$content = Get-Content "backup_chinese\rtl\calibration\sar_calib_ctrl_serial.sv" -Raw

# 替换英文注释为中文
$content = $content -replace '// File Name', '// 文件名'
$content = $content -replace '// Module Name', '// 模块名称'
$content = $content -replace '// Description', '// 功能描述'
$content = $content -replace '// Version', '// 版本'
$content = $content -replace '// Date', '// 日期'
$content = $content -replace '// Author', '// 作者'

# 保存文件
Set-Content "backup_chinese\rtl\calibration\sar_calib_ctrl_serial.sv" -Value $content -Encoding UTF8
```

#### 2.2 迁移 TB 文件（带中文注释）

**从 sim_1/new/ 迁移到 backup_chinese/testbenches/**：

```powershell
# 复制 TB 文件到备份文件夹
Copy-Item "sim_1\new\tb_gain_comp_check_lsb.sv" "backup_chinese\testbenches\calibration\"
Copy-Item "sim_1\new\tb_sar_recon.sv" "backup_chinese\testbenches\reconstruction\"
Copy-Item "sim_1\new\tb_sar_adc_top.sv" "backup_chinese\testbenches\top_level\"
Copy-Item "sim_1\new\tb_flash_decoder.sv" "backup_chinese\testbenches\decoder\"
Copy-Item "sim_1\new\fpga_top_wrapper.sv" "backup_chinese\rtl\top\"
```

**转换注释为中文**：

```powershell
# 批量转换 TB 文件注释
$tb_files = Get-ChildItem "backup_chinese\testbenches" -Filter "*.sv" -Recurse
foreach ($file in $tb_files) {
    $content = Get-Content $file.FullName -Raw
    $content = $content -replace '// Testbench', '// 测试平台'
    $content = $content -replace '// Test Description', '// 测试描述'
    $content = $content -replace '// Expected Result', '// 预期结果'
    Set-Content $file.FullName -Value $content -Encoding UTF8
}
```

#### 2.3 迁移约束文件

```powershell
# 复制约束文件
Copy-Item "constrs_1\new\sar_calib_fpga.xdc" "backup_chinese\constraints\"
```

---

### 阶段 3：创建同步机制

#### 3.1 创建同步脚本

**文件**：`scripts/sync_backup_vivado.ps1`

```powershell
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
$BackupPath = Join-Path $PSScriptRoot "..\backup_chinese"
$VivadoSourcesPath = Join-Path $PSScriptRoot "..\sources_1\new"
$VivadoSimPath = Join-Path $PSScriptRoot "..\sim_1\new"
$VivadoConstrsPath = Join-Path $PSScriptRoot "..\constrs_1\new"

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

# 主同步逻辑
if ($BackupToVivado) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  从备份同步到 Vivado（中文 -> 英文）" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    foreach ($backupSubPath in $FileMapping.Keys) {
        $backupFile = Join-Path $BackupPath $backupSubPath
        $vivadoFile = Join-Path $PSScriptRoot "..\" $FileMapping[$backupSubPath]
        
        if (Test-Path $backupFile) {
            Write-Host "处理：$backupSubPath" -ForegroundColor Yellow
            
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
        } else {
            Write-Host "  ✗ 文件不存在：$backupFile" -ForegroundColor Red
        }
    }
    
    Write-Host "`n同步完成！" -ForegroundColor Green
}
elseif ($VivadoToBackup) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  从 Vivado 同步到备份（英文 -> 中文）" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    foreach ($backupSubPath in $FileMapping.Keys) {
        $vivadoFile = Join-Path $PSScriptRoot "..\" $FileMapping[$backupSubPath]
        $backupFile = Join-Path $BackupPath $backupSubPath
        
        if (Test-Path $vivadoFile) {
            Write-Host "处理：$backupSubPath" -ForegroundColor Yellow
            
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
        } else {
            Write-Host "  ✗ 文件不存在：$vivadoFile" -ForegroundColor Red
        }
    }
    
    Write-Host "`n同步完成！" -ForegroundColor Green
}
else {
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
}
```

---

### 阶段 4：创建验证脚本

#### 4.1 一致性验证脚本

**文件**：`scripts/verify_consistency.ps1`

```powershell
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
    
    return $Content
}

# 验证计数器
$TotalFiles = 0
$MatchedFiles = 0
$MismatchedFiles = 0

# 逐个验证文件
foreach ($backupFile in $FileMapping.Keys) {
    $vivadoFile = $FileMapping[$backupFile]
    $TotalFiles++
    
    Write-Host "[$TotalFiles] 验证：$backupFile" -ForegroundColor $Color_Info
    
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
        
        $MismatchedFiles++
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
Write-Host ""

if ($MismatchedFiles -eq 0) {
    Write-Host "✓ 所有文件代码完全一致！" -ForegroundColor $Color_Success
    exit 0
} else {
    Write-Host "✗ 发现不一致的文件，请检查！" -ForegroundColor $Color_Error
    exit 1
}
```

---

### 阶段 5：创建自动化迁移脚本

#### 5.1 完整迁移脚本

**文件**：`scripts/automated_migration.ps1`

```powershell
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

# 开始迁移
Write-Step "开始自动化文件迁移"

# 步骤 1：创建文件夹结构
Write-Step "步骤 1：创建文件夹结构"

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
        Write-Success "目录已存在：$dir"
    }
}

# 步骤 2：复制 RTL 文件
Write-Step "步骤 2：复制 RTL 文件到备份文件夹"

$rtl_files = @{
    "sources_1\new\sar_calib_ctrl_serial.sv" = "backup_chinese\rtl\calibration\"
    "sources_1\new\sar_reconstruction.sv" = "backup_chinese\rtl\reconstruction\"
    "sources_1\new\sar_adc_controller.sv" = "backup_chinese\rtl\sar_logic\"
    "sources_1\new\flash_decoder_adder.sv" = "backup_chinese\rtl\decoder\"
    "sources_1\new\fpga_top_wrapper.sv" = "backup_chinese\rtl\top\"
    "sources_1\new\virtual_adc_phy.v" = "backup_chinese\sim_models\"
}

foreach ($src in $rtl_files.Keys) {
    Copy-Item $src $rtl_files[$src] -Force
    Write-Success "复制：$src"
}

# 步骤 3：复制 TB 文件
Write-Step "步骤 3：复制 TB 文件到备份文件夹"

$tb_files = @{
    "sim_1\new\tb_gain_comp_check_lsb.sv" = "backup_chinese\testbenches\calibration\"
    "sim_1\new\tb_sar_recon.sv" = "backup_chinese\testbenches\reconstruction\"
    "sim_1\new\tb_sar_adc_top.sv" = "backup_chinese\testbenches\top_level\"
    "sim_1\new\tb_flash_decoder.sv" = "backup_chinese\testbenches\decoder\"
}

foreach ($src in $tb_files.Keys) {
    Copy-Item $src $tb_files[$src] -Force
    Write-Success "复制：$src"
}

# 步骤 4：复制约束文件
Write-Step "步骤 4：复制约束文件"

Copy-Item "constrs_1\new\sar_calib_fpga.xdc" "backup_chinese\constraints\" -Force
Write-Success "复制约束文件"

# 步骤 5：转换注释为中文
Write-Step "步骤 5：转换备份文件夹注释为中文"

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
}

$all_backup_files = Get-ChildItem "backup_chinese" -Include *.sv,*.v,*.xdc -Recurse
foreach ($file in $all_backup_files) {
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    foreach ($key in $chinese_mapping.Keys) {
        $content = $content -replace $key, $chinese_mapping[$key]
    }
    Set-Content $file.FullName -Value $content -Encoding UTF8
    Write-Success "转换注释：$($file.Name)"
}

# 步骤 6：创建项目文件夹符号链接
Write-Step "步骤 6：创建项目文件夹符号链接"

$links = @{
    "project_files\rtl" = "..\backup_chinese\rtl"
    "project_files\testbenches" = "..\backup_chinese\testbenches"
    "project_files\sim_models" = "..\backup_chinese\sim_models"
    "project_files\constraints" = "..\backup_chinese\constraints"
}

foreach ($link in $links.Keys) {
    if (Test-Path $link) {
        Remove-Item $link -Force
    }
    New-Item -ItemType SymbolicLink -Path $link -Target $links[$link] -Force | Out-Null
    Write-Success "创建符号链接：$link -> $($links[$link])"
}

# 步骤 7：验证
Write-Step "步骤 7：运行一致性验证"

if (Test-Path "scripts\verify_consistency.ps1") {
    & "scripts\verify_consistency.ps1"
} else {
    Write-Error-Custom "验证脚本不存在"
}

# 完成
Write-Step "迁移完成"
Write-Host ""
Write-Host "备份文件夹（中文注释）：backup_chinese/" -ForegroundColor Green
Write-Host "Vivado 文件夹（英文注释）：sources_1/, sim_1/, constrs_1/" -ForegroundColor Green
Write-Host "项目文件夹（符号链接）：project_files/" -ForegroundColor Green
Write-Host ""
Write-Host "下一步操作：" -ForegroundColor Yellow
Write-Host "  1. 在 Vivado 中打开工程验证" -ForegroundColor White
Write-Host "  2. 运行仿真测试" -ForegroundColor White
Write-Host "  3. 检查所有文件注释" -ForegroundColor White
Write-Host ""
```

---

## 📊 迁移前后对比

| 项目 | 迁移前 | 迁移后 |
|------|--------|--------|
| **文件组织** | 分散在 5 个位置 | 统一到 project_files/ |
| **备份系统** | 无 | backup_chinese/（中文注释） |
| **Vivado 系统** | 分散 | sources_1/, sim_1/, constrs_1/（英文注释） |
| **注释语言** | 混乱 | 备份中文，Vivado 英文 |
| **同步机制** | 手动 | 自动化脚本 |
| **验证机制** | 无 | 自动一致性检查 |

---

## ✅ 验证清单

迁移完成后，请检查以下项目：

- [ ] backup_chinese/ 文件夹创建完成
- [ ] 所有 RTL 文件已迁移到 backup_chinese/rtl/
- [ ] 所有 TB 文件已迁移到 backup_chinese/testbenches/
- [ ] 所有约束文件已迁移到 backup_chinese/constraints/
- [ ] 备份文件夹所有注释为中文
- [ ] Vivado 文件夹所有注释为英文
- [ ] project_files/ 符号链接创建完成
- [ ] 运行 verify_consistency.ps1 验证通过
- [ ] Vivado 工程打开正常
- [ ] 所有仿真运行正常

---

## 🚀 执行迁移

### 方法 1：自动迁移（推荐）

```powershell
# 运行自动化迁移脚本
cd scripts
.\automated_migration.ps1
```

### 方法 2：手动分步执行

按照本文档的阶段 1-5 逐步执行

---

## 📞 联系信息

**负责人**：Zhao Yi  
**邮箱**：717880671@qq.com  
**更新日期**：2026-03-05

---

**请确认是否开始执行迁移操作？**

- [ ] 确认执行方案 A（保守方案）
- [ ] 已阅读并理解迁移步骤
- [ ] 已备份当前项目
- [ ] 预留足够时间（2-3 小时）

**确认后我将立即开始执行迁移！** 🚀
