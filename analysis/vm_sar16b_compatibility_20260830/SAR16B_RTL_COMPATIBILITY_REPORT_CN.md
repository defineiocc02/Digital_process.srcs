# VM `SAR_16B` 系列电路与当前 RTL 兼容性审查报告

## 1. 审查结论

**结论：当前 RTL 的三个算法核心可以作为 VM 中 `SAR_16B_5M` 电路的数字后端基础，但不能按现有端口直接接入。**

更具体地说：

| 对象 | 结论 | 当前状态 |
| --- | --- | --- |
| 20 路加权重构 `sar_reconstruction` | 架构匹配，可复用 | 必须修正 raw-bit 映射、EOC/valid、时钟域和 Cadence symbol |
| 前台递归权重校准 `sar_calib_ctrl_serial` | 原理匹配，条件式可用 | 必须增加模拟侧校准时序器、模式仲裁和 CDAC 开关映射 |
| SRM 残差估计 `srm_residue_estimator` | 数学模块可复用，现有电路尚无所需序列 | 必须在模拟顶层新增明确的 22 次随机比较序列，或按实际次数重建 LUT |
| `sar_adc_digital_top` | 可综合的数字集成骨架 | 不是可直接替换 VM 异步 SAR 控制链的完整 mixed-signal top |
| VM 中旧 `Digital_Process` / `sar_reconstruction` | 仅可作历史参考 | 版本落后、接口不全，且顶层实例实际被 netlister 忽略 |

因此，回答“能否用在里面”时应区分三层：

1. **算法层：能。** 20 个 CDAC 决策、6 位低位参考段、冗余权重结构均与当前数字校准/重构方向相符。
2. **RTL 核层：能。** 本轮四组 XSIM 回归全部通过，四模块数字顶层也完成 Vivado 综合。
3. **当前 VM 接线层：不能直接用。** 已存在严重位序、valid、时钟、校准物理接口和 SRM 序列缺口。

本报告不声称已经完成 mixed-signal 仿真闭环。VM 操作为只读审查，没有改写原理图、Maestro 状态或工艺库。

## 2. 审查范围与证据边界

审查时间：2026-08-30（Asia/Shanghai）。

实时连接到 VM `192.168.38.140`，主机名 `meowu`。实际检查的库为：

- `/home/meow/IC/SAR_16B_5M_CORE`
- `/home/meow/IC/SAR_16B_5M_EXP`
- `/home/meow/IC/SAR_16B_5M_TB`
- `/home/meow/IC/simulation/SAR_16B_5M_TB`

实际顶层：

```text
SAR_16B_5M_TB/
  TEST_TRAN_ALL_TRANSISTOR_wFLash_ver6
```

证据由以下本地快照保存：

- `checkpoint_sar16b_series.json`：库、cell、view 与 VM 进程清单。
- `checkpoint_sar16b_hierarchy.json`：21 个 OA design 的层次、实例、网络和 pin。
- `checkpoint_sar16b_full_params.json`：顶层激励、CDAC、电源与时序参数。
- `checkpoint_text_views.json`：VM HDL 文件路径、大小和 SHA-256；具体文本快照因体积和 Cadence 生成文件属性不纳入 Git。
- `checkpoint_sar16b_maestro.json`：当前 Maestro test、analysis、输出和环境。
- `checkpoint_sar16b_history_logs.json`：现存 Maestro history log 状态。
- `local_rtl_validation_summary.json`：本轮本地 RTL 回归与综合摘要。

证据可信度分级：

| 结论类型 | 可信度 | 原因 |
| --- | --- | --- |
| OA 层次、实例端口和当前连接 | 高 | 来自实时 Virtuoso OA 数据库只读查询 |
| VM HDL 版本和哈希 | 高 | 直接从 VM 文件系统读取 |
| 当前 Maestro 设置 | 高 | 后台只读打开指定 Maestro view 并关闭 |
| 既往 Maestro 仿真是否成功 | 低/否定 | history log 明确记录 simulation errors，结果目录无可复查 PSF/netlist |
| 当前 RTL 单元功能和可综合性 | 高（限数字域） | 本轮有效 XSIM 与 Vivado 2018.3 综合 |
| RTL 接入真实 CDAC 后的校准效果 | 尚未验证 | 尚未生成修正后的 AMS 网表并运行闭环实验 |

## 3. VM 中实际 SAR 架构

### 3.1 顶层数据通路

实时层次显示的主路径为：

```text
差分输入 VIP/VIN
  -> 每侧 20 个 SS_MAIN split-sampling 单元
  -> CDAC_MAIN_20b 四段桥接 CDAC
  -> COMP_AZ（自动调零前置放大器 + latch）
  -> 2-bit Flash 初判 + 19 次比较器判决
  -> SAR_Logic_transistor_woflash 异步移位/锁存
  -> BITP/BITN<20:0>
```

顶层还包含：

- 两个 `CDAC_SWITCH_DRIVER_NEW`，分别驱动差分 CDAC 两侧，并交换 P/N 逻辑。
- `Flash` Verilog-A 与 `flash_decoder_adder` SystemVerilog。
- `sar_reconstruction` SystemVerilog 实例 `I94`，但该实例当前 `nlAction = ignore`。
- 未实例化当前仓库的 `sar_calib_ctrl_serial`、`srm_residue_estimator` 或 `sar_adc_digital_top`。

### 3.2 采样与转换时序

顶层所有主脉冲周期为 `200 ns`，对应 `5 MS/s`。当前参数包括：

| 信号 | 当前设置 | 作用判断 |
| --- | --- | --- |
| `CLKS` | `td=-90 ns`, `pw=115.5 ns` | split-sampling 主采样窗 |
| `CLKSTOP` | `td=25 ns`, `pw=5 ns`, 高到低 | 采样终止/交接窗口 |
| `CLK_nt` | `td=1 ps`, `pw=30 ns + TAZ` | 采样/预充辅助相位 |
| `CLKDAC_top` | `pw=25 ns` | CDAC/比较器顶层时序 |
| `RST` | `pw=25.2 ns` | 采样支路复位 |
| `CLKAZ` | `td=30 ns`, `pw=TAZ` | 比较器 auto-zero；当前 `TAZ=19.6 ns` |
| `RSTT` | `pw=49.5 ns` | CDAC switch driver 复位/VCM 相位 |
| `sdc` | `td=28.5 ns`, `pw=171.5 ns`, 高到低 | split-sampling 切换控制 |
| `CLK0` | `td=30 ns+TAZ` | 异步 SAR 链复位释放 |
| `CLK00` | `CLK0` 再延迟 `0.3 ns` | 相邻复位/预置相位 |

`COMP_AZ.READYN` 回送给 `SAR_Logic_transistor_woflash.CCLK`，后者按比较器 ready 事件推进 `SET<0:20>`。因此正常转换是**异步自定时 SAR**，并不是当前数字 top 假设的单一自由运行同步时钟系统。

### 3.3 真实决策位映射

这是本轮最重要的接口发现。

| 转换阶段 | 判决来源 | 锁存输出 | 是否驱动物理 CDAC |
| --- | --- | --- | --- |
| `SET<0>` | Flash bit 1 | `BITP/N<20>` | 是，CDAC bit 20 |
| `SET<1>` | Flash bit 0 | `BITP/N<19>` | 是，CDAC bit 19 |
| `SET<2>` ... `SET<19>` | comparator | `BITP/N<18>` ... `BITP/N<1>` | 是，CDAC bit 18 ... 1 |
| `SET<20>` | comparator | `BITP/N<0>` | 否，是最终附加判决/残差信息 |

`CDAC_SWITCH_DRIVER_NEW` 的连接进一步确认：

```text
SET<0>  -> BITU/D<20>
SET<1>  -> BITU/D<19>
...
SET<19> -> BITU/D<1>
```

所以 20 路重构输入的正确基本映射应为：

```systemverilog
raw_bits[19:0] = BITP[20:1];
```

其中 `raw_bits[19]` 对应模拟 CDAC bit 20（MSB），`raw_bits[0]` 对应模拟 CDAC bit 1（LSB）。`BITP<0>` 不应混入 20 路 CDAC 权重和。

## 4. 当前 VM 顶层的阻断问题

### P0-1：现有重构实例码位接错

VM 顶层实例 `I94` 当前连接为：

```text
raw_bits<19:0> = BITP<19:0>
data_valid_in  = BITP<20>
```

这会同时造成：

- 丢失 Flash/CDAC 的最高位 `BITP<20>`；
- 错把不驱动 CDAC 的最终附加判决 `BITP<0>` 当作 LSB；
- 错把 Flash 数据位 `BITP<20>` 当成 valid 脉冲。

这不是轻微标号差异，而是足以破坏重构线性、符号和时序的系统级错误。

### P0-2：重构实例实际上未参与 netlist

实例 `I94` 带有：

```text
nlAction = ignore
```

而且以下网络均只有 `I94` 一个连接端：

```text
rst_n
w_wr_en
w_wr_addr<4:0>
w_wr_data<29:0>
data_valid_out
adc_dout<15:0>
```

VM 中旧版 `sar_reconstruction` 还把 20 个 `weight_ram` 全部初始化为零，只能依赖 `w_wr_*` 写入。即使去掉 `ignore`，以当前悬空写口和 reset 接线也不能形成有效重构。

### P0-3：把比较器 `CLK` 当数字流水时钟不成立

`I94.clk` 当前接在比较器/SAR 异步脉冲 `CLK` 上。该时钟只在一次转换的异步比较序列中活动，转换结束后不会继续提供重构流水线所需的稳定边沿。

当前 `sar_reconstruction` 是多级流水线。应使用独立自由运行数字时钟，并在 EOC 时把锁存后的 `BITP<20:1>` 跨时钟域送入重构模块。直接使用 comparator `CLK` 可能导致：

- 最后一个 code 尚未完成流水就停止时钟；
- raw bus 在异步更新期间被采样；
- EOC 与数据没有原子性；
- reset 周期开始时上一笔 code 被覆盖。

### P0-4：`CDAC_MAIN_20b` 存在需核实的 OA 连接异常

实时 OA 层次显示：

- N 侧出现两套看似并联且完整的桥接电容链。
- P 侧第二套链中的 `net22` ... `net28` 为单端连接，涉及桥电容以及 bit 11...15 的若干电容。
- 多个原 `analogLib/cap` 与 `tsmc18/cfmom` 替换件同时存在；部分 `cfmom` 的 `c=7.41408 fF`，而 Maestro 当前变量 `cf=40 fF`。

这可能是：

1. 有意的并联/版图等效建模；
2. 电容替换后遗留的旧支路；
3. 迁移过程中断开的桥接网络；
4. 实际原理图错误。

在生成当前 Spectre netlist并核对每个端点之前，不能把本地 proxy 权重表当作该 VM CDAC 的已验证真实权重。若这些支路确实参与网表，差分两侧会出现严重不对称，数字校准的前提也会被破坏。

### P1：VM HDL 视图落后于当前仓库

VM `sar_reconstruction/systemVerilog/verilog.sv`：

- 没有 `srm_residue` 端口；
- 20 个权重上电为零；
- 没有当前版本的参数约束和低 6 位 Q8 reset 默认值。

VM `Digital_Process` 是旧校准控制器版本。VM `sar_adc_controller` 是另一个通用同步 SAR 控制器，当前没有实例化，也不等价于 transistor asynchronous SAR 链。

因此必须从当前仓库重新建立 Cadence SystemVerilog view、symbol 和 config binding，不能只替换文本而保留旧 symbol。

### P1：现有 SRM 判决数不闭合

当前正常转换共有 21 个锁存判决：2 个 Flash + 19 个 comparator，其中仅 20 个驱动物理 CDAC，另有 `BITP/N<0>` 一个附加判决。

当前 `srm_residue_estimator` 的 LUT 固定为 `DECISION_COUNT=22`。电路顶层尚未提供 22 次同一残差条件下的随机比较，也没有 `srm_start/decision_valid/decision_bit` 接口。因此：

- 不能把 `BITP<20:0>` 直接理解成 22 次 SRM；它只有 21 位，且前 20 位承担正常逐次逼近。
- 不能只补一位常数或重复最后一位；这样会破坏 inverse-normal 统计假设。
- 必须实现明确的 residue hold、重复 comparator evaluate、decision counter 和完成握手。

## 5. 当前 RTL 与该电路的算法匹配性

### 5.1 加权重构

当前 RTL 对每个 raw bit 使用双极性符号：

\[
s_i = \begin{cases}
+1, & b_i=1 \\
-1, & b_i=0
\end{cases}
\]

并形成：

\[
S = \sum_{i=0}^{19}s_iW_i
\]

当前实现的输出等效为：

\[
D_{out}=\operatorname{sat}_{16}\left(
\operatorname{round}\left[
\frac{S/2+R_{SRM}}{2^{8}}
\right]\right)
\]

其中：

- `W_i` 是 Q8 权重，`256` 表示重构域的一个权重 LSB；
- `/2` 来自双极性 `+W/-W` 表示到单端 code 增量的归一化；
- `R_SRM` 与权重使用相同 Q8 单位；
- `R_SRM=+256` 会使最终输出增加 1 code。

该方法适合 20-decision、16-bit 目标且具有非二进制冗余权重的 SAR。VM CDAC 的四段桥接结构与本地模型采用的 `6+4+5+5` 关系在概念上吻合，因此重构算法方向是正确的。

不过，必须从修正后的 VM netlist提取实际 `W_i`，再确定 Q8 量化和全局增益。当前本地参考表：

```text
1, 2, 4, 8, 16, 32,
33.53, 67.05, 134.10, 268.20,
316.91, 316.91, 633.81, 1267.63, 2535.25,
5031.09, 5031.09, 10062.17, 20124.35, 40248.69
```

只可作为理想四段网络的起始估计，不应直接宣称等于当前 VM 实物权重。

### 5.2 前台递归权重校准

当前校准核心的基本思想是：

1. 低 6 位 `bit[5:0]` 作为可信 reference DAC，初始权重为 `256*2^i`。
2. 从目标 bit 6 开始，利用已经可信/已校准的低位权重逼近目标电容权重。
3. 分别执行 P、N 两种极性测量，利用两相和减弱 comparator offset。
4. 对每个目标 bit 重复 `AVG_LOOPS=32` 并平均，减小随机比较噪声。
5. 将估计值写入 reconstruction weight RAM，并递归用于更高位。
6. 对最高两位使用保护/bit-swapping，避免低位 reference range 不足。

理想化地，若单次估计误差标准差为 `sigma_m`，独立平均 `N` 次后：

\[
\sigma_{avg}=\frac{\sigma_m}{\sqrt{N}}
\]

P/N 两相若具有相反 offset 项，可写为：

\[
m_P=W_k+V_{os}+n_P,\qquad
m_N=W_k-V_{os}+n_N
\]

则：

\[
\hat W_k=\frac{m_P+m_N}{2}
=W_k+\frac{n_P+n_N}{2}
\]

该思想和 VM 电路中的 6 位低位段、冗余桥接 CDAC、auto-zero comparator 具有良好架构匹配性。因此对**静态、可重复、码相关的电容失配**，方案原则上能够校准。

但有效性有五个硬条件：

- 校准时走过的 CDAC 开关、参考电压和信号路径必须与正常转换等效。
- 低 6 位 reference DAC 的自身误差必须足够小，并建立真实 transfer/range 模型。
- 每次 comparator evaluate 必须在 CDAC settling 后进行，而不是仅等待任意固定数字周期。
- P/N 两相必须在模拟开关层真正翻转，而不只是交换一个数字变量。
- 顶层必须禁止 normal SAR 与 calibration 同时驱动 `BITP/BITN/SET/RSTT`。

该校准不能消除：采样开关动态非线性、reference memory、VCM 切换瞬态、比较器 metastability、kickback、频率相关 settling 和随机热噪声。它校准的是静态 effective decision weight，不是整个模拟 ADC 的所有误差。

### 5.3 SRM

当前 SRM 数字核统计 22 次二值判决中 1 的个数 `K`，通过离散 inverse-normal LUT 估计残差并输出 Q8 修正量。数学上，它要求：

- 22 次判决对应同一个被保持的模拟 residue；
- 判决噪声分布与 LUT 标定时的 sigma 一致；
- 判决样本近似独立；
- residue 与随后重构的 raw code 属于同一转换。

数字 LUT 本身本轮 XSIM 通过，但 VM 现有 conversion sequencing 不满足上述接口合同。所以 SRM 当前属于“算法可用、物理序列未实现”。

## 6. 推荐接入架构

不要直接把 `sar_adc_digital_top` 的端口硬连到现有模拟网络。建议增加以下四个明确边界模块：

```text
normal asynchronous SAR
  BITP<20:1> + SET<20>/EOC
          |
          v
sar16b_code_capture_adapter
  - 原子锁存 raw code
  - async event -> sync handshake/CDC
          |
          v
free-running digital clock domain
  sar_reconstruction + weight RAM + output valid

foreground calibration mode
  sar_calib_ctrl_serial
          |
          v
sar16b_calib_phy_sequencer
  - SS/RST/RSTT/VCM/SET/CLKAZ/compare sequencing
  - P/N polarity mapping
  - wait READYN / timeout
          |
          v
normal/calibration/SRM mode arbiter
          |
          v
two CDAC_SWITCH_DRIVER_NEW instances + COMP_AZ
```

### 6.1 `sar16b_code_capture_adapter`

职责：

- 在 `SET<20>` 完成、且 `BITP<20:1>` 稳定后锁存整笔 code。
- 输出 `raw_bits[19:0] = BITP[20:1]`。
- 不使用 `BITP<20>` 作为 valid。
- 通过 toggle synchronizer、request/ack handshake 或 async FIFO 把事件送入自由运行数字时钟域。
- 在下一次 `RST/CLK0` 清除 bit latch 前保证数据已被接收。

### 6.2 `sar16b_calib_phy_sequencer`

职责：

- 进入 foreground calibration 时冻结正常输入转换。
- 控制 split-sampling、VCM 预充、`RSTT`、target/reference CDAC 码、auto-zero 和 comparator evaluate。
- 把 `dac_p_force/dac_n_force` 转换成两个 switch driver 的互补 `BITP/BITN` 与 `SET`。
- 以 `READYN` 或明确 comparator done 为完成条件，并带最大超时保护。
- 对 P/N phase 使用真实差分极性翻转。

当前校准 core 的 `COMP_WAIT_CYC` 可作为数字侧最小等待，但不能替代模拟侧 `settled/done` 握手。

### 6.3 模式仲裁器

至少需要三态：

```text
NORMAL_CONVERT
FOREGROUND_CALIBRATE
SRM_RESIDUE_MEASURE
```

每种模式必须独占：

```text
BITP/BITN
SET
RST/RSTT
CLKAZ/comparator evaluate
SS sampling controls
```

切换模式时应先回到已知 VCM/reset 状态，禁止组合 mux 在模拟开关导通期间改变控制源。

### 6.4 SRM 序列器

如果论文/电路最终确认为 22 次 SRM，需要：

1. 正常 20 路 CDAC 决策结束后保持 residue。
2. 进入指定 SRM switching state。
3. 连续触发 22 次 comparator evaluate。
4. 每次 `READYN` 后产生一个同步 `decision_valid`。
5. 将 22 个判决送入 `srm_residue_estimator`。
6. 在 `srm_done` 后将 residue 与同一笔 raw code 一起提交给 reconstruction。

若模拟方案实际只提供其他次数，必须重新按该次数和实际噪声 sigma 计算 LUT，不能仅修改 `DECISION_COUNT` 参数。

## 7. 接口映射建议

| VM 信号 | 新适配层信号 | 当前 RTL 信号 | 说明 |
| --- | --- | --- | --- |
| `BITP<20:1>` | `captured_raw[19:0]` | `raw_bits[19:0]` | 20 路物理 CDAC 决策，位序直接降一位 |
| `BITP<0>` | `final_residue_decision` | 暂不直接连接 | 可作为残差/完成辅助证据，不是 CDAC LSB |
| `SET<20>` + `READYN/CLK` | `async_eoc` | `data_valid_in` 经 CDC 后 | 必须锁存并同步，不能用 Flash bit |
| 独立数字 clock | `dig_clk` | `clk` | 驱动校准、SRM 与 reconstruction 流水线 |
| 顶层 reset sequencing | `dig_rst_n` | `rst_n` | 与模拟 reset 释放顺序需定义 |
| `COMP/COMN` 或明确 logic decision | `calib_comp_bit` | `calib_comp_out` | 需定义极性，并用测试向量证明 |
| 两侧 switch driver 控制 | `calib_phy_*` | `dac_p_force/dac_n_force` 经适配 | 不能直接一根 bus 同时驱动两侧 |
| 22 次 comparator result | `srm_decision_*` | `srm_start/valid/bit` | 当前 VM 尚不存在 |
| calibration weight write | 内部同步总线 | `w_wr_en/addr/data` | 当前顶层应由 calibration core 直接写 reconstruction |

## 8. 本轮数字验证结果

### 8.1 XSIM

第一次调用 Vivado `.bat` wrapper 时，由于宿主进程没有 `PROCESSOR_ARCHITECTURE` 环境变量，loader 误选已不存在的 `win32.o`。这次失败发生在编译前，不能归因于 RTL。

设置：

```powershell
$env:PROCESSOR_ARCHITECTURE='AMD64'
```

后使用 Vivado 2018.3 64-bit 有效重跑，结果：

| Testbench | 结果 | 主要覆盖 |
| --- | --- | --- |
| `tb_sar_recon_binary_norm` | PASS，49 checks / 0 failed | 20-to-16 归一化、流水吞吐、权重写入、SRM ±1 code |
| `tb_recon_q8_split_weights` | PASS，17 / 0 | Q8 split-weight bit-exact manual model |
| `tb_srm_residue_estimator` | PASS，17 / 0 | 22-decision LUT 边界、中点、对称性 |
| `tb_gain_comp_check_lsb` | PASS，10 / 0 | 5 次 MC、offset=5 LSB、noise=0.5 LSB、32 averages |

校准 TB 的 5 次 MC 最差恢复误差为 `0.4937 LSB`，通过 `<0.5 LSB` 的当前单元级限制。该数字 TB 是算法证据，不是 VM CDAC 实测证据。

### 8.2 综合

对以下四个模块组成的 `sar_adc_digital_top` 运行 Vivado 2018.3 综合：

```text
sar_calib_ctrl_serial
srm_residue_estimator
sar_reconstruction
sar_adc_digital_top
```

结果：

```text
0 errors
0 critical warnings
3 warnings
WNS = +3.957 ns at 100 MHz
TNS = 0
```

Artix-7 `xc7a35tfgg484-2` 估算资源：

```text
Slice LUTs      1520
Slice Registers 1661
BRAM               0
DSP                0
```

综合器删除了 3 个未使用的中间寄存器，这是当前重构写法的优化提示，不影响本轮功能结果。当前报告没有给真实 IO delay，`check_timing` 显示 27 个 input 和 71 个 output 未指定 IO delay；因此 `WNS` 只说明内部 100 MHz 路径可达，不是 FPGA 板级或 ASIC signoff。

## 9. 必须执行的闭环验证计划

### 阶段 A：先修复静态结构

通过条件：

- 生成 `CDAC_MAIN_20b` 当前 Spectre netlist。
- P/N 两侧每一位电容、三只 bridge cap 和 top node 连接逐项对称或有明确设计依据。
- 解释或移除 `net22...net28` 单端支路；确认重复 N 侧链是否有意。
- 从实际 netlist 求出 20 个单边 effective weights，并与理想表逐项比较。
- 新 Cadence digital symbol 与当前 RTL 端口完全一致。

### 阶段 B：无噪声 normal conversion

目标是先证明纯 16-bit 数字闭环，而不是用 SRM 掩盖基础错误。

实验：

- 关闭 mismatch、transient noise 和所有随机源。
- 至少采集 512 个**有效解码输出**，不是仅仿真 512 个时钟。
- 5 MS/s 下 512 笔转换净时间为 `102.4 us`；还需加入启动和流水延迟，所以 stop time 应大于此值。
- 使用 coherent sine，分别测 oracle weight 和 nominal/calibrated path。
- SRM off 时也必须接近理想 16-bit 量化上限。

参考判断：理想 16-bit 满幅正弦的量化 SNDR 约为：

\[
6.02\times16+1.76=98.08\ \mathrm{dB}
\]

实际离散频点、输入幅度和 FFT 定义会造成小幅差异，但无噪声理想 case 若远低于约 97--98 dB，应先检查码位、增益、采样相位和 FFT，而不是归咎于 CDAC mismatch。

### 阶段 C：仅静态 mismatch 的校准实验

必须固定同一颗 mismatch chip，比较：

```text
IDEAL_NO_MISMATCH
MISMATCH_UNCALIBRATED
MISMATCH_ORACLE_WEIGHT
MISMATCH_RTL_CALIBRATED
```

要求：

- 不加采样/比较器噪声，不开 SRM。
- mismatch 来源必须是实际物理电容与 bridge/parasitic 网络，不是直接给 effective weight 加独立高斯数。
- 运行至少 100 颗 Monte Carlo；记录 mean、P5、worst，而不是只报告均值。
- 校准后的 20 个权重逐位与 oracle 比较。
- 动态指标包括 SNDR/SFDR/ENOB；静态指标用独立 ramp 或 sine histogram 提取 DNL/INL。

关键通过条件建议：

- 所有校准权重 residual `<0.5 output LSB`，或按系统误差预算给出更严格阈值。
- calibrated SNDR/SFDR 显著优于 uncalibrated，并接近 oracle，而不是只接近 nominal proxy。
- 不出现 missing code，DNL > `-1 LSB`。
- SRM off 在无噪声条件下不能比正确 normal path 额外下降。

### 阶段 D：5 MS/s 时序与 CDC

检查：

- `SET<20>` 后 code 稳定窗口。
- code capture 与下一周期 reset 之间的 margin。
- 连续 5 MS/s 无丢码、重码、跨样本混码。
- calibration mode 进入/退出时先回到 VCM/reset 安全状态。
- comparator timeout、metastability 和 CDC assertion。

### 阶段 E：SRM 独立闭环

先在无噪声下证明：

```text
SRM_OFF == SRM_ON with zero residue/no stochastic noise
```

再加入论文定义的噪声和 22 次比较，检查：

- ones-count 分布是否符合 LUT 假设；
- 22 次判决是否属于同一 residue；
- SRM residue 的 Q8 单位和符号是否正确；
- 开启 SRM 后噪声方差下降，而不是由于错误增益或错位产生虚假指标变化。

## 10. Maestro 现状

当前 test：

```text
ADC_TOP_16b_5MS_SS_SRM_TEST:TEST_TRAN_ALL_TRANSISTOR_wFLash_ver6:1
```

当前启用：

```text
tran stop = 30 us
errpreset = conservative
transient noise = enabled
noisefmax = 10 GHz
noiseruns = 100
```

30 us 在 5 MS/s 下理论上只有约 150 笔转换，无法满足 512 个有效解码点。当前 outputs 保存 P/N、VIP/VIN、Flash、`BITP<20:0>`、VCM、comparator 内部节点和功耗，但没有 `adc_dout`、`data_valid`、calibration weight 或 SRM 输出。

历史日志状态：

- `ExplorerRun.0`：1 个 simulation error。
- `Interactive.7/8/9`：各 1 个 simulation error。
- `Interactive.6`：3 个输出表达式 error。
- 当前 simulation scratch 目录没有可复查的 Spectre PSF/netlist，仅有少量 HDL/VQP 环境文件。

因此既往历史不能作为“当前 SAR16 + RTL 已经仿真通过”的证据。

## 11. 最终工程判断

当前 RTL 不应被否定，也不能被直接宣称已经接入成功。准确判断为：

> `sar_reconstruction`、`sar_calib_ctrl_serial` 和 `srm_residue_estimator` 已形成可综合、单元级通过的数字算法核；VM 的 `SAR_16B_5M` 电路在 20 路 CDAC、6 位低位参考段和冗余权重层面与其方向相容。但现有 Cadence 顶层存在错误 bit slice、错误 valid、异步时钟域不匹配、悬空/忽略的数字实例、未实现的 calibration PHY/SRM 序列，以及待确认的 CDAC 连接异常。完成适配与 mixed-signal 闭环前，不能称为可流片集成版本。

优先顺序应为：

1. **先核实并修正 CDAC 原理图/netlist。**
2. **修正 code mapping 为 `BITP<20:1>`，建立 EOC capture + CDC。**
3. **建立 foreground calibration 物理时序器和模式仲裁。**
4. **重新生成当前 RTL 的 Cadence view/symbol/config。**
5. **先做无噪声、SRM-off、512 点 normal conversion。**
6. **再做物理 mismatch 的 oracle/uncalibrated/calibrated 对照。**
7. **最后实现和验证 22-decision SRM。**
