**Purpose**
- **Goal:** 帮助 AI 代码代理快速理解并在本 SAR ADC 数字处理工程中高效工作（修改 RTL、更新测试、调试仿真、更新约束）。

**Big Picture / Architecture**
- **Project type:** Vivado 风格的 FPGA + 仿真代码库，RTL/测试/约束分离（sources / sim / constrs）。
- **Major components:**
  - **Front-end RTL / controllers:** 位于 [sources_1/new/](sources_1/new/)（例如 `sar_adc_controller.sv`, `sar_calib_ctrl_serial.sv`）负责控制流与校准逻辑。
  - **重构/数据路径:** `sar_reconstruction.sv`（位于 [sources_1/new/](sources_1/new/)）实现 ADC 重构算法。
  - **物理/仿真模型:** `virtual_adc_phy.v`（[sources_1/new/](sources_1/new/)）为仿真提供物理层模型，通常只在测试中使用。
  - **测试平台:** 仿真顶层和 testbench 在 [sim_1/new/](sim_1/new/)（例如 `tb_sar_adc_top.sv`, `tb_sar_recon.sv`）。
  - **约束:** FPGA 引脚/时序约束在 [constrs_1/new/sar_calib_fpga.xdc](constrs_1/new/sar_calib_fpga.xdc) 中。

**Discoverable patterns & conventions**
- **文件分层:** 源码放在 `sources_1/new/`，仿真放在 `sim_1/new/`，约束放在 `constrs_1/new/`。
- **命名:** 文件与模块多采用下划线风格（snake_case），testbench 文件以 `tb_` 前缀。
- **模块边界:** 控制类模块（controller）与数据通路（reconstruction/adder/decoder）分开实现；修改数据路径时请同时检查相关控制信号接口（controller 文件）。
- **仿真用模型:** `virtual_adc_phy.v` 仅用于仿真场景——勿合入综合路径。

**How to run / debug (practical hints)**
- **Primary tools:** 仓库结构表明使用 Vivado 项目与仿真（若使用第三方仿真器，请保持仿真顶层为 [sim_1/new/] 中的 `tb_` 文件）。
- **Typical flow:** 修改 RTL → 更新/编写 testbench（在 [sim_1/new/]）→ 在 Vivado/ModelSim/Questa 中运行仿真并查看波形。
- **文件联动注意点:** 若修改模块接口（端口名/宽度/顺序），请同时：
  - 更新对应的 testbench（[sim_1/new/...]），
  - 检查任何约束文件是否引用该信号（[constrs_1/new/sar_calib_fpga.xdc](constrs_1/new/sar_calib_fpga.xdc)）。

**Code patterns to follow (examples from repo)**
- **Serial calibration control:** `sar_calib_ctrl_serial.sv` 对应一个序列化校准控制流程；若要扩展校准命令，先在此模块上扩展解析/状态机，然后再更新仿真脚本以发送新的序列。
- **Reconstruction pipeline:** `sar_reconstruction.sv` 表示重建算法的集中实现；数据输入通常来自 ADC 模型（`virtual_adc_phy.v`）或 flash decoder（`flash_decoder_adder.sv`）。
- **Flash decoder + adder:** `flash_decoder_adder.sv` 将比较/译码与加法逻辑合并，改动此文件时要关注位宽与溢出处理。

**Checks an AI agent should perform before committing changes**
- **Run/Update testbench:** 确保至少有一个仿真顶层（[sim_1/new/tb_sar_adc_top.sv](sim_1/new/tb_sar_adc_top.sv) 或相关 tb）覆盖改动路径。
- **Separation of synth vs sim:** 不要把仿真-only 文件（例如 `virtual_adc_phy.v`）误加入综合流或替换综合模块。
- **Interface compatibility:** 对外部端口改动必须在所有实例化点（sources 与 sim）同步修改。

**Search tips & useful grep targets**
- 查找模块定义: `module sar_reconstruction` 或 `module sar_adc_controller`。
- 查找 testbench: `tb_` 前缀在 [sim_1/new/] 下很可靠。

**Where to look for design rationale**
- 阅读 [docs/PROJECT_ANALYSIS.md](docs/PROJECT_ANALYSIS.md) 来获取项目设计决策、性能目标与测试计划（优先级高）。

**When uncertain — safe defaults for AI edits**
- 优先修改并运行相关 testbench，再提交小而可回退的变更。
- 在不确定合成影响时，仅修改仿真文件或在 PR 描述中明确标注“仿真改动/不影响综合”。

请检查这份说明是否涵盖了你希望 AI 代理遵循的要点，或告诉我需补充的具体开发/仿真命令与 CI 流程，我会据此迭代更新。
