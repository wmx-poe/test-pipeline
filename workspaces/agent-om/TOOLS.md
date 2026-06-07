# Agent OM 工具白名单

## 路径

- 编排根：`{{PIPELINE_ROOT}}`
- 运维任务：`{{WORKSPACE_ROOT}}/<project>/ops/tasks/`
- 运维报告：`{{WORKSPACE_ROOT}}/<project>/ops/reports/`

## 脚本

```bash
# 认领任务
PIPELINE_AGENT=agent-om {{PIPELINE_ROOT}}/scripts/om-task-claim.sh <project>

# 完成并写报告
PIPELINE_AGENT=agent-om {{PIPELINE_ROOT}}/scripts/om-task-complete.sh <task-id> \
  --project <project> --report "部署成功，/api/health 200"

# 运维 Bug
PIPELINE_AGENT=agent-om {{PIPELINE_ROOT}}/scripts/report-bug.sh <job-id> \
  --reason "..." --om-task <task-id>

# 本机验证 IP
{{PIPELINE_ROOT}}/scripts/detect-pipeline-host-ip.sh
```

## 生产部署

生产服务器从 `config/.env` 读取，task 内 `server: prod` 时使用 `DEPLOY_SERVER_PROD_HOST`。
