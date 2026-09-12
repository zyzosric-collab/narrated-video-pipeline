# 排障

按症状查表；每条都给出「原因 → 处置」。原则：**先看真实产物，再改配置**（`episode.sh doctor` 能一次列出缺什么）。

## 安装与环境

| 症状 | 原因 | 处置 |
|---|---|---|
| `找不到可用 Python 解释器` / `解释器不可执行` | 没有 `.venv`，系统 `python3` 也没装 PyYAML；或 `PIPELINE_PY` 指错 | `cd <repo>/pipeline && python3 -m venv .venv && .venv/bin/pip install pyyaml`；或 `export PIPELINE_PY=/path/to/python` |
| `ep-env.py` 报 YAML 解析错误 | 解释器里缺 PyYAML | `.venv/bin/pip install pyyaml`（脚本会先做这个判断，缺了会直接报错而不是继续跑） |
| 脚本找不到 `auto-motion/exampleFolder` | 渲染工作区没克隆或路径不同 | `git clone https://github.com/zyzosric-collab/auto-motion ~/auto-motion`，或 `export AUTO_MOTION_DIR=/path/to/auto-motion` |
| `bash: .venv/bin/python: ...` | 老脚本用相对路径找解释器（`legacy/`） | 用 `pipeline/` 下的当前脚本；legacy 仅作历史记录 |
| 想一次看清环境 | — | `bash pipeline/episode.sh doctor`：逐项检查依赖 / 解释器 / TTS / 密钥 / 渲染工作区，并给出补齐命令 |

## 配音（P2）

| 症状 | 原因 | 处置 |
|---|---|---|
| `找不到 TTS CLI` / 路径不存在 | 既没设 `TTS_CLI`，仓库内 `tools/` 也不在 | 用仓库自带实现（默认），或 `export TTS_CLI=/path/to/your_tts.py` |
| `缺少 VOLCENGINE_TTS_API_KEY` | 没配密钥 | `cd tools/volcengine-doubao-tts && cp .env.example .env.local`，填 Key（见目录内 README） |
| 时间戳只有段落级、逐镜头同步漂移 | TTS 没输出**词级**时间戳 | 用支持 `--subtitle-json` 的实现（仓库自带豆包即支持），或走 `external-narration-bridge.md` 的 whisper.cpp 对齐 |
| 试听时音色不对 | 用了平台内置 TTS 凑数 | 试听/预览必须用流水线官方 TTS 通道，音色取自 `episode.yaml: speaker` |
| 稿子改了但配音没变 | 增量逻辑复用了旧分段 | 删掉对应段落的 mp3 再跑；或整体重跑 `voice` |

## 拆镜（P4）

| 症状 | 原因 | 处置 |
|---|---|---|
| 镜头没台词 / 台词串场 | `frame.md` 未注入，或词级切片缺数据 | 确认先跑 `design`，再 `scenes <epDir> plan`；检查 `run/scene-context.md` |
| `SCENE_ID` 缺失导致护栏标红 | 镜头脚本模板不对 | 由 P5a 护栏自动回写；若仍失败，检查该镜头脚本被手改过 |
| Codex 直接开始渲染/调用了渲染命令 | PROMPT 缺「只规划不渲染」约束 | 重新 `plan`；PROMPT 里的模式段由执行器统一注入，不要手工删 |
| 拆镜结果与上一集雷同 | 复用了旧工作区 | `REUSE_PLAN=1` 只在“有意复用”时用；否则让执行器重组工作区 |

## 渲染（P5）

| 症状 | 原因 | 处置 |
|---|---|---|
| 单镜头超时/无日志增长 | 渲染器卡住或驱动脚本出错 | 看 `scenes/scene-XXX/` 下日志尾部；不要盲目重跑全量 |
| 进度长时间停在某镜头 | 并发被占满（固定 3） | 属正常；确认其他镜头在推进即可 |
| 断点续跑想跳过已完成镜头 | — | 直接再跑 `scenes <epDir> all`，已完成的会跳过；未完成的由 P5d 补渲 |

## 质检（P6）—— 最容易被漏掉的一类

| 症状 | 原因 | 处置 |
|---|---|---|
| 成片某段“画面不动” | 动画根本没在跑（例如自制 gsap shim、非确定性驱动、未注册的动画库） | **必做 PSNR 动帧扫描**：帧帧全同（帧差 `inf`）即静帧。改用真动画库 + 由时间轴 scrub 确定性驱动渲染帧 |
| `npm run check` 有 error 却渲染成功 | 只看了日志尾部 | 质检要求**全文过目** `npm run check` 输出；只看 `tail` 不算通过 |
| 拼接后总时长与配音对不上 | 镜头时长偏差累积 | 看质检门的「期望 vs 实际」对账；差值 > 容差就重渲偏差镜头 |
| 截图/抽帧看不出问题 | 固定帧抽检的盲点 | 固定帧 + 动帧扫描两者都要；元素重叠类误报以成片抽帧人工裁决为准 |
| 面板显示有镜头重叠 | DOM 审计脚本的 seek 盲点 | 以成片抽帧为准，不直接改画面 |

## 音频（P7）

| 症状 | 原因 | 处置 |
|---|---|---|
| `FATAL: 未提供 BGM` | `assets/bgm/` 为空且未传参 | 传 BGM 路径或把文件放进 `assets/bgm/` |
| 人声被 BGM 盖住 | `bgm_volume` 过高 | 调低 `episode.yaml: bgm_volume` 后重跑 P7（不必重渲画面） |
| SFX 与切点差半拍 | 切点来自旧时长 | 重跑 `cut-points.py` 后重混，不要手工挪音效 |

## 画面可读性（验收常见退回项）

| 症状 | 处置 |
|---|---|
| 眉题/小标签太小看不清 | 字号提到 ≥ 1.1cqw |
| 连接线压卡片、盖边框、伸进卡片 | 按旋转角先算端点，让端点停在卡片边缘外侧 ≥ 8px |
| 出现字幕条 / 逐字高亮 / 口播稿文字 | 违反硬规则：画面不放烧录字幕，改为纯图形叙事 + 外挂 `.srt` |

## 额度与外部 CLI

| 症状 | 原因 | 处置 |
|---|---|---|
| 批量任务大面积失败 | 外部 CLI 额度/限流 | **先查根因，不要盲目重试**；必要时降并发或分批 |
| 报 `unknown provider` / 400 | 路由配置坏了 | 停下来等用户处理，不要自行改全局配置或强指模型 |
| 报 503 / `auth_unavailable` | 临时故障 | 退避重试即可，不是配置问题 |
