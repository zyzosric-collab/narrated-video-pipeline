# 火山引擎豆包语音合成 2.0（视频口播配置）

本目录是 `narrated-video-pipeline` 的配音实现（Phase 2）。采用火山引擎 V3 HTTP SSE 单向流式接口，适合一次提交完整口播稿。脚本只依赖 Python 标准库，不需要 `pip install` 任何东西。

## 配置（三步）

```bash
cd tools/volcengine-doubao-tts

# 1) 生成自己的密钥文件
cp .env.example .env.local
chmod 600 .env.local

# 2) 填入你的火山引擎语音合成 API Key
#    控制台：https://console.volcengine.com/speech/app
#    需要开通「语音合成 2.0 / seed-tts-2.0」并创建应用，取应用的 API Key（它以 X-Api-Key 请求头发送）
$EDITOR .env.local        # VOLCENGINE_TTS_API_KEY=<你的 Key>

# 3) 自检（不会调用付费接口）
python3 tts.py --text '配置检查。' --dry-run
```

`.env.local` 已在本目录的 `.gitignore` 中，不会被提交。密钥也可以直接由进程环境变量提供（优先级高于 `.env.local`）：`export VOLCENGINE_TTS_API_KEY=...`。

## 基线

| 项 | 值 |
|---|---|
| 模型资源 | `seed-tts-2.0` |
| 默认音色 | 大壹 2.0 男声 `zh_male_dayi_uranus_bigtts` |
| 默认语速 | `speech_rate=20`（约正常语速 1.2 倍） |
| 输出 | MP3、24 kHz、160 kbps |
| 语气 | `context_texts` 自然语言指令（不用旧版固定情绪枚举） |
| 发音 | 默认把 `AI` / `AIGC` / `API` / `PPT` / `GPU` 等缩写转为逐字母读法 |

这些值写在 `config.json`，可用命令行参数临时覆盖。

## 用法

```bash
# 基本合成
python3 tts.py --text 'AI 正在从回答问题，走向完成工作。' --output outputs/test.mp3

# 选择语气
python3 tts.py --text '这次真正变化的，不是参数。' --style counterintuitive_hook --output outputs/hook.mp3

# 指定音色（不改长期默认值）
python3 tts.py --text '……' --speaker zh_male_dayi_uranus_bigtts --output outputs/dayi.mp3

# 追加某一段独有的表演指令
python3 tts.py --text '真正的分水岭，是能不能交付。' --style conclusion \
  --instruction '最后六个字略微放慢并加重。' --output outputs/conclusion.mp3

# 字词级时间戳（流水线 P2 需要）
python3 tts.py --text '……' --output outputs/narration.mp3 --subtitle-json outputs/narration.words.json
```

`--subtitle-json` 落盘的是火山引擎原生的 `sentence.words`（**时间单位是秒，浮点**）：

```json
{
  "schema_version": "1.0.0",
  "request_id": "...",
  "sentences": [
    {
      "text": "配置检查，一二三四五六七八九十。",
      "phonemes": [],
      "words": [
        { "word": "配", "startTime": 0.115, "endTime": 0.185, "confidence": 0.418 }
      ]
    }
  ]
}
```

`build_narration_v2.py` 就是按 `sentences[].words[]` 把词级时间轴拼成整片 SRT 与镜头台词切片的。

`--dry-run` 只校验配置、不调用接口，输出中的密钥始终脱敏。

## 与流水线的关系

流水线通过 `TTS_CLI` 环境变量找到本脚本：

```bash
python3 "$TTS_CLI" --text <文本> --speaker <音色> --speech-rate <整数> \
  --style <风格> --instruction <提示> --output <mp3> --subtitle-json <词级JSON>
```

`pipeline/` 下的脚本按这个顺序解析：`$TTS_CLI` → 仓库内本目录 → 本机旧路径。也就是说，**什么都不设也能用**；想换成别的实现，只需把 `TTS_CLI` 指过去（接口一致即可）。

## 安全边界

- 真正的密钥只放在权限 `600` 的 `.env.local`，或由进程环境变量注入。
- `.env.local` 已在 `.gitignore` 中，不得放进源码包、交付包或日志。
- 若密钥曾在聊天、截图或公开文本中出现，请到火山引擎控制台轮换。

## 官方资料

- 语音合成 V3 接口：https://docs.volcengine.com/docs/6561/2532486?lang=zh
- 语音指令：https://www.volcengine.com/docs/6561/1871062?lang=zh
- 音色列表：https://www.volcengine.com/docs/6561/1257544?lang=zh
- 官方 ByteDance SSE 示例：https://github.com/bytedance/agentkit-samples/tree/main/skills/byted-text-to-speech
