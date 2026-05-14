# 报告文档版本管理规范

**文档版本**：v1.0.0  
**发布日期**：2026-03-05  
**适用范围**：Reports 目录下所有报告文档  

---

## 1. 版本管理策略

### 1.1 文件命名规范

#### 1.1.1 标准格式

```
<文档名称>_v<主版本>.<次版本>.<修订号>.md
```

#### 1.1.2 命名示例

```
project_report_v1.0.0.md    # 初始版本
project_report_v1.1.0.md    # 功能新增
project_report_v1.0.1.md    # 问题修正
project_report_v2.0.0.md    # 重大变更
```

### 1.2 版本号规则

采用**语义化版本号**（Semantic Versioning）：

```
主版本号。次版本号.修订号
```

#### 1.2.1 版本号定义

| 版本号 | 更新类型 | 说明 | 示例 |
|--------|----------|------|------|
| 主版本号 | 重大变更 | 不兼容的 API 修改 | v1.0.0 → v2.0.0 |
| 次版本号 | 功能新增 | 向下兼容的功能性新增 | v1.0.0 → v1.1.0 |
| 修订号 | 问题修正 | 向下兼容的问题修正 | v1.0.0 → v1.0.1 |

#### 1.2.2 版本号递增规则

1. **主版本号递增**：
   - 文档结构重大调整
   - 内容组织方式改变
   - 核心技术方案变更

2. **次版本号递增**：
   - 新增章节或内容
   - 扩展技术细节
   - 添加新的分析结果

3. **修订号递增**：
   - 修正错别字
   - 更新数据或图表
   - 优化排版格式

### 1.3 Git 版本控制

#### 1.3.1 Git 标签管理

```bash
# 创建标签
git tag -a report_v1.0.0 -m "Release project report v1.0.0"

# 推送标签到远程
git push origin report_v1.0.0

# 查看所有标签
git tag -l

# 删除标签（如需要）
git tag -d report_v1.0.0
git push origin :refs/tags/report_v1.0.0
```

#### 1.3.2 提交信息规范

```
<类型>(<范围>): <简短描述>

<详细描述>

<页脚>
```

**类型说明**：

| 类型 | 说明 | 示例 |
|------|------|------|
| docs | 文档更新 | docs(report): 添加构建策略章节 |
| feat | 新增功能 | feat(report): 添加性能分析章节 |
| fix | 修正错误 | fix(report): 修正数据统计错误 |
| refactor | 重构文档 | refactor(report): 重新组织章节结构 |
| style | 格式调整 | style(report): 统一标题格式 |

**提交示例**：

```
docs(report): 添加构建策略章节

- 详细说明 Vivado 构建工具选择依据
- 添加构建流程设计图
- 说明依赖管理方案
- 列举构建优化措施

Closes #123
```

---

## 2. 文档更新流程

### 2.1 标准更新流程

```
┌─────────────┐
│  识别需求   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  创建分支   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  更新文档   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  审查文档   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  合并分支   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  打标签     │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  发布文档   │
└─────────────┘
```

### 2.2 分支管理策略

#### 2.2.1 分支命名

```
report/<类型>-<简短描述>-<日期>
```

**示例**：

```
report/feat-build-strategy-20260305
report/fix-data-error-20260305
report/refactor-structure-20260305
```

#### 2.2.2 分支操作

```bash
# 创建并切换分支
git checkout -b report/feat-build-strategy-20260305

# 更新文档
# ...

# 提交更改
git add Reports/project_report_v1.1.0.md
git commit -m "docs(report): 添加构建策略章节"

# 推送分支
git push origin report/feat-build-strategy-20260305

# 创建 Pull Request
# ...

# 合并到主分支
git checkout main
git merge report/feat-build-strategy-20260305

# 删除分支
git branch -d report/feat-build-strategy-20260305
```

---

## 3. 文档审查标准

### 3.1 内容审查

#### 3.1.1 技术准确性

- [ ] 技术描述准确无误
- [ ] 数据统计正确
- [ ] 图表清晰易懂
- [ ] 代码示例可运行

#### 3.1.2 完整性

- [ ] 章节完整无遗漏
- [ ] 内容详实丰富
- [ ] 参考文献齐全
- [ ] 术语表完整

#### 3.1.3 一致性

- [ ] 术语使用一致
- [ ] 格式风格统一
- [ ] 版本号正确
- [ ] 时间戳准确

### 3.2 格式审查

#### 3.2.1 Markdown 格式

- [ ] 标题层级正确
- [ ] 列表格式规范
- [ ] 表格对齐
- [ ] 代码块语法正确

#### 3.2.2 排版规范

- [ ] 段落间距合理
- [ ] 中英文混排正确
- [ ] 标点符号规范
- [ ] 缩进对齐

---

## 4. 文档归档策略

### 4.1 历史版本归档

#### 4.1.1 归档目录结构

```
Reports/
├── archive/                    # 历史版本归档
│   ├── v1.0/
│   │   ├── project_report_v1.0.0.md
│   │   └── project_report_v1.0.1.md
│   ├── v1.1/
│   │   └── project_report_v1.1.0.md
│   └── v2.0/
│       └── project_report_v2.0.0.md
├── project_report_v2.1.0.md   # 当前版本
└── README.md                  # 报告索引
```

#### 4.1.2 归档规则

1. **主版本归档**：每个主版本创建独立目录
2. **保留所有版本**：不删除历史版本
3. **添加归档说明**：每个版本添加归档说明

### 4.2 文档索引

#### 4.2.1 README.md 索引

创建 `Reports/README.md` 作为文档索引：

```markdown
# 项目报告文档索引

## 当前版本

- [项目报告 v1.0](project_report_v1.0.md) - 2026-03-05

## 历史版本

### v1.0.x

- [v1.0.0](archive/v1.0/project_report_v1.0.0.md) - 2026-03-05
  - 初始版本，完整项目报告

## 文档说明

- **文档类型**：技术报告
- **更新频率**：按需更新
- **版本管理**：语义化版本号
```

---

## 5. 协作规范

### 5.1 多人协作流程

#### 5.1.1 协作步骤

1. **任务分配**：明确各成员负责的章节
2. **并行编辑**：各成员在独立分支编辑
3. **合并冲突**：及时解决合并冲突
4. **统一审查**：最终统一审查和发布

#### 5.1.2 冲突解决

```bash
# 拉取最新更改
git pull origin main

# 解决冲突
# 手动编辑冲突文件

# 标记冲突已解决
git add <冲突文件>
git commit -m "resolve merge conflicts"

# 推送更改
git push origin <分支名>
```

### 5.2 审查流程

#### 5.2.1 Pull Request 审查

1. **创建 PR**：提交 Pull Request
2. **自动检查**：运行自动化检查脚本
3. **人工审查**：至少一人审查通过
4. **合并代码**：审查通过后合并

#### 5.2.2 审查清单

- [ ] 文档格式正确
- [ ] 内容准确完整
- [ ] 版本号更新正确
- [ ] 时间戳更新正确
- [ ] 无敏感信息泄露

---

## 6. 自动化工具

### 6.1 版本号自动更新

创建脚本 `scripts/update_report_version.sh`：

```bash
#!/bin/bash

# 更新报告版本号脚本

OLD_VERSION=$1
NEW_VERSION=$2
REPORT_FILE="Reports/project_report_${NEW_VERSION}.md"

# 复制旧版本文件
cp "Reports/project_report_${OLD_VERSION}.md" "$REPORT_FILE"

# 更新版本号
sed -i "s/v${OLD_VERSION}/v${NEW_VERSION}/g" "$REPORT_FILE"

# 更新日期
sed -i "s/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}/$(date +%Y-%m-%d)/g" "$REPORT_FILE"

echo "Report version updated: $OLD_VERSION -> $NEW_VERSION"
```

### 6.2 文档生成脚本

创建脚本 `scripts/generate_report_index.sh`：

```bash
#!/bin/bash

# 生成报告索引脚本

INDEX_FILE="Reports/README.md"

echo "# 项目报告文档索引" > "$INDEX_FILE"
echo "" >> "$INDEX_FILE"
echo "## 当前版本" >> "$INDEX_FILE"
echo "" >> "$INDEX_FILE"

# 查找当前版本
CURRENT_VERSION=$(ls Reports/project_report_*.md | sort -V | tail -1)
if [ -n "$CURRENT_VERSION" ]; then
    VERSION=$(basename "$CURRENT_VERSION" .md | sed 's/project_report_//')
    DATE=$(grep "发布日期" "$CURRENT_VERSION" | awk '{print $3}')
    echo "- [项目报告 ${VERSION}]($(basename "$CURRENT_VERSION")) - ${DATE}" >> "$INDEX_FILE"
fi

echo "" >> "$INDEX_FILE"
echo "## 历史版本" >> "$INDEX_FILE"
echo "" >> "$INDEX_FILE"

# 查找历史版本
for VERSION_DIR in Reports/archive/v*/; do
    if [ -d "$VERSION_DIR" ]; then
        VERSION=$(basename "$VERSION_DIR")
        echo "### ${VERSION}.x" >> "$INDEX_FILE"
        echo "" >> "$INDEX_FILE"
        
        for REPORT in "$VERSION_DIR"*.md; do
            if [ -f "$REPORT" ]; then
                REPORT_NAME=$(basename "$REPORT" .md)
                DATE=$(grep "发布日期" "$REPORT" | awk '{print $3}')
                DESC=$(grep "修订内容" "$REPORT" | head -1 | awk -F'|' '{print $4}' | xargs)
                echo "- [${REPORT_NAME}](${REPORT}) - ${DATE}" >> "$INDEX_FILE"
                echo "  - ${DESC}" >> "$INDEX_FILE"
            fi
        done
        echo "" >> "$INDEX_FILE"
    fi
done

echo "Report index generated: $INDEX_FILE"
```

---

## 7. 最佳实践

### 7.1 文档编写最佳实践

1. **先规划后编写**：明确文档结构和内容
2. **持续更新**：及时更新文档内容
3. **版本控制**：每次更新都要更新版本号
4. **审查验证**：发布前进行充分审查

### 7.2 版本管理最佳实践

1. **语义化版本**：严格遵循语义化版本规范
2. **频繁提交**：小步快跑，频繁提交
3. **清晰日志**：编写清晰的提交信息
4. **定期归档**：定期归档历史版本

### 7.3 协作最佳实践

1. **明确分工**：明确各成员职责
2. **及时沟通**：保持良好沟通
3. **代码审查**：重视代码审查
4. **文档同步**：文档与代码同步更新

---

## 8. 常见问题

### Q1: 如何处理版本冲突？

**A**: 
1. 拉取最新版本
2. 手动解决冲突
3. 测试验证
4. 提交合并

### Q2: 如何回退到历史版本？

**A**: 
```bash
# 查看历史版本
git log --oneline Reports/project_report_*.md

# 回退到指定版本
git checkout <commit-hash> -- Reports/project_report_v1.0.0.md
```

### Q3: 如何管理多个并行版本？

**A**: 
使用分支管理不同版本：
```bash
# 创建版本分支
git checkout -b version/v1.0
git checkout -b version/v2.0

# 在各自分支上维护
```

---

## 9. 附录

### 9.1 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| v1.0.0 | 2026-03-05 | 初始版本 |

### 9.2 参考文档

- [Semantic Versioning](https://semver.org/)
- [Git Flow](https://nvie.com/posts/a-successful-git-branching-model/)
- [Markdown Guide](https://www.markdownguide.org/)

---

*最后更新时间：2026-03-05*
