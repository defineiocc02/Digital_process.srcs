# 更新日志 (CHANGELOG)

本文件记录项目的所有重要更新和变更。

## [3.0.0] - 2026-03-01

### Added - 新增
- ✅ 创建 `organized_code/` 目录，包含完整整理后的代码
- ✅ 添加 17 个 README.md 文档，覆盖所有模块和目录
- ✅ 新增 `docs/CODE_STRUCTURE.md` - 代码组织结构指南
- ✅ 新增 `docs/MIGRATION_COMPLETE.md` - 重组完成报告
- ✅ 新增 `organized_code/SUMMARY.md` - 快速总结文档
- ✅ 添加版本管理和时间戳规范说明

### Changed - 变更
- ✅ 重新组织代码结构，按功能模块分类：
  - `rtl/calibration/` - 校准模块
  - `rtl/reconstruction/` - 重构模块
  - `rtl/sar_logic/` - SAR 逻辑控制
  - `rtl/decoder/` - Flash 译码器
  - `rtl/top/` - 顶层模块
  - `sim_models/` - 仿真模型
  - `testbenches/` - 测试平台
  - `constraints/` - 约束文件
  - `scripts/` - 工具脚本
  - `docs/` - 技术文档
- ✅ 更新主 README.md，添加完整的版本历史
- ✅ 规范化文档格式和时间戳

### Improved - 改进
- ✅ 改进代码可读性和可维护性
- ✅ 改进文档完整性和一致性
- ✅ 改进版本管理规范（采用语义化版本号）
- ✅ 改进时间戳格式（ISO 8601 标准）

### Fixed - 修复
- ✅ 删除临时文件 `organized_code_file_list.txt`
- ✅ 统一所有文档的日期格式
- ✅ 统一作者信息格式

### Technical Details - 技术细节
- **文件统计**：
  - RTL 源代码：5 个
  - 仿真模型：1 个
  - 测试平台：4 个
  - 约束文件：1 个
  - 工具脚本：1 个
  - 文档文件：17 个
  - **总计**：29 个文件

- **向后兼容性**：
  - ✅ 保留原有 `sources_1/new/` 目录
  - ✅ 保留原有 `sim_1/new/` 目录
  - ✅ 保留原有 `constrs_1/new/` 目录
  - ✅ 现有 Vivado 工程不受影响

---

## [2.0.0] - 2026-02-22

### Added - 新增
- ✅ 添加串行累加优化，改善时序收敛
- ✅ 增强 ASIC 兼容性，添加复位初始化逻辑
- ✅ 完善测试平台，添加蒙特卡洛分析

### Changed - 变更
- ✅ 优化权重计算逻辑，减少资源占用
- ✅ 改进状态机设计，提高可靠性

### Improved - 改进
- ✅ 改进时序收敛，工作频率提升至>50MHz
- ✅ 改进代码注释和文档
- ✅ 改进测试覆盖率

### Technical Details - 技术细节
- **性能提升**：
  - 时序裕量增加 30%
  - 资源占用减少 15%
  - 校准精度提高至<0.5 LSB

---

## [1.0.0] - 2026-02-15

### Added - 新增
- ✅ 实现基本校准算法（递归测量）
- ✅ 实现重构引擎（加权求和）
- ✅ 实现 SAR 控制器
- ✅ 实现 Flash 译码器
- ✅ 完成 FPGA 板级验证
- ✅ 添加基础测试平台

### Technical Details - 技术细节
- **初始功能**：
  - 20-bit 电容位数
  - 16-bit 输出分辨率
  - 30-bit 权重存储（Q22.8 格式）
  - 基本校准流程

---

## 版本命名规范

本项目采用**语义化版本号**（Semantic Versioning）：`主版本号。次版本号.修订号`

- **主版本号（Major）**：不兼容的 API 修改或架构变更
- **次版本号（Minor）**：向下兼容的功能性新增
- **修订号（Patch）**：向下兼容的问题修正

### 版本号示例

- `v1.0.0` - 初始发布版本
- `v1.1.0` - 新增功能，向下兼容
- `v1.1.1` - 修复 bug
- `v2.0.0` - 重大架构变更，可能不兼容

---

## 时间戳规范

本项目所有文档和代码文件的时间戳遵循以下规范：

- **日期格式**：YYYY-MM-DD (ISO 8601)
- **时区**：CST (China Standard Time, UTC+8)
- **记录位置**：
  - 文档末尾：`*最后更新时间：YYYY-MM-DD*`
  - 版本历史：在更新日志中详细记录
  - 代码文件：在文件头部注释中注明

---

## 发布流程

### 发布新版本前检查清单

- [ ] 更新 CHANGELOG.md
- [ ] 更新所有 README.md 中的版本号
- [ ] 运行所有测试平台，确保通过
- [ ] 检查文档完整性和一致性
- [ ] 提交 Git 并打标签
- [ ] 推送到远程仓库

### Git 标签

```bash
# 创建新版本标签
git tag -a v3.0.0 -m "Release version 3.0.0 - Code Reorganization"

# 推送标签到远程
git push origin v3.0.0
```

---

## 联系方式

**作者**：Zhao Yi  
**邮箱**：717880671@qq.com  
**项目**：SAR ADC 数字处理系统

---

*本更新日志遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/) 规范*
