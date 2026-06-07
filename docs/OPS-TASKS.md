# 运维任务（agent-om）

## 分工

- **agent-a**：接收用户运维请求 → `om-task-create.sh` → 读 `ops/reports/` 摘要反馈
- **agent-om**：认领执行 → `om-task-complete.sh`；代码 Bug → `report-bug.sh`

## 创建任务（agent-a）

部署前**必须让用户选服务器**：

```bash
PIPELINE_AGENT=agent-a ./scripts/deploy-servers-list.sh
# 用户选定后：
PIPELINE_AGENT=agent-a ./scripts/om-task-create.sh <project> \
  --type deploy --server prod \
  --title "部署到生产" --job-id <job-id> \
  --body "docker compose up -d，探活 /api/health"
```

| server id | 说明 |
|-----------|------|
| `local` | test-pipeline 部署机 IP（本地验证，`VERIFY_DEPLOY_HOST`） |
| `prod` | 生产 VPS（`config/.env` 中 `DEPLOY_SERVER_PROD_*`） |

## agent-om 执行

1. timer 触发 `pipeline-om-scan`
2. `om-task-claim.sh <project>`
3. 按 type 执行：deploy / diagnose / logs
4. `om-task-complete.sh <task-id> --project <project> --report "..."`
5. 发现代码缺陷：`report-bug.sh <job-id> --reason "..." --om-task <task-id>`

## 目录

```
pipeline-workspace/<project>/
  jobs/<job-id>/          # 进行中任务
  delivered/<job-id>/     # 验证交付（agent-verifier 复制）
  feedback/               # 反馈扫描（agent-feedback → agent-a）
  ops/                    # 运维（agent-a 下发 → agent-om 执行，与 delivered 平级）
    tasks/om-*.md
    reports/om-*.md
```

## 本地验证 IP

```bash
./scripts/detect-pipeline-host-ip.sh
```

agent-om 验证/探活默认使用流水线本机 IP，非用户生产机（除非 deploy 任务指定 prod）。
