# pipeline — 执行器

入口是 `episode.sh`：

```bash
bash episode.sh init   <epDir> [aspect] [preset]      # P0 建集
bash episode.sh voice  <epDir>                        # P2 配音 + SRT
bash episode.sh design <epDir>                        # P3 设计契约
bash episode.sh scenes <epDir> [plan|pilot|rest|all]  # P4-P6 拆镜 / 渲染 / 质检 / 拼接
bash episode.sh audio  <epDir> [bgm.mp3]              # P7 混音
bash episode.sh status <epDir>                        # 看进度
```

脚本按 `BASH_SOURCE` 解析自身路径，可从任意目录调用；解释器取 `PIPELINE_PY`，默认 `./.venv/bin/python`。

- 环境变量与安装：见 [`../docs/install.md`](../docs/install.md)
- 逐阶段 runbook：见 [`../docs/usage.md`](../docs/usage.md)
- 脚本职责与数据流：见 [`../docs/architecture.md`](../docs/architecture.md)
- `legacy/` 是已退役的 v2 执行器，仅作历史记录，不要调用
