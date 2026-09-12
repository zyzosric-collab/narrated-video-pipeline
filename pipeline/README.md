# pipeline — 执行器

入口是 `episode.sh`：

```bash
bash episode.sh doctor                                # 环境自检（依赖 / 解释器 / TTS / 渲染工作区）
bash episode.sh init   <epDir> [aspect] [preset]      # P0 建集
bash episode.sh voice  <epDir>                        # P2 配音 + SRT（豆包 TTS）
bash episode.sh design <epDir>                        # P3 设计契约
bash episode.sh scenes <epDir> [plan|pilot|rest|all]  # P4-P6 拆镜 / 渲染 / 质检 / 拼接
bash episode.sh audio  <epDir> [bgm.mp3]              # P7 混音
bash episode.sh status <epDir>                        # 看进度（生成 status.html）
```

一条命令都跑不了时先跑 `doctor`：它逐项检查 `ffmpeg`/`ffprobe`/`jq`/`node`/`npx`、Codex 与 Claude Code CLI、Python+PyYAML、TTS 客户端与 API Key、`auto-motion` 工作区，缺哪项都给出补齐命令。

脚本按 `BASH_SOURCE` 解析自身路径，可从任意目录调用。三个可覆盖的解析链：

| 需要 | 环境变量 | 解析顺序 |
|---|---|---|
| Python 解释器 | `PIPELINE_PY` | `$PIPELINE_PY` → `./.venv/bin/python` → 系统 `python3`（需 PyYAML），都没有则明确报错退出 |
| TTS 客户端 | `TTS_CLI` | `$TTS_CLI` → `../tools/volcengine-doubao-tts/tts.py`（仓库自带） → 旧的本机路径 |
| 渲染工作区 | `AUTO_MOTION_DIR` | `$AUTO_MOTION_DIR` → `~/auto-motion` |

- 环境变量与安装：见 [`../docs/install.md`](../docs/install.md)
- 逐阶段 runbook：见 [`../docs/usage.md`](../docs/usage.md)
- 脚本职责与数据流：见 [`../docs/architecture.md`](../docs/architecture.md)
- 配音客户端：见 [`../tools/volcengine-doubao-tts/README.md`](../tools/volcengine-doubao-tts/README.md)
- `legacy/` 是已退役的 v2 执行器，仅作历史记录，不要调用
