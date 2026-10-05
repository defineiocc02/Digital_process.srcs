# 机器可读指标入口审计与最小防误用方案 · 2026-10-05

**结论：冻结历史文件继续保留原字节；当前指标必须经过带 scope、版本及 SHA-256 的入口。**
审计基线为 main `f180d8a4e3ec21bfcc84b904e3672553344b0114`，共 529 个跟踪文件。
未修改历史 summary 的数字，也未重新生成历史 CSV、NPZ、PDF、TeX 或交付包。

## 入口清点

审计覆盖所有跟踪文件的 JSON、CSV、NPZ、YAML、校验清单、报告宏，以及 Python
读取/汇总/生成入口和 CI。精确路径、分类理由和字节哈希列在
[`METRICS_CURRENT.json`](METRICS_CURRENT.json)；它不是对历史 summary 的覆盖层。

| 入口或文件族 | 审计结果与处理 |
|---|---|
| `docs/REVALIDATION_20261002.json` | 唯一永久固化的 current 机器证据；理想对照和物理 CDAC 主矩阵，包含环境、配置、主矩阵统计、pass rates |
| `analysis/physical_cdac_mismatch_20260729/outputs_revalidation/summary.json` 及 6 个 CSV | 历史口径；理想 SNR 95.6391892 dB < SNDR 98.0791126 dB；冻结，不作为 current |
| 同项目 `outputs/summary.json`、两个 profiles JSON/CSV 和其他 CSV | 早期矩阵、敏感性及 SRM 研究变体；历史，不能因目录名称或数字接近自动提升 |
| `analysis/full_sar_behavioral_20260729/outputs/summary.json`、逐芯片 CSV、9 个 NPZ | 历史完整行为证据；October 含噪重跑完整结果在 workflow artifacts，未完整固化在该目录；本清单不声称它是新的 current |
| `analysis/calibration_effectiveness_20260729/outputs/summary.json` 和 CSV | 历史校准有效性证据；未被 current 物理矩阵替代为同条件结果 |
| `analysis/self_cal_adctoolbox_behavioral_20260830/outputs/summary.json`、trace、metrics/weights/ablation CSV、日志 | 未重跑的后续变体；理想 SNR 95.604176 < SNDR 98.092508；metrics.csv 5/10 行存在排序矛盾；历史，需独立重验证 |
| `archive/assumption_stress_tests/effective_weight_3pct_20260729/outputs/*` | 已撤回的有效权重假设实验，CSV 805/2048 行排序矛盾；历史 |
| `archive/assumption_stress_tests/revalidation_v2_symmetric_sum_20260729/outputs_revalidation/*` | 旧 v2 模型和旧频谱口径；历史，不与主模型混合 |
| `delivery/current_calibration_validation_20260729/behavior/outputs/*`、`delivery/full_sar_behavioral_validation_20260729/behavior/outputs/*`、`delivery/physical_cdac_revalidation_20260729/evidence/*` | 旧交付镜像，连同包内代码、报告、哈希清单冻结；physical summary 与上面的旧 summary 相同字节 |
| analysis 下三个 `report/` / `report_revalidation/` 的 `.tex` 宏、表格和 PDF，以及 `docs/paper/*` | LaTeX 也能读取旧指标；纳入冻结，报告 reader 不再默认使用它们 |
| `analysis/full_flow_tapeout_review_20260830/*.json` / `*.csv` / `evidence/*.json` 和 `analysis/vm_sar16b_compatibility_20260830/*.json` / `compatibility_matrix.csv` | 历史工程诊断、RTL 验证、版图资产/层次和签核清单；不属于 current ADC 频谱证据，逐文件分类冻结 |
| `docs/LEGACY_SOURCE_MAP.json` | 源文件/blob 映射，不含 ADC 数值指标，不能作为指标入口 |
| 实验 `spec.yml` / `revalidation_spec.yml`、requirements 和 workflow YAML | 配置/依赖/运行入口，不是结果；副本仍随冻结交付包保存 |
| `analysis/surrogate/`、campaign 检查点/进度、临时输出 | producer 可生成机器记录，但不在基线固化 current 中；未经发布清单登记不能成为 current |

新增清单冻结 **410 个文件**：analysis 118、archive 105、delivery 185、docs/paper 2。
覆盖原有全部 **35 CSV、18 NPZ、44 PDF、41 TeX 和 27 个历史 JSON**。
另外两个基线 JSON 是 current 快照和非指标 source map。
NPZ 保存静态 code/DNL/transition/INL 数组，没有用于纠正旧频谱的时域波形。

**SNR ≥ SNDR 仅是必要的一致性条件，不是 current 身份。** 旧 physical 主 CSV 的
6144 对满幅/回退 SNR/SNDR 全部满足排序，其他多个历史 CSV 也满足，仍必须拒绝为 current。

## 实现与读取方式

1. 清单明确 `schema_version=1`、`metric_definition=coherent-one-sided-v1`、current
   路径和快照字节 SHA，以及每个历史文件的身份/分类。没有按最新日期、glob 或 fallback 选择。
2. `analysis/metric_evidence.py` 为 Python 标准库 reader。只发布
   `physical_cdac.ideal` / `physical_cdac.main`，返回包含身份、条件和 provenance 的 JSON envelope。
   旧路径、交付镜像、缺失/未知 scope、丢失文件、错误版本、快照/源码哈希不符直接非零失败。
3. 三个活跃报告生成器默认直接失败。只有显式 `--historical-evidence --outdir NEW_DIRECTORY`
   才允许复现；在读指标/写文件之前验证同目录的所有冻结输入，包括 CSV companions。
   输出必须新建或为空，不得覆盖历史目录；生成宏及终端信息标明 HISTORICAL 和勘误。
   当前精简 JSON 不能与旧 sigma/amplitude CSV 拼接成新的报告。
4. 一致性检查现在校验 current 和 410 个冻结文件。独立 `evidence` CI job 在 push/PR 上
   运行负例测试，并以完整 Git history 对照 `f180d8a`：不能修改历史内容后同步刷新新清单哈希来蒙混通过。
   测试还检查基线证据不能从冻结清单移除，新机器记录不能无分类进入仓库。

```bash
python -m analysis.metric_evidence --scope physical_cdac.ideal
python -m analysis.metric_evidence --scope physical_cdac.main
python -m analysis.metric_evidence --check
python scripts/check_repo_consistency.py
python -m pytest analysis/test_metric_evidence.py analysis/test_coherent_metrics.py -q

# 必须失败，不输出指标 JSON：
python -m analysis.metric_evidence --path analysis/physical_cdac_mismatch_20260729/outputs_revalidation/summary.json
python -m analysis.metric_evidence --scope physical_cdac.amplitude

# 仅用于历史资产复现，仍受勘误约束：
python analysis/physical_cdac_mismatch_20260729/report_revalidation/generate_report_assets.py --historical-evidence --outdir historical-report-new
```

## 版本与哈希的含义

- current 快照本身的 SHA-256：`bba44e9f3834f5cc01c572f189ec545de5ff3382f3febc4eab5b5e9901b888dc`。
- `provenance.summary_sha256=7230120b…` 是完整重跑 artifact 的原始 summary SHA，**不是**
  checked-in 精简快照，也不是旧历史 summary 的 SHA。reader 不拿它验证错误的文件。
- `tested_head_commit=1655d303…`、`provenance.checkout_commit=f0401fca…` 与合并基线
  `f180d8a…` 分别保留，不能替换成当前 HEAD 或合并为一个版本号。
- reader 校验四个绑定源码的实际 SHA 与记录一致，日期/提交/完整 provenance 与清单一致；
  源码漂移需明确重验证和发布新证据。reader 本身不重算数值，不要求其运行 Python/依赖版本
  等于旧数值运行环境；保留的依赖身份描述数值运行，不是安装推断。
- 六份历史 SHA256SUMS 共 213 条：基线 161 条精确匹配、42 条记录 CRLF 运输字节、10 条
  另有过时原因。原清单保留，新清单独立锚定。新 SHA 对照 checkout 实际字节；
  `.gitattributes` 使 12 个被冻结 PS1 明确为 CRLF，本轮补充默认文本 `eol=lf`，
  避免 Windows `core.autocrlf` 改写其他证据的 checkout 换行；不改变历史 Git blob。
  不作自动换行/内容归一化；修改换行也会触发哈希失败。

## 具体修改文件

| 文件 | 修改目的 |
|---|---|
| `docs/METRICS_CURRENT.json` | current 指针、scope/版本/provenance、410 个冻结文件清单 |
| `analysis/metric_evidence.py` | 严格 current reader、冻结哈希校验、历史复现 guard/CLI |
| `analysis/test_metric_evidence.py` | 实际负例、CLI/报告入口、独立 Git 基线及清单覆盖检查 |
| `analysis/calibration_effectiveness_20260729/generate_report_assets.py` | 去除静默历史读取，显式历史复现到新目录 |
| `analysis/full_sar_behavioral_20260729/report/generate_report_assets.py` | 同上，撤掉把旧 summary 称为 authoritative 的说明 |
| `analysis/physical_cdac_mismatch_20260729/report_revalidation/generate_report_assets.py` | 同上，禁止混用新 JSON 与旧 CSV companions |
| `scripts/check_repo_consistency.py` | 纳入 current/冻结字节校验 |
| `.github/workflows/numerical-metrics.yml` | 独立快速 evidence job，完整 history 对照基线 |
| `.gitattributes` | 默认文本 checkout 为 LF，保留已有 PS1/BAT CRLF 例外，使跨平台字节哈希稳定 |
| `AGENTS.md`、`.github/copilot-instructions.md` | Agent 必须经 current reader，未知 scope 失败，历史产物保留 |
| `README.md` | 机器入口前置，重跑示例明确新目录和 full campaign `--no-resume` |
| `docs/METRIC_ENTRYPOINT_AUDIT_20261005.md` | 本审计、具体文件、验收和未覆盖边界 |

## 验收条件与边界

| 验收 | 条件 |
|---|---|
| 当前理想数字 | SNR 98.07978061038199 dB、SNDR 98.0791126132558 dB，附 identity/provenance；主矩阵 512 样本 |
| 误用旧口径 | 旧 summary、镜像、未知源/scope 均非零退出且无指标 stdout；即使仅路径/哈希重指向旧 summary 也拒绝 |
| 身份漂移 | 版本、快照字节、provenance、四个源码 SHA 漂移均失败；重新计算快照哈希不能绕过排序/provenance 检查 |
| 冻结不变 | 410 个文件 SHA 全匹配，Git 对照基线无历史改写；清单删项、历史文件与清单同时改写也不能通过 |
| 报告入口 | 无参失败；显式历史模式只写新目录；JSON/CSV 任一变化先失败，旧报告和输入目录不受写入 |
| CI | evidence job、现有相关数值检查及 repository consistency 全绿；新增 CI 失败是状态信号，尚不等于 branch protection 强制阻止合并 |

这是最小发布入口防护，不拦截外部 Agent 自行绕过 API 直接 `json.load`；仓库 Agent 指令和 CI
让合规入口固定、误用可见。当前 main 没有 required checks，若要强制合并门禁需另行配置仓库规则。

**producer 默认输出路径仍是历史目录。** 为保持固化快照绑定的数值源码不变，本轮没有更改
数值 producer。所有重跑必须显式 `--outdir` 新目录；full campaign 使用 `--no-resume`。
已有 full campaign 检查点绑定配置、源码、Python/依赖身份，但其他 producer 不自动获得同等能力。
CI/一致性检查会检测覆盖后的字节变化，不能撤销本地 producer 的写入。

GitHub artifacts 有保留期限。本轮不下载/复制 artifacts，也不把完整行为重跑、sigma/amplitude
扫描或后续消融冒充成已永久固化的 current。它们需保存完整结果、环境、源码和独立 scope 后再发布。
全系统重跑、RTL/AMS/PVT/PEX/硅片签核不属于本次 reader 防护验证。
