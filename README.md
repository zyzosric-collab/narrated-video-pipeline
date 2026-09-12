# narrated-video-pipeline · 中文口播视频流水线

> 给一个主题，产出一条配好音、有画面、可直接发布的中文口播视频。

主题 → 研究/写稿 → 豆包 TTS（词级时间戳）→ 逐镜头画面 → 质检拼接 → BGM ducking 混音 → 发布文案包。

本项目由两部分组成：

- **技能包**：`SKILL.md` + `references/`，供 Hermes Agent / Claude Code / Codex 等 agent 加载，规定工作流的阶段、硬规则与验收门。
- **执行器**：`pipeline/` 下的 bash / python 脚本，可以脱离 agent 独立运行（拆镜、配音、渲染调度、质检、混音、状态面板）。

---

## 流水线长什么样

| Phase | 名称 | 主要产物 | 由谁执行 |
|---|---|---|---|
| P0 | init | `episode.yaml`（画幅 / fps / 预设 / BGM 音量） | `episode.sh init` |
| P1 | 写稿 | `script/*.md` 分段口播稿（**人工确认后才能进入 P2**） | 人 + 写作类技能 |
| P2 | 配音 | `narration.mp3`、词级时间戳 JSON、`transcription.srt` | `build_narration_v2.py` → 豆包 TTS（仓库内） |
| P3 | 设计契约 | 工作区内的 `frame.md`（配色 / 版式 / 组件规则） | `inject-design.sh` |
| P4 | 拆镜 | 每镜头一份 `run-claude-ai.sh` + `PROMPT.md` | Codex（**只规划，不渲染**） |
| P5 | 逐镜头渲染 | `scenes/scene-XXX/scene-XXX.mp4` | Claude Code + HyperFrames（并发 3） |
| P6 | 质检 + 拼接 | `run/final.mp4`（`npm run check` 全绿 + PSNR 动帧扫描） | `run-scenes-v3.sh` |
| P7 | 音频层 | 成片（BGM ducking + 镜头切点 SFX） | `build-audio.sh` |
| P8 | 发布包（可选） | `publish-kit.md`（平台标题 / 简介 / 话题） | agent 按各平台规则联网核对后撰写 |

一句话总结分工：**Codex 只负责拆镜规划，Claude Code 只负责“一个镜头一份代码”的画面实现，编排、质检、验收由外层 agent（Hermes）掌握。**

---

## 目录结构

```
.
├── SKILL.md                      # agent 技能主文件：硬规则 + 阶段 runbook + 验收门
├── references/                   # 5 份深化文档（见下表）
├── pipeline/                     # 执行器（bash + python，无第三方服务依赖）
│   ├── episode.sh                # 入口：init | voice | design | scenes | audio | status
│   ├── run-scenes-v3.sh          # P4+P5+P6：拆镜 → 契约护栏 → 并发渲染 → 质检门 → 拼接
│   ├── inject-design.sh          # P3：把设计契约注入镜头工作区
│   ├── build_narration_v2.py     # P2：分段 TTS + 拼接 + 词级 SRT
│   ├── build-audio.sh            # P7：BGM ducking + 切点 SFX 混音
│   ├── make-scene-context.py     # 词级时间戳 → 每镜头台词切片
│   ├── make-scene-timing.py      # 每镜头起止时间 → scene-timing.json
│   ├── cut-points.py             # 镜头切点（供 SFX 对齐）
│   ├── gen-overlay.py            # 画面叠层素材
│   ├── parse-script.py           # 口播稿 → 分段
│   ├── ep-env.py                 # episode.yaml → shell 变量
│   ├── status-watcher.py         # 生成 status.html 实时状态面板（每 10s 刷新）
│   ├── setup-shared-deps.py      # 共享依赖软链（auto-motion 工作区）
│   ├── legacy/                   # 已退役的 v2 执行器，仅作历史记录
│   └── ...
├── tools/                        # 外部服务客户端（本仓库自带）
│   └── volcengine-doubao-tts/    # 豆包 seed-tts-2.0 配音实现（P2 默认走这里）
└── docs/                         # 人类可读文档（安装 / 使用 / 架构 / 排障）
    └── notes/                    # 早期设计记录与性能审计
```

`references/` 内容：

| 文件 | 内容 |
|---|---|
| `pipeline-internals.md` | 各脚本的输入输出、命令签名、已知坑 |
| `scene-quality-gates.md` | 镜头质量门与验收清单（含 PSNR 静帧检测） |
| `audio-asset-routing.md` | BGM / SFX 素材检索与授权记录规范 |
| `external-narration-bridge.md` | 外部配音（成品 `narration.mp3`）接入与词级对齐 |
| `platform-publish-rules.md` | 各平台发布规则（标题字数 / 话题数 / 简介长度） |

---

## 快速开始

```bash
# 1) 取代码 + 建虚拟环境（只依赖 PyYAML）
git clone https://github.com/zyzosric-collab/narrated-video-pipeline ~/nvp
cd ~/nvp/pipeline && python3 -m venv .venv && .venv/bin/pip install pyyaml

# 2) 配好自己的配音 API Key（豆包 / 火山引擎，就三步）
cd ~/nvp/tools/volcengine-doubao-tts
cp .env.example .env.local && chmod 600 .env.local && $EDITOR .env.local   # 填 VOLCENGINE_TTS_API_KEY
python3 tts.py --text '配置检查。' --dry-run                              # 不调用付费接口

# 3) 环境自检（依赖、解释器、TTS、渲染工作区一次过）
bash ~/nvp/pipeline/episode.sh doctor

# 4) 建一集（Phase 0）
bash ~/nvp/pipeline/episode.sh init ~/episodes/ep01 16:9 blue-professional
bash ~/nvp/pipeline/episode.sh status ~/episodes/ep01

# 5) 写稿 → 人确认 → 配音（Phase 1-2）
bash ~/nvp/pipeline/episode.sh voice ~/episodes/ep01

# 6) 设计契约 → 拆镜 → 试点一镜 → 全量渲染（Phase 3-6）
bash ~/nvp/pipeline/episode.sh design ~/episodes/ep01
bash ~/nvp/pipeline/episode.sh scenes ~/episodes/ep01 plan     # 只拆镜
bash ~/nvp/pipeline/episode.sh scenes ~/episodes/ep01 pilot    # 只渲 scene-001
bash ~/nvp/pipeline/episode.sh scenes ~/episodes/ep01 rest     # 其余镜头 + 质检 + 拼接
bash ~/nvp/pipeline/episode.sh scenes ~/episodes/ep01 all      # 全量（已渲的会跳过）

# 7) 音频层（Phase 7）
bash ~/nvp/pipeline/episode.sh audio ~/episodes/ep01 /path/to/bgm.mp3
```

执行器按 `BASH_SOURCE` 解析自身路径，**可以从任意工作目录调用**；`doctor` 会把缺什么、怎么补逐条列出来。

完整的环境准备见 [`docs/install.md`](docs/install.md)，逐阶段 runbook 见 [`docs/usage.md`](docs/usage.md)。

---

## 依赖

| 组件 | 用途 | 备注 |
|---|---|---|
| `ffmpeg` / `ffprobe` | 拼接、混音、规范化、抽帧质检 | 需较新版本（实测 9.x） |
| `jq` | 脚本内 JSON 处理 | |
| Node.js + `npx hyperframes` | 镜头渲染引擎 | 随 `auto-motion` 工作区提供 |
| Python 3.11+ / PyYAML | 执行器与配置解析 | 建在 `pipeline/.venv` |
| Codex CLI | P4 拆镜（只规划） | 自备账号与额度；建议在隔离目录内运行 |
| Claude Code CLI | P5 逐镜头实现 | 自备账号与额度 |
| **豆包 TTS（配音）** | P2 配音 | **已随仓库提供**：`tools/volcengine-doubao-tts/`；只需自备火山引擎 API Key |
| `auto-motion` 工作区 | 渲染引擎 + 13 套预设 + 技能 | 另仓：`github.com/zyzosric-collab/auto-motion`，克隆到 `~/auto-motion` |

配音默认走仓库内的豆包实现（火山引擎 `seed-tts-2.0`，音色取 `episode.yaml: speaker`），只要求一个环境变量 `VOLCENGINE_TTS_API_KEY`。解析顺序是 `$TTS_CLI` → 仓库内 `tools/volcengine-doubao-tts/tts.py` → 本机旧路径；**什么都不设也能用**。

要换成别的实现，写一个满足下面契约的脚本并把 `TTS_CLI` 指过去即可（也可以完全跳过 P2，用现成配音走
[`references/external-narration-bridge.md`](references/external-narration-bridge.md) 的词级对齐流程）：

```bash
python3 "$TTS_CLI" --text <文本> --speaker <音色ID> --speech-rate <整数> \
  --style <风格> --instruction <发音提示> --output <mp3> --subtitle-json <词级JSON>
```

---

## 硬规则（不可协商）

1. **画面不烧录字幕**：不留字幕条、不做卡拉OK逐字高亮、不把口播稿文字铺到画面上。语言信息由配音承载；需要字幕就外挂 `.srt`。
2. **口播稿必须先经人工确认**，才允许跑 TTS。不要把「写完的稿 + 生成好的配音」捆绑成一次交付去审。
3. **每集画幅与预设必须逐集询问**，不得沿用上一集。默认 16:9（1920×1080 / 30fps）。
4. **BGM 先出纯音频试听**，用户选定之后再渲染视频；不要为了选 BGM 渲染多个视频版本。
5. **镜头渲染并发固定 3**；批量前先跑 `pilot` 试点一镜，通过后再全量。
6. **镜头质检必须包含两件事**：`npm run check` 的**全文输出**逐条过目 + **PSNR 动帧扫描**（抓“动画没动”的静帧）。只看结尾 `tail` 不算通过。
7. **画面元素可读性**：眉题/小标签字号 ≥ 1.1cqw；连接线端点停在卡片边缘外侧 ≥ 8px，禁止压卡或伸入卡片。
8. 外部依赖（Claude / Codex）**不改其全局配置、不在命令行强制指定模型**，使用当前配置。

---

## 已验证范围

- 已用本流水线产出 5 集口播视频（每集 7–9 个镜头，30–115 秒）。
- 最近一集实测：期望时长 111.5s vs 实际 111.6s（A/V 等长），质检门 + 固定帧抽检通过。
- 支持画幅：16:9 / 9:16 / 3:4，支持 13 套画面预设（`auto-motion` 的 `hyperframes-design/frame-presets/`）。
- 已在 macOS（Apple Silicon）上运行；脚本是 bash + POSIX 工具，Linux 上大概率可直接用，但未做交叉验证。

## 边界与免责

- 本仓库**不含**任何 API 凭据、模型权重或第三方素材；豆包 TTS 客户端源码在 `tools/`（纯标准库），服务本身由火山引擎提供，Codex / Claude Code 为外部依赖，各自遵守其服务条款。`.env.local` 必须留在本机（已在 `.gitignore` 内）。
- `docs/notes/` 与 `pipeline/legacy/` 是历史记录，不对应当前接口，请勿直接调用。
- 音色与素材授权由使用者自行负责（素材来源 / 作者 / 许可证 / 路径 / 校验值的记录规范见 `references/audio-asset-routing.md`）。

## License

MIT，见 [LICENSE](LICENSE)。
