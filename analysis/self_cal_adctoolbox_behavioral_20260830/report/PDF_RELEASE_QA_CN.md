# 16 位 SAR 自校准报告 PDF 发布记录

## 1. 发布对象

| 项目 | 内容 |
|---|---|
| PDF | `SAR16B_SELF_CAL_SRM_BEHAVIORAL_REPORT_CN.pdf` |
| XeLaTeX 源文件 | `SAR16B_SELF_CAL_SRM_BEHAVIORAL_REPORT_CN.tex` |
| 页面 | 38 页，A4 |
| 生成日期 | 2026-08-30 |
| SHA-256 | `281B315DD6A12FF80CC6A35C234F5A2E58EA03C6B101FAF689E76E462AFABD90` |
| 算法与实验证据提交 | `8e35335ed51fdd015be54ce4909c717dcb22509d` |
| 排版引擎 | XeLaTeX / MiKTeX 25.12 |

## 2. 版式合同

- A4、11 pt、2.25 cm 页边距；
- 中文 FandolSong Regular/Bold；
- 拉丁文 Latin Modern Roman；
- 数学 Computer Modern；
- 代码 Latin Modern Mono；
- booktabs 三线表，无竖线；
- 居中章标题与节标题；
- 细页眉线、左侧短标题、右侧章标题、页脚居中页码；
- 蓝、青、绿、橙、紫、灰语义色块，仅用于方法、证据、通过、风险、诊断和复现提示；
- 五张实验图直接引用冻结的 `outputs/*.png`，数值以 JSON/CSV 为准。

## 3. 构建与自动门禁

1. XeLaTeX 三遍编译：PASS。
2. 编译日志检查：无 `Overfull`、`Missing character`、未解析引用、重复标签或 `Infinite glue`。
3. CJK Unicode 映射注入：PASS，2 个字体、919 个 code mapping。
4. PDF release gate：PASS。
5. Reference-style gate：PASS。
6. 字体嵌入：PASS；无 Type 3 字体。
7. 页面下限：PASS，实际 38 页。
8. 日文误混入检查：PASS。
9. 固定 `SOURCE_DATE_EPOCH=1788019200` 完整重建：PASS。
10. 重建前后字节级 SHA-256 完全一致：PASS。

确定性重建结果：

```text
first_sha256   = 281B315DD6A12FF80CC6A35C234F5A2E58EA03C6B101FAF689E76E462AFABD90
rebuild_sha256 = 281B315DD6A12FF80CC6A35C234F5A2E58EA03C6B101FAF689E76E462AFABD90
deterministic_byte_match = PASS
```

## 4. 逐页视觉 QA

使用 Poppler 以 120 dpi 将全部 38 页渲染为 PNG，并检查总览 contact sheet。随后按原始分辨率重点检查：

| 角色 | 页码 | 结果 |
|---|---:|---|
| 封面 | 1 | 标题层级、英文副题、元数据与底部声明清晰，未溢出 |
| 摘要与执行摘要 | 2-3 | 正文密度、语义色块、关键结论表可读 |
| 目录/图表目录 | 4-7 | 页码与链接层级完整 |
| 公式与数学原理 | 12-14 | Computer Modern 数学清晰，公式未裁切 |
| decoder matrix | 18 | 长名称可换行，表格不越界 |
| 核心结果图 | 23-26 | 图例、坐标、caption 在 A4 页面尺寸可辨 |
| ASIC 风险表 | 31 | 三列表格与风险色块无重叠 |
| 参考文献 | 37 | 文献条目和提交标识完整 |
| 封底追溯 | 38 | 报告源、证据提交和日期完整 |

未发现空白异常页、裁切、重叠、错位图片、乱码、不可见文字或页码断裂。

## 5. 已知环境提示

MiKTeX 在命令行提示“尚未检查更新”和“以管理员权限运行”的环境级警告。该提示不影响编译结果、PDF 内容或发布门禁；本次 PDF 已通过字节级确定性重建。后续环境维护时可单独更新 MiKTeX，但不得在未重新执行全部 PDF QA 的情况下覆盖本发布件。

## 6. 发布结论

`SAR16B_SELF_CAL_SRM_BEHAVIORAL_REPORT_CN.pdf` 满足本工程中文学术技术报告的发布要求，可以作为本次 16 位片上自校准、SRM 与 ADCToolbox 行为验证的正式 PDF 交付件。
