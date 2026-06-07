# 用户反馈（非 Bug）

**用户反馈** = 意见、建议、体验抱怨、变更意向、表扬等 — **不一定是缺陷**，不自动进编码流水线。

| 项目 | 用户反馈 | Bug |
|------|----------|-----|
| 脚本 | `report-feedback.sh` | `report-bug.sh` |
| 文件 | `reports/user-feedback.md` | `reports/bugs.md` |
| status | 不变 | → `fix_needed` |
| 处理 | agent-a 分拣 | agent-coder 修复 |

## agent-a 分拣规则

| 反馈类型 `--type` | 典型话术 | 动作 |
|-------------------|----------|------|
| `suggestion` | 「能不能加导出」 | 新需求？→ brainstorming / 改 spec |
| `complaint` | 「太慢了」「不好用」 | 先记录；若可复现缺陷 → 再 `report-bug` |
| `change` | 「改成蓝色」 | 改 spec 变更记录或新 job |
| `other` | 闲聊式意见 | 记录并回复用户 |

**只有确认是缺陷** 时才调用 `report-bug.sh`，不要一开始就把所有用户话都当 Bug。

## 脚本

```bash
PIPELINE_AGENT=agent-a ./scripts/agent-a-run.sh report-feedback.sh job-xxx \
  --type suggestion --reason "用户希望支持 PDF 导出" --by feishu-user
```

## 与 project/feedback/inbox 的关系

| inbox 类型 | 落盘 |
|------------|------|
| `bug_report` | `report-bug.sh` |
| `user_complaint` | `report-feedback.sh` `--type complaint` |
| `feature_request` | 新需求流程，非 report-feedback |
