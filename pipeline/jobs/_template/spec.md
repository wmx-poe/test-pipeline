# 任务规格：{{TITLE}}

## 目标

（用户希望达成什么）

## 验收标准

- [ ] 标准 1
- [ ] 标准 2

## 背景知识

（领域上下文、约束、已有系统说明）

## 用户原始输入

（文字摘要或录音转写）

## 方案对比

（2–3 种可行方案、权衡、推荐方案及理由；brainstorming 产出）

## 设计摘要

（架构、关键组件、数据流、错误处理、测试要点；brainstorming 产出）

## 工作流拆解

1. 设计（Google Stitch）→ `design/`
2. 实现（Claude Code `claude-pipeline.sh`）→ `src/`（须含 `docker-compose.yml` 与健康检查）
3. 验证 → `verify-pipeline.sh`（Docker 部署 + 探活）+ `claude-pipeline.sh verify` → `reports/verify.md`
4. 验证 FAIL → `fix_needed` → coder 读 `verify-feedback.md` 修复 → 重新验证（最多 3 轮）
5. 验证 PASS → `deploy-info.md` 含访问地址与测试账号 → 交付与反馈循环

详见 `docs/VERIFICATION.md`。

## 附件

- 录音/文件路径：`attachments/`
