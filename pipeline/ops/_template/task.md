---
id: om-YYYYMMDD-HHMMSS
project: PROJECT_SLUG
type: deploy
status: pending
jobId: job-YYYYMMDD-HHMMSS
serverId: prod
serverHost: "<DEPLOY_SERVER_PROD_HOST>"
serverName: "生产 VPS"
sshTarget: "<user>@<host>"
deployRoot: /opt/pipeline-apps
priority: P2
createdAt: ISO8601
createdBy: agent-a
title: "任务标题"
---

# 任务标题

## 背景

（为何需要此次运维）

## 目标服务器

（deploy 类型由 om-task-create --server 自动填写；生产 IP 见 config/.env DEPLOY_SERVER_PROD_*）

## 步骤

1. ...

## 验收

- reports 中含 ...
- 关键命令退出码

## 约束

- compose 项目名、端口、路径等
