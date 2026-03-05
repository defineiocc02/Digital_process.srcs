# =============================================================================
# Script Name   : sync_backup_vivado.ps1
# Description   : Synchronize backup folder (Chinese comments) and Vivado folder (English comments)
# Author        : Zhao Yi
# Date          : 2026-03-05
# =============================================================================

param(
    [Parameter(Mandatory=$false)]
    [switch]$BackupToVivado,
    [Parameter(Mandatory=$false)]
    [switch]$VivadoToBackup
)

$ErrorActionPreference = "Stop"

# Paths
$ScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
$BackupPath = Join-Path $ScriptRoot "..\backup_chinese"
$VivadoSourcesPath = Join-Path $ScriptRoot "..\sources_1\new"
$VivadoSimPath = Join-Path $ScriptRoot "..\sim_1\new"
$VivadoConstrsPath = Join-Path $ScriptRoot "..\constrs_1\new"

# File mapping
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

# Comment mapping (Chinese to English)
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
    "电容位数" = "Capacitor Bits"
    "权重位宽" = "Weight Bit Width"
    "比较器" = "Comparator"
    "校准" = "Calibration"
    "重构" = "Reconstruction"
    "测试" = "Test"
    "仿真" = "Simulation"
    "综合" = "Synthesis"
    "实现" = "Implementation"
    "约束" = "Constraints"
    "端口" = "Ports"
    "信号" = "Signals"
    "逻辑" = "Logic"
    "算法" = "Algorithm"
    "系统" = "System"
    "数字" = "Digital"
    "模拟" = "Analog"
    "转换器" = "Converter"
    "控制器" = "Controller"
    "引擎" = "Engine"
    "译码器" = "Decoder"
    "加法器" = "Adder"
    "乘法器" = "Multiplier"
    "累加器" = "Accumulator"
    "寄存器" = "Register"
    "存储器" = "Memory"
    "缓存" = "Buffer"
    "接口" = "Interface"
    "总线" = "Bus"
    "时钟" = "Clock"
    "复位" = "Reset"
    "使能" = "Enable"
    "选择" = "Select"
    "输出" = "Output"
    "输入" = "Input"
    "数据" = "Data"
    "地址" = "Address"
    "控制" = "Control"
    "状态" = "Status"
    "标志" = "Flag"
    "中断" = "Interrupt"
    "同步" = "Synchronous"
    "异步" = "Asynchronous"
    "边沿" = "Edge"
    "电平" = "Level"
    "上升沿" = "Rising Edge"
    "下降沿" = "Falling Edge"
    "高电平" = "High Level"
    "低电平" = "Low Level"
    "有效" = "Valid"
    "无效" = "Invalid"
    "成功" = "Success"
    "失败" = "Failure"
    "错误" = "Error"
    "警告" = "Warning"
    "信息" = "Info"
    "调试" = "Debug"
    "验证" = "Verification"
    "检查" = "Check"
    "确认" = "Confirm"
    "完成" = "Done"
    "开始" = "Start"
    "停止" = "Stop"
    "运行" = "Run"
    "等待" = "Wait"
    "延迟" = "Delay"
    "周期" = "Cycle"
    "频率" = "Frequency"
    "时间" = "Time"
    "速度" = "Speed"
    "性能" = "Performance"
    "功耗" = "Power"
    "面积" = "Area"
    "资源" = "Resource"
    "利用率" = "Utilization"
    "优化" = "Optimization"
    "平衡" = "Balance"
    "匹配" = "Match"
    "比较" = "Compare"
    "判断" = "Judge"
    "决定" = "Decision"
    "分支" = "Branch"
    "循环" = "Loop"
    "条件" = "Condition"
    "默认" = "Default"
    "初始" = "Initial"
    "最终" = "Final"
    "中间" = "Intermediate"
    "临时" = "Temporary"
    "永久" = "Permanent"
    "静态" = "Static"
    "动态" = "Dynamic"
    "固定" = "Fixed"
    "可变" = "Variable"
    "常量" = "Constant"
    "变量" = "Variable"
    "索引" = "Index"
    "偏移" = "Offset"
    "基址" = "Base Address"
    "长度" = "Length"
    "宽度" = "Width"
    "高度" = "Height"
    "深度" = "Depth"
    "大小" = "Size"
    "数量" = "Count"
    "最大值" = "Maximum"
    "最小值" = "Minimum"
    "平均值" = "Average"
    "峰值" = "Peak"
    "谷值" = "Valley"
    "阈值" = "Threshold"
    "门限" = "Threshold"
    "范围" = "Range"
    "精度" = "Precision"
    "分辨率" = "Resolution"
    "误差" = "Error"
    "偏差" = "Deviation"
    "补偿" = "Compensation"
    "校正" = "Correction"
    "调整" = "Adjustment"
    "增益" = "Gain"
    "衰减" = "Attenuation"
    "放大" = "Amplification"
    "缩小" = "Reduction"
    "扩展" = "Extension"
    "压缩" = "Compression"
    "编码" = "Encoding"
    "解码" = "Decoding"
    "调制" = "Modulation"
    "解调" = "Demodulation"
    "滤波" = "Filtering"
    "采样" = "Sampling"
    "量化" = "Quantization"
    "保持" = "Hold"
    "跟踪" = "Track"
    "捕获" = "Capture"
    "触发" = "Trigger"
    "锁存" = "Latch"
    "锁相环" = "PLL"
    "延迟锁相环" = "DLL"
    "查找表" = "LUT"
    "触发器" = "Flip-Flop"
    "锁存器" = "Latch"
    "多路选择器" = "Multiplexer"
    "多路分配器" = "Demultiplexer"
    "编码器" = "Encoder"
    "译码器" = "Decoder"
    "计数器" = "Counter"
    "定时器" = "Timer"
    "分频器" = "Divider"
    "倍频器" = "Multiplier"
    "移位寄存器" = "Shift Register"
    "串行" = "Serial"
    "并行" = "Parallel"
    "同步" = "Synchronization"
    "异步" = "Asynchronization"
    "握手" = "Handshake"
    "就绪" = "Ready"
    "有效" = "Valid"
    "确认" = "Acknowledge"
    "请求" = "Request"
    "响应" = "Response"
    "主" = "Master"
    "从" = "Slave"
    "发送" = "Transmit"
    "接收" = "Receive"
    "读" = "Read"
    "写" = "Write"
    "加载" = "Load"
    "存储" = "Store"
    "更新" = "Update"
    "刷新" = "Refresh"
    "清除" = "Clear"
    "设置" = "Set"
    "复位" = "Reset"
    "初始化" = "Initialize"
    "配置" = "Configure"
    "编程" = "Program"
    "擦除" = "Erase"
    "备份" = "Backup"
    "恢复" = "Restore"
    "保存" = "Save"
    "加载" = "Load"
    "导入" = "Import"
    "导出" = "Export"
    "生成" = "Generate"
    "创建" = "Create"
    "删除" = "Delete"
    "修改" = "Modify"
    "添加" = "Add"
    "移除" = "Remove"
    "合并" = "Merge"
    "分割" = "Split"
    "连接" = "Connect"
    "断开" = "Disconnect"
    "打开" = "Open"
    "关闭" = "Close"
    "启动" = "Launch"
    "终止" = "Terminate"
    "暂停" = "Pause"
    "继续" = "Resume"
    "跳过" = "Skip"
    "重复" = "Repeat"
    "重试" = "Retry"
    "取消" = "Cancel"
    "确认" = "Confirm"
    "拒绝" = "Reject"
    "接受" = "Accept"
    "通过" = "Pass"
    "失败" = "Fail"
    "成功" = "Success"
    "完成" = "Complete"
    "进行中" = "In Progress"
    "等待中" = "Waiting"
    "超时" = "Timeout"
    "过期" = "Expire"
    "无效" = "Invalid"
    "有效" = "Valid"
    "合法" = "Legal"
    "非法" = "Illegal"
    "安全" = "Safe"
    "危险" = "Danger"
    "保护" = "Protect"
    "锁定" = "Lock"
    "解锁" = "Unlock"
    "加密" = "Encrypt"
    "解密" = "Decrypt"
    "认证" = "Authenticate"
    "授权" = "Authorize"
    "权限" = "Permission"
    "访问" = "Access"
    "禁止" = "Forbidden"
    "允许" = "Allow"
    "拒绝" = "Deny"
    "忽略" = "Ignore"
    "处理" = "Process"
    "执行" = "Execute"
    "运行" = "Run"
    "调用" = "Call"
    "返回" = "Return"
    "跳转" = "Jump"
    "分支" = "Branch"
    "循环" = "Loop"
    "迭代" = "Iterate"
    "递归" = "Recursive"
    "调用栈" = "Call Stack"
    "堆栈" = "Stack"
    "队列" = "Queue"
    "列表" = "List"
    "数组" = "Array"
    "结构" = "Structure"
    "联合" = "Union"
    "枚举" = "Enumeration"
    "类型" = "Type"
    "定义" = "Definition"
    "声明" = "Declaration"
    "实现" = "Implementation"
    "接口" = "Interface"
    "类" = "Class"
    "对象" = "Object"
    "方法" = "Method"
    "函数" = "Function"
    "过程" = "Procedure"
    "任务" = "Task"
    "线程" = "Thread"
    "进程" = "Process"
    "协程" = "Coroutine"
    "纤程" = "Fiber"
    "调度" = "Schedule"
    "优先级" = "Priority"
    "抢占" = "Preempt"
    "阻塞" = "Block"
    "非阻塞" = "Non-blocking"
    "同步" = "Synchronize"
    "互斥" = "Mutex"
    "信号量" = "Semaphore"
    "事件" = "Event"
    "消息" = "Message"
    "邮箱" = "Mailbox"
    "管道" = "Pipe"
    "套接字" = "Socket"
    "网络" = "Network"
    "协议" = "Protocol"
    "包" = "Packet"
    "帧" = "Frame"
    "位" = "Bit"
    "字节" = "Byte"
    "字" = "Word"
    "双字" = "Double Word"
    "四字" = "Quad Word"
    "有符号" = "Signed"
    "无符号" = "Unsigned"
    "整数" = "Integer"
    "浮点" = "Floating Point"
    "定点" = "Fixed Point"
    "小数" = "Fractional"
    "科学计数法" = "Scientific Notation"
    "二进制" = "Binary"
    "八进制" = "Octal"
    "十进制" = "Decimal"
    "十六进制" = "Hexadecimal"
    "补码" = "Two's Complement"
    "反码" = "One's Complement"
    "原码" = "Sign-Magnitude"
    "移码" = "Excess Code"
    "格雷码" = "Gray Code"
    "BCD 码" = "BCD Code"
    "ASCII 码" = "ASCII Code"
    "Unicode" = "Unicode"
    "UTF-8" = "UTF-8"
    "UTF-16" = "UTF-16"
    "UTF-32" = "UTF-32"
    "大端" = "Big Endian"
    "小端" = "Little Endian"
    "字节序" = "Byte Order"
    "位序" = "Bit Order"
    "最高有效位" = "MSB"
    "最低有效位" = "LSB"
    "最高有效字节" = "MSB"
    "最低有效字节" = "LSB"
}

# English to Chinese
$EnglishToChinese = @{}
foreach ($key in $ChineseToEnglish.Keys) {
    $EnglishToChinese[$ChineseToEnglish[$key]] = $key
}

# Convert comments function
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

# Show help
function Show-Help {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Backup and Vivado Synchronization Tool" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\sync_backup_vivado.ps1 -BackupToVivado   # Backup -> Vivado" -ForegroundColor White
    Write-Host "  .\sync_backup_vivado.ps1 -VivadoToBackup   # Vivado -> Backup" -ForegroundColor White
    Write-Host ""
    Write-Host "Description:" -ForegroundColor Yellow
    Write-Host "  -BackupToVivado:  Sync backup folder to Vivado (Chinese to English)" -ForegroundColor Gray
    Write-Host "  -VivadoToBackup:  Sync Vivado folder to backup (English to Chinese)" -ForegroundColor Gray
    Write-Host ""
}

# Main sync logic - Backup to Vivado
if ($BackupToVivado) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Sync from Backup to Vivado (CN->EN)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $sync_count = 0
    $error_count = 0
    
    foreach ($backupSubPath in $FileMapping.Keys) {
        $backupFile = Join-Path $BackupPath $backupSubPath
        $vivadoFile = Join-Path $ScriptRoot "..\" $FileMapping[$backupSubPath]
        
        if (Test-Path $backupFile) {
            Write-Host "Processing: $backupSubPath" -ForegroundColor Yellow
            
            try {
                # Read backup file
                $content = Get-Content $backupFile -Raw -Encoding UTF8
                
                # Convert comments to English
                $content = Convert-Comments -Content $content -Mapping $ChineseToEnglish -ToEnglish
                
                # Determine target path
                $targetPath = if ($backupSubPath -like "testbenches\*") {
                    $VivadoSimPath
                } elseif ($backupSubPath -like "rtl\*" -or $backupSubPath -like "sim_models\*") {
                    $VivadoSourcesPath
                } else {
                    $VivadoConstrsPath
                }
                
                $targetFile = Join-Path $targetPath (Split-Path $backupFile -Leaf)
                
                # Save to Vivado path
                Set-Content $targetFile -Value $content -Encoding UTF8
                Write-Host "  ✓ Synced to: $targetFile" -ForegroundColor Green
                $sync_count++
            } catch {
                Write-Host "  ✗ Sync failed: $($_.Exception.Message)" -ForegroundColor Red
                $error_count++
            }
        } else {
            Write-Host "  ℹ File not found: $backupFile" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Sync Complete" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Success: $sync_count files" -ForegroundColor Green
    Write-Host "  Failed: $error_count files" -ForegroundColor $(if ($error_count -eq 0) {"Green"} else {"Red"})
    Write-Host ""
}
# Main sync logic - Vivado to Backup
elseif ($VivadoToBackup) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Sync from Vivado to Backup (EN->CN)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $sync_count = 0
    $error_count = 0
    
    foreach ($backupSubPath in $FileMapping.Keys) {
        $vivadoFile = Join-Path $ScriptRoot "..\" $FileMapping[$backupSubPath]
        $backupFile = Join-Path $BackupPath $backupSubPath
        
        if (Test-Path $vivadoFile) {
            Write-Host "Processing: $backupSubPath" -ForegroundColor Yellow
            
            try {
                # Read Vivado file
                $content = Get-Content $vivadoFile -Raw -Encoding UTF8
                
                # Convert comments to Chinese
                $content = Convert-Comments -Content $content -Mapping $EnglishToChinese -ToEnglish
                
                # Create target directory
                $targetDir = Split-Path $backupFile -Parent
                if (!(Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
                
                # Save to backup path
                Set-Content $backupFile -Value $content -Encoding UTF8
                Write-Host "  ✓ Synced to: $backupFile" -ForegroundColor Green
                $sync_count++
            } catch {
                Write-Host "  ✗ Sync failed: $($_.Exception.Message)" -ForegroundColor Red
                $error_count++
            }
        } else {
            Write-Host "  ℹ File not found: $vivadoFile" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Sync Complete" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Success: $sync_count files" -ForegroundColor Green
    Write-Host "  Failed: $error_count files" -ForegroundColor $(if ($error_count -eq 0) {"Green"} else {"Red"})
    Write-Host ""
}
else {
    Show-Help
}
