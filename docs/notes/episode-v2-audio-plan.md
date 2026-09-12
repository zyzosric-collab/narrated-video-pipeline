# 视频流水线 v2：音频层执行规则

## 素材来源

- 首选 Pixabay：音乐和音效统一搜索、试听、下载。
- Pixabay 被 Cloudflare 拦截时，按顺序回退 Openverse、Freesound、Mixkit、本地已审核缓存。
- 不得把备用来源伪称为 Pixabay。
- 每个素材必须保存作品页、作者、许可证、许可证 URL 和本地文件路径。
- CC0 优先；CC BY 必须生成署名记录；不选 CC BY-NC/ND。

## BGM 选择

- 一部知识口播默认 1 首主 BGM。
- 依据主题、写作情绪和 frame preset 生成搜索词。
- blue-professional 默认：clean / minimal / technology / optimistic / ambient。
- 排除：dark、horror、epic trailer、aggressive、vocal、dramatic tension。
- BGM 先生成 3 个候选，用户试听混入旁白后的版本后确定，不由模型只看标题擅自决定。

## SFX 选择与放置

- SFX 按语义事件放置，不按镜头数量机械添加。
- 可用事件：标题 reveal、流程节点、数据强调、镜头转场、成功确认、片尾收束。
- 80 秒知识口播通常 6–9 个 SFX 事件以内。
- blue-professional 适合 soft UI click、轻 whoosh、digital tick、克制的 confirmation chime。
- 每个事件写入 sound-plan.json，包含时间、类型、素材、增益和来源。
- 时间来源优先级：词级时间戳 > 镜头边界 > 人工指定。

## 混音

- Narration 为主轨；BGM 峰值基线 25%，不代表整片恒定 25%。
- 旁白说话时用 sidechaincompress 压低 BGM，attack 80–150ms、release 400–700ms、ratio 约 6–8:1。
- SFX 低增益、短时长，不覆盖语音；转折句“但是”可以只做 BGM 短暂下沉而不加 SFX。
- 末端做 limiter，true peak 目标不高于 -1dBFS；输出 AAC 48kHz 双声道。
- 音频层只在 auto-motion 静音 final.mp4 完成后合成，不改变 auto-motion 原生静音契约。

## 验收

- 视频：分辨率、30fps、H.264 High@4.0、yuv420p、QuickTime 可播放。
- 音频：旁白/BGM/SFX 音轨存在，时长与视频误差可接受，无削波，BGM 不盖住旁白。
- 交付：final-with-voice.mp4、audio-assets.json、sound-plan.json、许可证/署名记录、试听候选记录。