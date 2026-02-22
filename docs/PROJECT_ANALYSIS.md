# SAR ADC 数字处理工程 — 原理与问题分析

## 一、工程整体原理

### 1.1 系统定位

本工程是 **SAR ADC 的数字后端**，包含两条主线：

| 主线 | 功能 | 对应文件/模块 |
|------|------|----------------|
| **校准 (Calibration)** | 在已知/可控条件下测量电容权重，写入 RAM，用于后续转换的“查表/加权” | `fpga_top_wrapper` → `sar_calib_ctrl_serial` + `virtual_adc_phy` |
| **重构 (Reconstruction)** | 用已校准的权重把 SAR 的 raw bits 加权求和，得到数字码输出 | `tb_sar_recon` → `sar_reconstruction` |

关系可以概括为：

- **校准** 产出：权重 `w[0..CAP_NUM-1]`（通过 `w_wr_en / w_wr_addr / w_wr_data` 写入）。
- **重构** 使用：同一套权重 + 每次转换的 `raw_bits` → 输出 `adc_dout`（如 16-bit 有符号）。

因此：**校准是离线/上电一次（或周期重校），重构是每拍/每样本都在用**。

---

### 1.2 校准链路原理（fpga_top_wrapper）

```
  [start_sw] → sar_calib_ctrl_serial → dac_p_force / dac_n_force → virtual_adc_phy
       ↑                                      ↑                              |
       |                                      |                              |
       |                    w_wr_en/addr/data (写权重)                        |
       |                                      ↑                              |
       |                    comp_out (比较器结果) ←──────────────────────────┘
       |                                      |
       └──────────── calib_done (done_led) ───┘
```

- **sar_calib_ctrl_serial**：  
  - 在 `start_calib` 有效后，按某种顺序给 `dac_p_force` / `dac_n_force` 施加码字，驱动“虚拟 ADC”的比较器输入。  
  - 根据 `comp_out` 和算法（如逐次逼近、平均 AVG_LOOPS=32）估计各 bit 的权重。  
  - 通过 `w_wr_en / w_wr_addr / w_wr_data` 把权重写入（推测为与 `sar_reconstruction` 共享的权重 RAM 或同一接口）。

- **virtual_adc_phy**：  
  - 用 `dac_p_force`、`dac_n_force` 作为“等效 DAC 输出”，得到比较结果 `comp_out`，无需真实 ADC 模拟前端。  
  - 用于 FPGA 上闭环验证校准算法，或配合 ILA 调试。

- **fpga_top_wrapper**：  
  - 只做校准：按键/开关启动，LED 表示完成，没有在顶层显式实例化“重构”或“ADC 采样+重构”的数据通路。

---

### 1.3 重构链路原理（tb_sar_recon）

```
  raw_bits[19:0] ──┐
                   ├──→ sar_reconstruction ──→ adc_dout[15:0], data_valid_out
  w_wr_* (权重) ───┘         ↑
  data_valid_in (recon_start)┘
```

- **sar_reconstruction**（从 testbench 接口推断）：  
  - 输入：`raw_bits`（单次 SAR 转换的 20-bit 码）、权重写口 `w_wr_en/addr/data`。  
  - 内部：应实现 ** 加权和 **：  
    `sum = Σ (raw_bits[i] ? w[i] : 0)`，再经缩放（如右移 TOTAL_SHIFT = 1+FRAC_BITS 等）得到 16-bit 有符号 `adc_dout`。  
  - 注释中提到“冗余权重幅值约 2^23、防输出饱和”，说明权重是冗余/非二进制，缩放与 `FRAC_BITS`、`TOTAL_SHIFT` 需与 RTL 一致。

- **tb_sar_recon**：  
  - 用 `generate_ideal_bits(vin)` 把归一化电压 -1~+1 转成 20-bit 理想码。  
  - 用 `force_ideal_weights()` 灌入“理想权重” W[i] ∝ 2^(i+4)，验证重构通路。  
  - 三个测试：线性度、权重更新灵敏度、流水线吞吐。

---

### 1.4 数据流与参数一致性

- **CAP_NUM = 20**：校准与重构均为 20 bit/cap，一致。  
- **WEIGHT_WIDTH = 30**：两处均为 30-bit 有符号权重，一致。  
- **AVG_LOOPS = 32**：仅校准用；重构不关心。  
- **OUTPUT_WIDTH/FRAC_BITS**：仅重构用；校准只写权重，不直接产生 16-bit 输出。  
- 若权重 RAM 在 `sar_reconstruction` 内部，则 **校准控制器写的是“重构模块内部的 RAM”**；在 FPGA 上需要 **同一套逻辑既支持校准写权重，又支持正常采样+重构**，即顶层应同时包含校准控制器和重构（或“ADC 采样 + 重构”）通路。

---

## 二、问题分析

### 2.1 架构/集成问题

1. **校准与重构在顶层未统一**  
   - `fpga_top_wrapper` 只有校准（calib_ctrl + virtual_phy），没有 `sar_reconstruction`，也没有“真实 ADC raw_bits → 重构”的数据通路。  
   - 若最终产品是：**先校准 → 再正常采样 → 重构输出**，则 FPGA 顶层应有一份“正常模式”：ADC 提供 `raw_bits`，重构模块用已校准权重输出 `adc_dout`；校准模式与正常模式可复用同一 `sar_reconstruction` 的权重 RAM。

2. **testbench 与 FPGA 顶层不对应**  
   - `tb_sar_recon` 只测 `sar_reconstruction`，用 TB 自己驱动的 `w_wr_*` 灌理想权重。  
   - 没有 testbench 对 **“校准控制器 + 虚拟 ADC”** 做闭环测试（即：跑完校准后，用得到的权重再跑重构，看线性度）。  
   - 建议：要么在 TB 里增加“校准 DUT + 虚拟 ADC + 重构”的联合测试，要么至少有一个顶层把校准和重构连在一起，便于在板级/仿真统一验证。

### 2.2 仿真/测试问题

3. **理想权重的含义与注释**  
   - `force_ideal_weights()` 用 `2^(i+4)` 作为 W[i]，注释说“匹配 DUT 的 TOTAL_SHIFT”“MSB 约 2^23”。  
   - 若 RTL 的 TOTAL_SHIFT 或 FRAC_BITS 日后改动，这里容易不同步，导致线性度测试“理论值”与“Meas”偏差。  
   - 建议：在 TB 或共用头文件里用宏/参数显式写出 TOTAL_SHIFT/FRAC_BITS，理想权重和 ideal_expect 都基于同一套公式，便于维护。

4. **线性度判据过松**  
   - 当前用 `ideal_expect == adc_dout ± 1` 判 MATCH。  
   - 对于 16-bit、理想权重、理想 raw_bits，一般可以期望误差在舍入范围内（如 ±1 LSB）；若将来要做 INL/DNL 统计，建议记录 `adc_dout - ideal_expect`，并可选地输出到文件或做简单直方图，而不是只判 PASS/MATCH。

5. **Test 3 流水线背压**  
   - 连续 5 拍拉高 `recon_start`，不等待 `data_valid_out`，若 DUT 有背压（如 ready 信号）或内部缓冲有限，可能丢包或行为与预期不符。  
   - 若 RTL 明确“无背压、可满速送”，当前测法可接受；否则建议在 TB 里对 DUT 的 ready/valid 握手建模。

### 2.3 实现/维护问题

6. **mark_debug 的用途**  
   - `w_wr_en/addr/data` 加 `mark_debug` 是为了防止综合优化掉、方便 ILA 抓取；若仅为此目的，保留无妨。  
   - 若之前“55 LUTs”是因为关键逻辑被优化掉，需要确认根本原因是“逻辑未使用”还是“被误优化”；若为后者，仅靠 mark_debug 可能不够，可能还需要在综合选项中保留 hierarchy 或对关键路径加 keep/dont_touch。

7. **复位与消抖**  
   - 注释已建议对 `rst_n_btn` 做消抖；若未做，按键抖动可能造成校准或状态机异常。建议在顶层或单独模块对按键做消抖后再接 DUT。

8. **RTL 源文件不在当前工作区**  
   - 当前工作区内仅见 `tb_sar_recon.sv` 和 `fpga_top_wrapper.sv`；`sar_reconstruction`、`sar_calib_ctrl_serial`、`virtual_adc_phy` 的 RTL 未出现在本工作区。  
   - 若它们位于其他 Vivado 源目录（如 sources_1），建议在文档或 README 中注明源文件列表和依赖关系，便于后续修改和 review。

---

## 三、建议的“期望做法”（供你 CHECK 后拍板）

### 3.1 架构层面

- **方案 A（推荐）**：  
  - 做一个“完整 FPGA 顶层”，包含：  
    - 校准：`sar_calib_ctrl_serial` + `virtual_adc_phy`（仅在校准模式使能）；  
    - 重构：`sar_reconstruction`，权重由校准写入（同一套 `w_wr_*` 或共享 RAM）；  
    - 模式选择：校准时用 virtual_phy 的 `comp_out` 与 `dac_*_force`；正常采样时用真实 ADC 的 `raw_bits` 送入重构。  
  - 这样板级可以：先拨到校准模式跑完校准，再拨到正常模式采真实信号，用同一套权重。

- **方案 B（最小改动）**：  
  - 保持 `fpga_top_wrapper` 仅做校准；  
  - 另做一个“仅重构”的顶层或复用现有某顶层，在别处接真实 ADC 的 `raw_bits` 和 `sar_reconstruction`，权重由校准工程在“同一 FPGA 映像”里先跑一次写入，或通过 JTAG/寄存器预置。  
  - 需在文档中明确：校准与正常采样是同一映像两次运行，还是两个不同比特流。

### 3.2 仿真层面

- **统一参数**：在共享头文件或包中定义 CAP_NUM、WEIGHT_WIDTH、OUTPUT_WIDTH、FRAC_BITS、TOTAL_SHIFT（若 RTL 有），TB 和 RTL 都引用，避免两处改不同步。  
- **理想权重公式**：TB 中 `force_ideal_weights` 与“理论 ideal_expect”用同一套 TOTAL_SHIFT/FRAC_BITS 的公式写清（可加注释或小函数），便于和 RTL 对照。  
- **可选**：增加一个“校准+重构”联合 TB：实例化 calib_ctrl + virtual_phy + reconstruction，跑完校准后，用 virtual_phy 或 TB 生成的 raw_bits + 刚校准得到的权重跑若干点，检查线性度或误差分布。

### 3.3 实现细节

- 为 `rst_n_btn` 增加消抖模块（或明确说明由外部硬件/固件消抖），再接到所有 DUT。  
- 若 ILA 需要，保留 `mark_debug`；若仍出现逻辑被优化，再考虑 hierarchy 保留或 dont_touch。  
- 在工程根目录或 docs 下维护一个 **源文件与模块清单**（含 sar_reconstruction、sar_calib_ctrl_serial、virtual_adc_phy 的路径），便于后续你指挥具体改哪个文件。

---

## 四、小结

| 项目 | 说明 |
|------|------|
| **原理** | 校准估计电容权重并写入；重构用权重对 raw_bits 加权求和得到数字码；当前 FPGA 顶只有校准，TB 只测重构。 |
| **主要问题** | 校准与重构在顶层未集成；TB 与 FPGA 顶不对应；理想权重/参数易不同步；复位未消抖；关键 RTL 不在当前工作区。 |
| **期望做法** | 做“校准+重构”一体的顶层或明确双模式流程；仿真统一参数与理想权重公式；可选联合 TB；消抖与文档化。 |

你 CHECK 后可直接指出：要按“方案 A/B”改、先做哪几条（例如：先加消抖、先写联合 TB、先做完整顶层等），我再按你的优先级逐条给出具体修改方案或补丁（到文件/行级）。
