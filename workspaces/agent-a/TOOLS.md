# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## What Goes Here

Things like:

- Camera names and locations
- SSH hosts and aliases
- Preferred voices for TTS
- Speaker/room names
- Device nicknames
- Anything environment-specific

## Examples

```markdown
### Cameras

- living-room → Main area, 180° wide angle
- front-door → Entrance, motion-triggered

### SSH

- home-server → 192.168.1.100, user: admin

### TTS

- Preferred voice: "Nova" (warm, slightly British)
- Default speaker: Kitchen HomePod
```

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

Add whatever helps you do your job. This is your cheat sheet.

## Brainstorming

- Skill：`skills/brainstorming/SKILL.md`
- 新需求必须先走 brainstorming，`draft` → 用户批准 → `pending`
- 任务索引：`{{PIPELINE_ROOT}}/pipeline/jobs/<job-id>/job.md`（指针）
- 任务工作区：`{{WORKSPACE_ROOT}}/<project>/jobs/<job-id>/`（spec、status 等）
- 任务模板：`{{PIPELINE_ROOT}}/pipeline/jobs/_template/spec.md`
- 创建任务：`{{PIPELINE_ROOT}}/scripts/new-job.sh "标题"`（默认 draft）
- 校验 spec：`{{PIPELINE_ROOT}}/scripts/validate-spec.sh <job-id>`
- 批准入队：`{{PIPELINE_ROOT}}/scripts/promote-job.sh <job-id>`

## Related

- [Agent workspace](/concepts/agent-workspace)
