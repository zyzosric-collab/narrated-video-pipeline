# 架构

## 数据流

```
主题
 └─ P1 script/*.md ────────────────┐        （人工确认门）
                                   ▼
              P2 build_narration_v2.py ──► narration.mp3
                     │                        ├─ word-timing.json（词级）
                     │                        └─ subtitles.srt（外挂，不入画面）
                     ▼
              P3 inject-design.sh ──► run/exampleFolder/**/frame.md（设计契约）
                     ▼
              P4 run-scenes-v3.sh ──► Codex 只规划
                     │                  ├─ scenes/scene-XXX/run-claude-ai.sh
                     │                  └─ scenes/scene-XXX/PROMPT.md
                     ▼
              P5 并发 3（Claude Code + HyperFrames）
                     │                  └─ scenes/scene-XXX/scene-XXX.mp4
                     ▼
              P6 质检门 + 拼接 ──────► run/final.mp4
                     │                  ├─ npm run check（全文过目）
                     │                  ├─ PSNR 动帧扫描（抓静帧）
                     │                  └─ 时长 A/V 对账
                     ▼
              P7 build-audio.sh ─────► 成片（BGM ducking + 切点 SFX）
                     ▼
              P8 publish-kit.md（可选）
```

## 每集目录契约

```
<epDir>/
├── episode.yaml            # 配置真源（P0 生成，之后是唯一权威）
├── script/                 # P1 口播稿分段
├── assets/
│   ├── narration.mp3       # P2
│   ├── word-timing.json    # P2 词级时间戳
│   ├── subtitles.srt       # P2 外挂字幕
│   ├── bgm/                # 选定的 BGM（先试听后落盘）
│   └── sfx/                # 镜头切点音效（可选）
├── run/
│   ├── exampleFolder/      # 渲染工作区（从 auto-motion 模板整份拷贝）
│   │   └── **/frame.md     # P3 注入的设计契约
│   ├── scenes/scene-XXX/   # 每镜头一份工作区（代码 + mp4 + 日志）
│   ├── scene-context.md    # 每镜头台词切片（词级时间 → 镜头）
│   ├── scene-timing.json   # 每镜头起止时间
│   └── final.mp4           # P6 拼接结果
└── frames/                 # 抽帧质检输出
```

## `episode.yaml` 字段

| 字段 | 含义 |
|---|---|
| `episode` | 集标识（用于日志与发布包） |
| `aspect` / `width` / `height` / `fps` | 画幅与帧率（默认 `16:9` / 1920×1080 / 30） |
| `preset` | 画面预设名（13 选 1，逐集确认） |
| `preset_dir` | 预设目录的绝对路径（init 时按 `AUTO_MOTION_DIR` 派生） |
| `bgm_volume` | BGM 峰值音量；说话时由 ducking 自动压低 |
| `bgm_mood` | 写作阶段填的 BGM 气质描述（如 `tech, inspiring, minimal`） |
| `speaker` / `speech_rate` | TTS 音色与语速 |
| `phases.*` | 各阶段完成标记（`script` / `voice` / `design` / `scenes` / `audio` / `delivered`） |

`phases.*` 让 `episode.sh status` 一眼看出卡在哪一步；`rest` / `all` 模式据此跳过已完成镜头。

## 分工与职责边界

| 角色 | 负责 | 不负责 |
|---|---|---|
| 外层 agent（Hermes） | 编排、门禁、质检裁决、验收、发布文案 | 不写镜头内代码 |
| Codex | P4 拆镜规划：把口播稿切成镜头，产出每镜头的 `PROMPT.md` | **不渲染、不执行画面代码** |
| Claude Code | P5 单个镜头的 HTML/JS 画面实现与渲染落地 | 不做整体编排与验收 |
| 人 | 口播稿确认、预设选择、BGM 选定、成片验收 | — |

拆镜与实现分离，是为了让「镜头规划」可以在不消耗渲染时间的前提下反复迭代；一次只给渲染器一个镜头，也让失败面收敛在单镜头内。

## 关键机制

| 机制 | 位置 | 作用 |
|---|---|---|
| `SCENE_ID` 契约护栏 | `run-scenes-v3.sh` P5a | 每个镜头脚本必须带 `SCENE_ID`，缺失/错位会被回写修正 |
| 契约包（一次 Read 取代多次翻文件） | P5a | 把公共契约打包注入，降低每镜头重复读文件的开销 |
| 效率门 + 质量门 | P5b | 渲染前静态检查（预算、必须项），避免跑到一半才发现缺契约 |
| 孤儿渲染补渲 | P5d | 上次中断留下的未完成镜头会被补跑 |
| 质检门 | P5e | `npm run check` + PSNR 动帧扫描 + 时长对账，任一不过即整体失败 |
| 词级时间切片 | `make-scene-context.py` | 把词级时间戳切到每个镜头的台词上（配音与画面同步的基础） |
| 状态面板 | `status-watcher.py` | 每 10 秒生成 `status.html`，逐镜头显示阶段/日志/耗时 |
