# legacy/ —— 历史脚本（保留备查，不再被任何流程调用）

这些脚本是流水线演进过程中的旧版本，**保留的原因是可追溯**：某些配方仍然有效，只是换了实现位置。
不要直接运行它们（路径多为早期绝对路径、参数与当前 `episode.sh` 不兼容）。

| 文件 | 年代 | 说明 | 现在用什么 |
|---|---|---|---|
| `run-scenes-v2.sh` | Episode1–2 | 旧并行渲染编排：xargs -P3、无 plan/preflight 分级 | `run-scenes-v3.sh` |
| `run-audio-ep1.sh` | Episode1 | 早期音频脚本，单路 BGM，无 SFX 层 | `build-audio.sh` |
| `mix-final-v2.sh` | Episode2（2026-08-31） | **当前音频配方的来源**：narration `loudnorm=I=-16:TP=-1.5:LRA=7`、`ratio=8:attack=100:makeup=1` 旁链、SFX 预混成等长 bed、`normalize=0`、立体声 48k 输出 | 配方已并入 `build-audio.sh`，此文件仅作历史参照 |
| `inspect-scenes.sh` | Episode1 | 拆镜质量巡检（护栏/画幅/特效选型统计），目录路径写死 | 按需重写；QC 门在 `run-scenes-v3.sh` 内 |

> 教训（2026-09-13）：打包时曾把比正式脚本更晚、更完整的 `mix-final-v2.sh` 当作「退役脚本」塞进 legacy/，
> 而把更早且带 bug 的 `build-audio.sh` 提成正式 P7 —— 判断依据不应该是文件名，而应该是**修改时间 + 内容成熟度**。
