# 安装

装完之后先跑一次 `bash pipeline/episode.sh doctor` —— 它会逐项检查下面所有依赖、解释器、TTS 客户端与密钥、渲染工作区，缺哪项都会给出补齐命令。以下各节是它的展开说明。

> 这些依赖都是**外部调用**（`npx` / 独立进程 / 官方 API），本仓库不打包它们的代码。各自的来源、作者与许可证见 README 的 [致谢与第三方组件](README.md#致谢与第三方组件)。

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
| Python 3.11+ | 执行器（需 PyYAML） | `python3 -V` |
| Codex CLI | P4 拆镜（只规划） | `codex --version`，**需自备账号与额度** |
| Claude Code CLI | P5 逐镜头实现 | `claude --version`，**需自备账号与额度** |

`ffmpeg` / `jq` / Node / Python 用于 P6-P7 的合成与质检；Codex 与 Claude Code 只在 P4-P5 需要，缺了不影响 P0-P3 和 P7。

## 2. 取代码 + 建虚拟环境

```bash
git clone https://github.com/zyzosric-collab/narrated-video-pipeline ~/nvp
cd ~/nvp/pipeline
python3 -m venv .venv
.venv/bin/pip install pyyaml
```

> `.venv` 建议建在 `pipeline/` 目录内（默认解释器路径是 `$PIPELINE/.venv/bin/python`）；建在别处也行，用 `PIPELINE_PY` 指过去，或让系统 `python3` 装好 PyYAML 也可以被自动选中。三者都没有时脚本会明确报错退出，不会静默假装成功。

## 3. 渲染工作区（auto-motion）

P4/P5 需要一个 `auto-motion` 工作区：里面包含 `.claude/skills/`（含 `hyperframes*` 技能）与
`exampleFolder/`（每集的工作区模板，含 `run-claude-ai.sh`、预设目录等），执行器会把它整份拷进每集的 `run/` 下。

```bash
git clone https://github.com/zyzosric-collab/auto-motion ~/auto-motion
ls ~/auto-motion/exampleFolder/.claude/skills/     # 应能看到 hyperframes* / general-video 等
```

若工作区不在 `~/auto-motion`，用 `AUTO_MOTION_DIR` 指过去（见第 5 节）。

## 4. 配音（豆包 TTS，仓库自带）

配音阶段调用的是**本仓库自带的**火山引擎豆包语音合成客户端：`tools/volcengine-doubao-tts/`（纯 Python 标准库，无需 `pip install`）。

你要准备的只有自己的 API Key：

```bash
cd ~/nvp/tools/volcengine-doubao-tts
cp .env.example .env.local
chmod 600 .env.local
$EDITOR .env.local          # 填 VOLCENGINE_TTS_API_KEY=<你的火山引擎 API Key>

python3 tts.py --text '配置检查。' --dry-run    # 只打印将要发送的请求头/参数，不产生费用
```

输出目录、音色与语速取自 `episode.yaml`（`speaker` / `speech_rate`），无需改脚本。逐字稿与音色细节见
[`../tools/volcengine-doubao-tts/README.md`](../tools/volcengine-doubao-tts/README.md)。

**解析顺序**：`$TTS_CLI` → 仓库内 `tools/volcengine-doubao-tts/tts.py` → 旧的本机路径。也就是说 clone 下来配好 Key 就能直接用，不需要设任何变量。

要换成别的实现，写一个满足下面契约的脚本并把 `TTS_CLI` 指过去即可：

```bash
python3 "$TTS_CLI" --text <文本> \
                   --speaker <音色ID> \        # episode.yaml: speaker
                   --speech-rate <整数> \      # episode.yaml: speech_rate
                   --style <风格> \
                   --instruction <发音提示> \
                   --output <mp3> \
                   --subtitle-json <词级JSON>  # 必须输出词级时间戳
```

**关键要求**：`--subtitle-json` 必须给出**词级**时间戳，否则 P5 的逐镜头时间切片（`make-scene-context.py`）无法做，只能退化成按段落估算。也可以完全跳过 P2、用现成成品配音走 `references/external-narration-bridge.md` 里的 whisper.cpp 词级对齐路线。

## 5. 环境变量

全部可选，脚本内已有默认值（`pipeline/*.sh` 顶部）：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `PIPELINE_DIR` | 脚本所在目录 | 执行器根目录 |
| `PIPELINE_PY` | `$PIPELINE/.venv/bin/python` | 执行器用的 Python（退路：系统 `python3`） |
| `AUTO_MOTION_DIR` | `$HOME/auto-motion` | 渲染工作区 |
| `TTS_CLI` | 仓库内 `tools/volcengine-doubao-tts/tts.py` | 配音客户端（可换成你自己的实现） |
| `REUSE_PLAN` | `0` | `1` = 复用已有拆镜，跳过工作区重组与 Codex 规划 |

## 6. 冒烟测试

**第一段**：环境自检（不消耗任何额度、不联网付费接口）

```bash
bash ~/nvp/pipeline/episode.sh doctor
```

**第二段**：建集 + 配置链（不调用外部服务）

```bash
rm -rf /tmp/nvp-smoke
bash ~/nvp/pipeline/episode.sh init /tmp/nvp-smoke 16:9 blue-professional
bash ~/nvp/pipeline/episode.sh status /tmp/nvp-smoke
eval "$(~/nvp/pipeline/.venv/bin/python ~/nvp/pipeline/ep-env.py /tmp/nvp-smoke)"
echo "$WIDTH x $HEIGHT @ $FPS  preset=$PRESET"
```

**第三段**：真跑一次 P2（需要第 4 节的 Key；约消耗一句短句的额度）。先放一个单句分段：

```bash
printf '[\n  {"style": "tech_explainer", "text": "这是一次配音链路检查。"}\n]\n' > /tmp/nvp-smoke/script-segments.json
bash ~/nvp/pipeline/episode.sh voice /tmp/nvp-smoke
ffprobe -v error -show_entries format=duration -of csv=p=0 /tmp/nvp-smoke/narration.mp3
head -c 200 /tmp/nvp-smoke/voice-timing.json
```

看到 `narration.mp3`、`transcription.srt`、`voice-timing.json`（词级）三件产物即 P2 通。渲染链还需要 P4/P5 的外部 CLI 与网络/额度。

## 7. 让 agent 加载技能

`SKILL.md` 是标准的 agent 技能文件（YAML frontmatter + Markdown 正文）。放到对应位置即可：

| 运行环境 | 放置位置 |
|---|---|
| Hermes Agent | `~/.hermes/skills/creative/narrated-video-pipeline/` |
| Claude Code | `~/.claude/skills/narrated-video-pipeline/`（项目内：`.claude/skills/`） |
| Codex | `~/.codex/skills/narrated-video-pipeline/` |

`references/` 与 `SKILL.md` 需一起复制，技能的深化文档在正文中以相对路径引用。

技能默认把执行器目录写作 `~/video-pipeline`，而本仓库克隆到 `~/nvp`。两种接法：

```bash
# 方式 A：把执行器目录指到仓库里
export PIPELINE_DIR=~/nvp/pipeline

# 方式 B：做软链接（技能文档里的路径即可原样生效）
ln -s ~/nvp/pipeline ~/video-pipeline
```
