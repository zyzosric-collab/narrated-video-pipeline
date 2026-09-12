# 口播视频流水线 v2 设计文档

> 状态：待用户确认后实施
> 基座：auto-motion（vibe-motion 原版，tracked 零修改）+ 仓库外 runner
> Episode 1 验证过的经验 + 三个深读报告（设计层/工作流层/特效库）的全部发现

---

## v1 → v2 变更总览

| # | 变更 | 解决的问题 | 来源 |
|---|---|---|---|
| 1 | 开工配置阶段（尺寸/预设/BGM情绪 一次问清） | 尺寸写死 3:4；视觉无人定 | 用户要求 |
| 2 | frame.md 设计契约注入（blue-professional） | 8镜头各自为政的深色压抑 | design-spec.md 机制 |
| 3 | 卡拉OK字幕系统（caption-skin + 词级时间戳） | 配音与文字动画或先或后 | caption-skin.html 原生机制 |
| 4 | 音频层（BGM + SFX + ducking 混音） | 成片无背景音乐音效 | 用户要求（Pixabay/Jamendo） |
| 5 | 质检门（lint/check + 参数化验收 + 防错护栏） | SCENE_ID 漏改、孤儿渲染、细节错位 | Episode1 实测教训 + cli 技能 |
| 6 | 画幅参数化（3:4 / 9:16 / 16:9） | 只能出 1080×1440 | 用户要求 |

---

## 流程（9 个 Phase）

```
Phase 0  开工配置（新增，一次性交互）
         ├─ 尺寸三选一：9:16(1080×1920) / 16:9(1920×1080) / 3:4(1080×1440)
         ├─ 视觉预设确认（默认 blue-professional，可换 13 选 1）
         ├─ BGM 情绪方向（自动从选题推断 + 用户可改）
         └─ 产出 episode.yaml（本集唯一配置真源，后续所有环节读它）

Phase 1  写作（不变）
         └─ 资料收集 → mediastorm-copywriter 口播稿（分段，句=段）

Phase 2  配音（增强）
         ├─ 豆包 TTS 逐段（大壹2.0 / rate=10 / 审批基线）
         ├─ 开启响应中的 subtitle_sentences + sentence.words（词级时间戳）
         ├─ 产物：narration.mp3 + segments.json（句级+词级时间轴）
         └─ 兜底：接口不给词级时间时，hyperframes transcribe 强制对齐

Phase 3  设计契约（新增）
         ├─ blue-professional/FRAME.md → 工作区 frame.md（追加工件：
         │   · 本集画幅适配段（16:9：display 左/索引顶；9:16：面板转横带）
         │   · 中文字体对（官方方案：Noto Sans SC 700 display / Noto Serif SC 400 body，
         │     本机 fallback Hiragino Sans GB；数字保持阿拉伯）
         │   · CJK 提示：eyebrow 大写字距信号弱化 → 用 accent-line 补足
         ├─ caption-skin.html 启用（卡拉OK字幕：当前词钴蓝chip/已读墨色/未读灰）
         └─ frame.md 复制进每个镜头目录（随 exampleFolder 分发机制）

Phase 4  拆镜与执行（增强）
         ├─ Codex 拆镜（PROMPT 追加段注入：
         │   · 尺寸参数 {W}×{H} 替换模板硬编码的 1080x1440
         │   · "每个镜头必须先读 frame.md，色板/字体/间距严格采用，禁止自选深色"
         │   · 特效选型规则（v1 已有，保留）
         │   · 防错三条：SCENE_ID 必须=目录名 / 禁止后台渲染 / 渲染完必须转存镜头目录)
         └─ 执行器（保留 B 方案）：xargs -P3 并行跑已填好的 run-claude-ai.sh

Phase 5  质检门（新增，每镜头自动执行）
         ├─ 护栏A：执行前校验 SCENE_ID==目录名，不一致自动改 run 副本（不碰仓库）
         ├─ 护栏B：claude 退出后无 mp4 但 hf-proj/index.html 存在 → 自动补渲染
         ├─ 护栏C：npx hyperframes lint（结构性错误即 fail）
         ├─ 验收：ffprobe 参数化（宽高/fps/时长/无音轨全部从 episode.yaml 读期望值）
         └─ 视觉抽检：每镜头首中尾 3 帧截图（人工可复核）

Phase 6  拼接（不变）
         └─ ffmpeg concat → final.mp4（静音，auto-motion 原生契约不破坏）

Phase 7  音频层（新增）
         ├─ BGM：按 episode.yaml 情绪标签 → Pixabay(浏览器自动化)/Jamendo(API) 下载 2-3 首候选
         ├─ SFX：镜头切点时间戳从 concat 清单取 → whoosh/pop 等短音效（Freesound/Pixabay）
         └─ 混音（一条 ffmpeg）：
            narration 100%
            BGM sidechaincompress（说话时≈15%，停顿浮回≈30%）
            SFX 切点插入（-20dB 短促不抢戏）
            → final-with-voice.mp4

Phase 8  交付
         └─ 成片 + 抽帧质检图 + 各镜头产物/日志 + 本集配置存档（可复现）
```

---

## 关键实现注记

### 尺寸参数化（3 个注入点，全在仓库外副本）
1. `run-claude-ai.sh` 副本：`1080x1440` → `{W}×{H}`（episode.yaml 供给）
2. 验收脚本：期望宽高从 episode.yaml 读（不再硬编码 1080/1440）
3. HyperFrames 构图由 Claude 按 prompt 里的尺寸写 `data-width/data-height`（core 技能原生机制）

### frame.md 采纳链（design-spec.md 官方机制）
```
frame-presets/blue-professional/FRAME.md（模板，大写）
  → 复制为工作区 frame.md（小写，官方规定）
  → 追加 episode.yaml 派生的画幅适配段 + 中文字体对
  → 每镜头目录各一份（随模板分发）
  → Claude 按 "frontmatter=brand truth, prose=context" 消费
```

### 卡拉OK字幕（替代 v1 的"整句文字动画"）
- caption-skin.html → compositions/captions.html（官方 Step2 机制）
- GROUPS 数组由词级时间戳填充（Phase 2 产物）
- 状态机 seek-safe（gsap.set，官方注明禁用 tl.call 回调）
- 位置：画面底部 band（--cap-band-top/height 有预留变量）

### 音频混音（单条命令）
```
ffmpeg -i final.mp4 -i narration.mp3 -i bgm.mp3 -i sfx.mp3 -filter_complex "
  [2:a]volume=0.3,acompressor=...[bgm];
  [1:a]asplit=2[n1][sc];
  [sc]sidechaincompress=threshold=0.05:ratio=8[bgmducked];
  [n1][bgmducked][3:a]amix=inputs=3:weights=1 0.35 0.5[out]" ...
```

### 不动仓库的边界（延续纯净原则）
- 所有模板改动都发生在 run 工作区副本（runner 负责复制+打补丁）
- frame.md/caption-skin 属于"纯新增"文件（git untracked），且源自仓库自带的预设目录
- validate 逻辑参数化版本放 runner 侧，仓库 validate.sh 原样

---

## 待确认项

1. **默认尺寸**：episode.yaml 的默认值定 16:9（Episode1 重制用），还是 9:16？
2. **BGM 默认音量基线**：30%（你之前用过的值）还是更低 25%？
3. **预设是否锁定为频道级**：之后每部片默认 blue-professional，换需明确说明？
4. **实施顺序**：先升级 runner 全部 9 个 Phase 再重制 Episode1（推荐，一步到位）？

---

## 实现修正（2026-09-13，P3–P7 全链验证时发现）

用桩替掉 Codex/Claude 的智能环节、真跑执行器后，发现 build-audio.sh 与设计稿不一致，三处已修：

| # | 问题 | 症状 | 修正 |
|---|---|---|---|
| 1 | 过滤器图有未被消费的输出 `[bgmduck2]` | ffmpeg 报 unconnected output → 整条主命令失败 → **静默**走 `\|\|` 回退，切点 SFX 永远不生效（`2>/dev/null` 把错误吞了） | 删掉多余的 `[2:a][1:a]` pass；改正侧链方向为「第一个输入=被压缩信号」`[2:a][1:a]sidechaincompress`（BGM 被压，narration 当 key）；回退改为打印 WARN |
| 2 | `amix` 未关 normalize（默认 true） | 输入从 2 个变 3 个时整体被重新归一化，**加不加 SFX 会让整轨差 ~7 dB** | 两处都加 `:normalize=0`，电平只由 weights 决定 |
| 3 | `-shortest` + `duration=first` | 配音比画面短时，`-shortest` 按音频截短，**画面尾部被剪掉** | 改 `duration=longest` + `-t "$VID_DUR"`，音频以成片时长为准，画面零截断 |

顺带：`pipeline/episode.sh` 的 `design` 原先要求 `run/` 已存在（即必须先拆镜），与文档里的 init→voice→design→scenes 顺序矛盾；改为自建 `run/`，任意时点可跑。

验证数据（`/tmp/e2e_full_p3p7.sh`，桩渲染 2 镜头 + 合成 BGM/SFX）：

- 侧链增益衰减：BGM 受 duck `-44.5 LUFS` vs 未 duck `-35.7 LUFS` → **8.8 dB**
- 切点 SFX：2.40–2.55s 窗口 `-31.3 dB` vs 无 SFX 对照 `-43.1 dB` → **+11.8 dB**（whoosh 确实落在切点）
- 画面零重编码：`run/final.mp4` 与成片的视频流 md5 一致
- 时长对齐：`final.mp4` 4.033s = 成片 4.033s（配音 4.296s，不再截画面）

### 第 4 处：P7 混音配方换成本机已验证的 v2 配方（2026-09-13）

修完前三条后复查发现：本机真正的混音配方是 `mix-final-v2.sh`（Aug 31 18:48，比 `build-audio.sh` 的 14:12 更晚），而打包时把它当「legacy 退役脚本」处理、把更早且有 bug 的 `build-audio.sh` 提成了正式 P7 —— 这是打包环节的判断错误，也是「本机跑得通、用户那边跑不通」的一部分真正来源。已把 v2 配方并入 `pipeline/build-audio.sh`：

| 项 | 旧 build-audio.sh | 现（= mix-final-v2.sh 配方） |
|---|---|---|
| narration 响度 | 原始电平 | `loudnorm=I=-16:TP=-1.5:LRA=7` |
| 旁链压缩 | `ratio=6:attack=120` | `ratio=8:attack=100:makeup=1` |
| SFX | 仅第一个切点，一条 whoosh，混在主图里 | 每个切点一条 whoosh + 可选结尾 chime，预混成等长 `sfx-bed.wav` 再作为一路输入 |
| amix 权重 | `1.0 0.5 0.5` | `1.0 0.5 0.35` |
| 输出 | 单声道 aac | `-ar 48000 -ac 2` 立体声 |

回归数据（同一桩场景）：**−16.8 LUFS**（v2 目标 −16）、aac/48000/**stereo**、时长 5.033s = `run/final.mp4` 5.033s、视频流 md5 一致、切点窗口 −24.9 dB vs 静默 −inf、BGM 旁链后 −42.0 vs 原始 −35.3 LUFS（−6.7 dB）；**有/无 SFX 素材两种情况下整轨都是 −16.8 LUFS**（修复前差约 7 dB）。
