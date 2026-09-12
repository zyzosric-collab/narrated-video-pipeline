# 使用（逐阶段 runbook）

所有命令都可以从任意目录执行（脚本按 `BASH_SOURCE` 解析自身路径）。下文假设执行器在 `~/nvp/pipeline`。

---

## P0 · 建一集

```bash
bash ~/nvp/pipeline/episode.sh init <epDir> [aspect] [preset]
```

- `aspect`：`16:9`（默认）/ `9:16` / `3:4`
- `preset`：13 套预设之一（`blue-professional`、`capsule`、`editorial-forest`、`cobalt`、`brisk-*`…），完整清单：
  ```bash
  ls ~/auto-motion/exampleFolder/.claude/skills/hyperframes-design/frame-presets/
  ```
- **逐集询问，不要沿用上一集。**

产出 `episode.yaml`。查看进度：

```bash
bash ~/nvp/pipeline/episode.sh status <epDir>
```

---

## P1 · 写稿（人工门）

把分段口播稿写进 `<epDir>/script/`。规则：

- 稿子**必须由人确认**后才能进入 P2。不要把新稿和它的配音一起交付评审。
- 文案避免 AI 腔（对仗收尾、空泛升华、冒号列举）；钩子用具体画面瞬间，不用问句式铺陈。
- 同主题重写时不要复用旧稿骨架。

---

## P2 · 配音 + 字幕 + 词级时间戳

```bash
bash ~/nvp/pipeline/episode.sh voice <epDir>
```

内部走 `build_narration_v2.py`：按段调用外部 TTS CLI → 拼接 `narration.mp3` → 汇总词级 JSON → 生成外挂
`subtitles.srt`。单集 13 段左右的规模约数分钟。

跳过 TTS、直接接入成品配音（例：外部生成的 `CPA.mp3`）：

- 把成品放到 `<epDir>/assets/narration.mp3`；
- 用 whisper.cpp 之类的词级对齐补出 `word-timing.json`，再跑 `make-scene-context.py` / `make-scene-timing.py`；
- 细节见 `references/external-narration-bridge.md`。

**画面不烧录字幕**——`subtitles.srt` 只用于外挂交付。

---

## P3 · 设计契约

```bash
bash ~/nvp/pipeline/episode.sh design <epDir>
```

把 `frame.md`（配色、版式、组件、字号下限）注入镜头工作区。**必须在任何镜头生成之前注入**，
否则 Codex 拆镜与 Claude Code 实现都会缺契约（历史事故来源之一）。

---

## P4-P6 · 拆镜 → 渲染 → 质检拼接

```bash
bash ~/nvp/pipeline/episode.sh scenes <epDir> plan    # 只拆镜（Codex 规划，不渲染）
bash ~/nvp/pipeline/episode.sh scenes <epDir> pilot   # 只渲染 scene-001（试点门）
bash ~/nvp/pipeline/episode.sh scenes <epDir> rest    # 其余镜头 + 质检 + 拼接
bash ~/nvp/pipeline/episode.sh scenes <epDir> all     # 全量（已完成的镜头会跳过）
```

要点：

- **并发固定 3**；单镜头有硬超时，卡住的镜头会被判失败而不是无限等。
- 先 `plan`，人工/agent 审一遍每镜头 `PROMPT.md` 与台词切片，再 `pilot`，通过后 `rest`。
- `REUSE_PLAN=1 bash ~/nvp/pipeline/run-scenes-v3.sh <epDir> all`：复用已有拆镜，跳过工作区重组与 Codex 规划（改稿后重渲时用）。
- 质检门不过会整体失败：`npm run check` 有 error、出现静帧、或时长对不上，都会拦下。
- 状态面板：
  ```bash
  python3 ~/nvp/pipeline/status-watcher.py <epDir>/run/scenes   # 写 pipeline/status.html
  ```

渲染预算是经验值：单镜头理解 ≤2min、写码 ≤8min、check+抽帧 ≤3min、总 ≤15min；典型一集 7–9 镜头。

---

## P7 · 音频层

```bash
bash ~/nvp/pipeline/episode.sh audio <epDir> [bgm.mp3]
```

- 不给 BGM 路径时，自动取 `<epDir>/assets/bgm/` 下的第一个 mp3。
- BGM 峰值音量取自 `episode.yaml: bgm_volume`，说话时 ducking 自动压低，末尾 2 秒淡出。
- SFX 按镜头切点对齐（`cut-points.py`）。
- **先出纯音频试听让用户选定 BGM，再渲染视频**——不要为了选 BGM 渲多个视频版本。

---

## P8 · 发布包（可选）

按目标平台联网核对规则后，产出 `<epDir>/publish-kit.md`：标题 / 简介 / 话题 / 封面文字。
规则速查见 `references/platform-publish-rules.md`（含各平台字数与话题数上限），**不要凭记忆写**。

---

## 常见操作速查

| 目的 | 命令 |
|---|---|
| 看某集卡在哪 | `bash ~/nvp/pipeline/episode.sh status <epDir>` |
| 只重渲一个镜头 | 删掉该镜头目录的 mp4（或整个镜头目录），再跑 `scenes <epDir> all` |
| 改稿后只重跑配音 | `bash ~/nvp/pipeline/episode.sh voice <epDir>` |
| 复用拆镜重渲全部 | `REUSE_PLAN=1 bash ~/nvp/pipeline/run-scenes-v3.sh <epDir> all` |
| 换 BGM | `bash ~/nvp/pipeline/episode.sh audio <epDir> /new/bgm.mp3` |
| 实时看渲染状态 | `python3 ~/nvp/pipeline/status-watcher.py <epDir>/run/scenes` |
