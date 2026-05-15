# Archive

此目录保存不再作为主线维护对象的资料。

## 内容

- `legacy_vivado_projects/sar_adc_project/`：早期 SAR ADC Vivado 工程。
- `legacy_vivado_projects/Verifiy/`：早期验证工程，原目录名保留。
- `binary_snapshots/sar_adc_v3.rar`：原始压缩快照，不提交到 Git。
- `git_metadata/`：从嵌套工程目录移出的旧 Git 元数据，不提交到 Git。

## 使用原则

1. 需要对照旧实现时可以读取归档。
2. 新功能和修复应进入 `Digital_process/` 主工程。
3. 归档工程如果需要重新启用，应先复制到新分支或新目录，再单独整理依赖。
