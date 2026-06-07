# 安全约定

## 全局禁止（所有 Agent）

- 修改 `${PIPELINE_ROOT}/scripts/`、`config/`、`docs/`（流水线基础设施）
- 泄露 `config/.env`、API Key、SSH 密钥
- 删库、关服、未授权 force push

## agent-a

- exec 仅：只读诊断 + 白名单 pipeline 脚本
- 禁止 `bash -c` / `python -c` 自写脚本改文件或 status

## 运维报告脱敏

`ops/reports/` 摘要给用户时移除 token、密码、内网 IP（若敏感）。

## 破例流程

跳过流水线规则须用户在飞书明确授权 + `PIPELINE_USER_OVERRIDE=1`。
