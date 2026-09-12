# 安装

## 1. 系统依赖

macOS（Homebrew）：

```bash
brew install ffmpeg jq python@3.12 node
```

| 依赖 | 最低用途 | 自检 |
|---|---|---|
| ffmpeg / ffprobe | 拼接、混音、抽帧 | `ffmpeg -version` |
| jq | 脚本内 JSON | `jq --version` |
| Node.js / npx | HyperFrames 渲染 | `node -v` |
| Python 3.11+ | 执行器 | `python3 -V` |
| Codex CLI | P4 拆镜 | `codex --version` |
| Claude Code CLI | P5 逐镜头实现 | `claude --version` |

## 2. 取代码 + 建虚拟环境

```bash
git clone <this-repo> ~/nvp
cd ~/nvp/pipeline
python3 -m venv .venv
.venv/bin/pip install pyyaml
```

> `.venv` 必须建在 `pipeline/` 目录内（默认解释器路径是 `$PIPELINE/.venv/bin/python`）。

## 3. 渲染工作区（auto-motion）

P4/P5 需要一个 `auto-motion` 工作区：里面包含 `.claude/skills/`（含 `hyperframes*` 技能）与
`exampleFolder/`（每集的工作区模板，含 `run-claude-ai.sh`、预设目录等），执行器会把它整份拷进每集的 `run/` 下。

```bash
git clone <auto-motion-repo> ~/auto-motion
ls ~/auto-motion/exampleFolder/.claude/skills/     # 应能看到 hyperframes* / general-video 等
```

若工作区不在 `~/auto-motion`，用 `AUTO_MOTION_DIR` 指过去（见下）。

## 4. 外部 TTS CLI

配音阶段调用一个外部命令，**本仓库不包含它**。默认路径：

```
$HOME/Documents/Codex/shared/volcengine-doubao-tts/tts.py
```

调用契约（`build_narration_v2.py` 与 `episode.sh voice` 均按此调用）：

```bash
python3 "$TTS_CLI" --text <文本> \
                   --speaker <音色ID> \        # episode.yaml: speaker
                   --speech-rate <整数> \      # episode.yaml: speech_rate
                   --style <风格> \
                   --instruction <发音提示> \
                   --output <mp3> \
                   --subtitle-json <词级JSON>  # 必须输出词级时间戳
```

**关键要求**：`--subtitle-json` 必须给出**词级**时间戳，否则 P5 的逐镜头时间切片（`make-scene-context.py`）无法做，只能退化成按段落估算。

想换成别的声音实现：写一个满足上述接口的脚本，或完全跳过 P2、用现成成品配音走
`references/external-narration-bridge.md` 里的 whisper.cpp 词级对齐路线。

## 5. 环境变量

全部可选，脚本内已有默认值（`pipeline/*.sh` 顶部）：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `PIPELINE_DIR` | 脚本所在目录 | 执行器根目录 |
| `PIPELINE_PY` | `$PIPELINE/.venv/bin/python` | 执行器用的 Python |
| `AUTO_MOTION_DIR` | `$HOME/auto-motion` | 渲染工作区 |
| `TTS_CLI` | `$HOME/Documents/Codex/shared/volcengine-doubao-tts/tts.py` | 外部 TTS 脚本 |
| `REUSE_PLAN` | `0` | `1` = 复用已有拆镜，跳过工作区重组与 Codex 规划 |

## 6. 冒烟测试

不需要任何模型额度就能验证安装：

```bash
export PIPELINE_PY="$PWD/.venv/bin/python"

# a) 建一集（不调用外部服务）
rm -rf /tmp/nvp-smoke
bash ./episode.sh init /tmp/nvp-smoke 16:9 blue-professional
bash ./episode.sh status /tmp/nvp-smoke

# b) 配置解析
eval "$("$PIPELINE_PY" ./ep-env.py /tmp/nvp-smoke)"
echo "$WIDTH x $HEIGHT @ $FPS  preset=$PRESET"

# c) 状态面板（写入 pipeline/status.html，每 10 秒刷新；Ctrl-C 退出）
python3 ./status-watcher.py /tmp/nvp-smoke/run/scenes
```

三段都通过说明执行器与配置链正常。渲染链还需要 P4/P5 的外部 CLI 与网络/额度。

## 7. 让 agent 加载技能

`SKILL.md` 是标准的 agent 技能文件（YAML frontmatter + Markdown 正文）。放到对应位置即可：

| 运行环境 | 放置位置 |
|---|---|
| Hermes Agent | `~/.hermes/skills/creative/narrated-video-pipeline/` |
| Claude Code | `~/.claude/skills/narrated-video-pipeline/`（项目内：`.claude/skills/`） |
| Codex | `~/.codex/skills/narrated-video-pipeline/` |

技能默认把执行器目录写作 `~/video-pipeline`。两种接法：

```bash
# 方式 A：把执行器目录指到仓库里
export PIPELINE_DIR=~/nvp/pipeline

# 方式 B：做软链接（技能文档里的路径即可原样生效）
ln -s ~/nvp/pipeline ~/video-pipeline
```

`references/` 与 `SKILL.md` 需一起复制，技能的深化文档在正文中以相对路径引用。
