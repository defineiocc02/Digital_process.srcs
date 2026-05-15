# 项目文档索引

**更新时间**：2026-03-05  
**作者**：Zhao Yi

---

## 📁 文档结构

```
Digital_process.srcs/
├── README.md                              # 项目主说明（根目录）
├── Docs/                                  # 项目文档
│   ├── FILE_STRUCTURE_EXPLANATION.md      # 文件结构说明
│   ├── MIGRATION_GUIDE.md                 # 迁移指南
│   ├── MIGRATION_REPORT.md                # 迁移报告
│   └── TB_REPORT_IMPLEMENTATION_SUMMARY.md # TB 报告总结
├── Reports/                               # 项目报告
│   ├── project_report_v1.0.md             # 项目报告 v1.0
│   └── VERSION_MANAGEMENT.md              # 版本管理规范
├── test_reports/                          # 测试报告
│   ├── README.md                          # 测试报告说明
│   └── TB_REPORT_SPEC.md                  # TB 报告规范
├── REFERENCE/                             # 参考文献
│   └── README.md                          # 参考文献说明
└── scripts/                               # 脚本工具
    └── README.md                          # 脚本使用说明
```

---

## 📄 文档分类

### 1. 项目主文档

| 文档 | 位置 | 说明 |
|------|------|------|
| **README.md** | 根目录 | 项目主说明文档 |

---

### 2. 项目文档（Docs/）

| 文档 | 说明 | 用途 |
|------|------|------|
| **FILE_STRUCTURE_EXPLANATION.md** | 文件结构说明 | 完整的文件结构、分类和使用指南 |
| **MIGRATION_GUIDE.md** | 迁移指南 | 详细的文件迁移步骤和方案 |
| **MIGRATION_REPORT.md** | 迁移报告 | 迁移实施报告和统计 |
| **TB_REPORT_IMPLEMENTATION_SUMMARY.md** | TB 报告总结 | TB 自动报告功能实施总结 |

---

### 3. 项目报告（Reports/）

| 文档 | 说明 | 用途 |
|------|------|------|
| **project_report_v1.0.md** | 项目报告 v1.0 | 完整的项目技术报告 |
| **VERSION_MANAGEMENT.md** | 版本管理规范 | 版本管理和命名规范 |

---

### 4. 测试报告（test_reports/）

| 文档 | 说明 | 用途 |
|------|------|------|
| **README.md** | 测试报告说明 | 测试报告文件夹使用说明 |
| **TB_REPORT_SPEC.md** | TB 报告规范 | TB 自动生成报告的规范 |

**注意**：实际测试报告文件（*.txt）在运行 TB 后自动生成

---

### 5. 参考文献（REFERENCE/）

| 文档 | 说明 |
|------|------|
| **README.md** | 参考文献列表和说明 |

**注意**：实际 PDF 文件存放在此文件夹

---

### 6. 脚本工具（scripts/）

| 文档 | 说明 |
|------|------|
| **README.md** | 脚本工具使用说明 |

**脚本列表**：
- `automated_migration.ps1` - 自动化迁移脚本
- `sync_backup_vivado.ps1` - 备份-Vivado 同步脚本
- `verify_consistency.ps1` - 一致性验证脚本
- `fix_git_config.ps1` - Git 配置修复脚本

---

## 🔗 快速链接

### 开发相关

- [文件结构说明](Docs/FILE_STRUCTURE_EXPLANATION.md) - 了解项目结构
- [脚本使用说明](scripts/README.md) - 使用自动化工具
- [TB 报告规范](test_reports/TB_REPORT_SPEC.md) - TB 报告生成规范

### 项目管理

- [项目报告](Reports/project_report_v1.0.md) - 完整技术报告
- [版本管理规范](Reports/VERSION_MANAGEMENT.md) - 版本管理规则
- [迁移指南](Docs/MIGRATION_GUIDE.md) - 项目迁移步骤

### 参考资料

- [参考文献](REFERENCE/README.md) - 学术参考资料

---

## 📊 文档统计

| 类别 | 文档数量 |
|------|----------|
| 项目主文档 | 1 |
| 项目文档 | 4 |
| 项目报告 | 2 |
| 测试报告规范 | 2 |
| 参考文献说明 | 1 |
| 脚本说明 | 1 |
| **总计** | **11** |

---

## 💡 使用建议

### 新成员入门

1. 阅读 [README.md](../README.md) - 了解项目概况
2. 阅读 [FILE_STRUCTURE_EXPLANATION.md](Docs/FILE_STRUCTURE_EXPLANATION.md) - 熟悉文件结构
3. 阅读 [project_report_v1.0.md](Reports/project_report_v1.0.md) - 深入了解技术细节

### 日常开发

1. 查看 [脚本使用说明](scripts/README.md) - 使用自动化工具
2. 参考 [TB 报告规范](test_reports/TB_REPORT_SPEC.md) - 编写 TB
3. 遵循 [版本管理规范](Reports/VERSION_MANAGEMENT.md) - 提交代码

### 项目迁移

1. 参考 [迁移指南](Docs/MIGRATION_GUIDE.md)
2. 查看 [迁移报告](Docs/MIGRATION_REPORT.md)
3. 使用自动化脚本完成迁移

---

## 📞 联系信息

**负责人**：Zhao Yi  
**邮箱**：717880671@qq.com  
**更新日期**：2026-03-05
