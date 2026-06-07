# 验证与部署约定

本流水线 **禁止仅做静态代码审查**。验证阶段必须包含运行时检查、容器化部署与失败回流。

## 验证阶段职责（agent-verifier）

1. **运行时验证（必须先执行）**

```bash
{{PIPELINE_ROOT}}/scripts/verify-pipeline.sh <job-id>
```

产出：

| 文件 | 内容 |
|------|------|
| `reports/verify-runtime.log` | 构建/部署原始日志 |
| `reports/verify-runtime.md` | 运行时摘要（含 **运行时结论: PASS/FAIL**） |
| `reports/deploy-info.md` | 访问地址、端口、测试账号说明（部署成功时） |

`verify-pipeline.sh` 会：

- 检查 Docker 可用性（`install-ubuntu.sh` 已安装）
- `docker compose up -d --build` 启动项目（compose 项目名 `pipeline-<job-id>`，避免冲突）
- 探活 `/api/health`、Web 首页等
- 尝试容器内 `pytest` / `npm test`（若存在）
- 无 compose 时回退本地 `npm run build` / `python compileall`

2. **规格与质量审查（Claude Code）**

```bash
{{PIPELINE_ROOT}}/scripts/claude-pipeline.sh verify "<workspace>/src" "<prompt>"
```

Prompt 必须要求阅读 `verify-runtime.md`；**综合运行时 + 静态审查** 后写 `reports/verify.md`，文末含 `结论：PASS` 或 `结论：FAIL`。

**状态自动更新**：`scripts/complete-verify.sh` 在验证结束后读取报告并更新 `status.json`：

| 调用时机 | 模式 | 行为 |
|----------|------|------|
| `verify-pipeline.sh` 失败退出前 | `--runtime-only` | 运行时 FAIL → `fix_needed` + `verify-feedback.md` |
| `claude-pipeline.sh verify` 结束时 | `--full` | 运行时+综合均 PASS → `verified`；任一 FAIL → `fix_needed` |
| 运行时 FAIL 时 | （跳过 Claude） | 仅 `--runtime-only`，直接回流 coder |

3. **验证通过（PASS）**

- `complete-verify.sh --full` 已将 `status` → `verified`
- 确认 `deploy-info.md` 含可访问 URL 与测试账号
- 复制到 `{{WORKSPACE_ROOT}}/<project>/delivered/<job-id>/`

4. **验证失败（FAIL）**

- `complete-verify.sh` 已写 `reports/verify-feedback.md` 并递增 `verifyRound`
- 默认 `maxVerifyRounds=10`：未超限时 → **`fix_needed`**（自动继续修复）
- **超过 10 轮仍 FAIL** → **`verify_paused`** + `reports/verify-user-report.md`（关键报错），**停止自动轮训**，飞书询问用户
- 用户同意继续 → `continue-verify.sh <job-id> --rounds 10`（再自动 10 轮）
- 用户放弃 → agent-a 将 status 设为 `verify_failed`

## 用户 Bug 与 job 策略

| 类型 | 做法 |
|------|------|
| **新需求** | agent-a 确认后 `new-job.sh` → draft → pending |
| **Bug / 改已有任务** | **同一 job**：`reopen-job.sh` → `fix_needed` + `reports/user-feedback.md` |
| **未完成 spec** | 在原 job 更新 `spec.md`，不开新 job |

```bash
{{PIPELINE_ROOT}}/scripts/reopen-job.sh <job-id> --reason "Bug 描述" --by feishu-user
```

`verify-feedback.md` 模板：

```markdown
# 验证修复清单 (round N)

## 阻塞项
1. ...

## 运行时失败
（来自 verify-runtime.md）

## 静态审查失败
（来自 verify.md）

## 建议修复顺序
1. ...
```

## 修复阶段（agent-coder）

当 `status === fix_needed`（验证 FAIL 或用户 Bug）：

1. 读 `reports/verify-feedback.md`、`reports/user-feedback.md`（若有）、`verify.md`、`verify-runtime.md`
2. `status` → `implementing`
3. 用 `claude-pipeline.sh resume` 或 `implement` 修复 **全部阻塞项**
4. 修复后重新运行测试；更新 `reports/implement-summary.md`（注明本轮 fix 摘要）
5. `status` → `impl_done`（等待 verifier 重新验证）

## 状态机补充

```
impl_done → verifying → (PASS) verified → delivered
                    ↘ (FAIL, round≤10) fix_needed → implementing → impl_done → verifying …
                    ↘ (FAIL, round>10) verify_paused → 用户决定 → continue-verify / verify_failed
```

| status | 含义 | 触发 Agent |
|--------|------|------------|
| `fix_needed` | 验证失败或用户 Bug，等待 coder 修复 | agent-coder |
| `verify_paused` | 已达 10 轮仍未通过，待用户决定是否继续 | agent-a 飞书通知 |
| `verify_failed` | 用户放弃或人工终止 | 人工 |

`status.json` 字段：

```json
{
  "verifyRound": 0,
  "maxVerifyRounds": 10
}
```

## 实现侧要求（agent-coder）

交付 `src/` 时必须（若项目可容器化）：

- 提供可工作的 `docker-compose.yml`（或 `compose.yaml`）
- 提供 `/api/health` 或等效健康检查端点
- 在 `README.md` 写明默认测试账号与访问方式

## 环境

### Docker 环境（必需，从零安装）

验证阶段依赖 Docker 做 **构建 + 容器化部署 + 健康探活**。新机或缺失环境时，按顺序执行：

#### 1. 一键安装（推荐）

```bash
cd {{PIPELINE_ROOT}}
./scripts/install-docker.sh
```

脚本会：

- 安装 `docker.io`（引擎）、`docker-compose-v2`（`docker compose` 子命令）、`uidmap`
- 配置 `/etc/docker/daemon.json` 镜像加速（国内网络）
- `systemctl enable --now docker`
- 将当前用户加入 `docker` 组

**无 sudo 密码时（桌面 Ubuntu）**：脚本自动改用 `pkexec`，会弹出系统授权框。

**已 root 安装时**：`sudo ./scripts/install-docker.sh` 或直接以 root 运行。

#### 2. 激活用户组（安装后必做）

安装脚本把用户加入 `docker` 组后，**当前终端不会立即生效**，任选其一：

```bash
# 方式 A：新开终端 / 重新登录 SSH
exit && ssh ...

# 方式 B：当前 shell 立即生效
newgrp docker
```

#### 3. 验收

```bash
docker --version
docker compose version
docker info                    # 不应报 permission denied
docker run --rm hello-world    # 应输出 Hello from Docker!

# 流水线运行时验证
{{PIPELINE_ROOT}}/scripts/verify-pipeline.sh <job-id>
```

#### 4. 常见问题

| 现象 | 处理 |
|------|------|
| `docker: 找不到命令` | 运行 `./scripts/install-docker.sh` |
| `permission denied` / `Cannot connect to the Docker daemon` | 执行 `newgrp docker` 或重新登录；确认 `groups` 含 `docker` |
| `docker compose` 不存在 | `sudo apt install docker-compose-v2` |
| 服务未运行 | `sudo systemctl start docker && sudo systemctl status docker` |
| 验证脚本仍报 Docker 不可用 | 确认未在 `sudo` 与无权限用户之间混用；同一终端跑 `docker info` 成功后再跑 verify |

#### 5. 与 verify-pipeline 的关系

| 检查项 | 无 Docker 时 |
|--------|----------------|
| `verify-pipeline.sh` | 立即 FAIL，写 `verify-runtime.md` 注明 Docker 不可用 |
| `claude-pipeline.sh verify` | 仍会跑，但缺少运行时结论，整体易 FAIL |
| 交付 `deploy-info.md` | 无法生成访问地址 |

**因此 Docker 属于流水线基础依赖**，与 Node/OpenClaw 同级，应在首次部署时安装（`install-ubuntu.sh` 会调用 `install-docker.sh`）。

#### 6. 可选配置

- `VERIFY_DEPLOY_HOST`：探活与 deploy-info 中的主机名（默认 `localhost`；远程 VPS 可设为公网 IP 或域名）

#### 7. 镜像加速（国内网络）

安装脚本默认写入 `/etc/docker/daemon.json`（也可单独运行 `./scripts/configure-docker-mirrors.sh` 强制更新）：

```json
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me",
    "https://docker.m.daocloud.io"
  ]
}
```

修改后执行：`sudo systemctl restart docker`。验收：`docker info | grep -A3 'Registry Mirrors'`。

#### 8. 项目 Dockerfile 内国内源（构建加速）

agent-coder 交付容器化项目时，**应在 Dockerfile 内**配置：

| 类型 | 推荐源 |
|------|--------|
| apt (Debian) | `mirrors.aliyun.com` 替换 `deb.debian.org` |
| pip | `-i https://pypi.tuna.tsinghua.edu.cn/simple` |
| npm | `registry=https://registry.npmmirror.com` |

示例见各 job `src/api/Dockerfile`、`src/web/Dockerfile`。

