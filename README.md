# HexStrike AI — BugFix Edition

基于 [HexStrike AI](https://github.com/0x4m4/hexstrike-ai)（v6.0.0）的修复版。修复了上游服务端 `hexstrike_server.py` 中的多个 Bug，包括导致健康检查误报的工具别名问题、HTTP 方法不匹配、以及新版工具参数不兼容等问题。

修复后工具可用数：**78 → 103 / 124**（8 个核心工具 8/8 全绿）。

---

## 修复清单

所有修改集中于服务端 `hexstrike_server.py`，完整 diff 见 [patches/hexstrike-fixes.patch](patches/hexstrike-fixes.patch)。

### 1. 健康检查误报（TOOL_ALIASES 别名映射）

**问题**：`/health` 端点用 `which <逻辑名>` 检测工具是否存在，但清单里大量条目是"逻辑名 ≠ 实际命令名"，导致已安装工具被误判为不可用：

| 清单逻辑名 | 实际命令名 |
|---|---|
| `metasploit` | `msfconsole` / `msfvenom` |
| `volatility` / `volatility3` | `vol` / `vol.py` |
| `exploit-db` | `searchsploit` |
| `sleuthkit` | `fls` / `icat` / `tsk_recover` |
| `bulk-extractor` | `bulk_extractor` |
| `ropgadget` | `ROPgadget` |
| `one-gadget` | `one_gadget` |
| `pwntools` | `pwn` |
| `censys-cli` / `shodan-cli` | `censys` / `shodan` |
| `hashcat-utils` | `hashcat` |
| `graphql-scanner` | `jaeles` |
| ... | 等约 45 条 |

**修复**：健康检查增加 `TOOL_ALIASES` 映射表，逐个别名探测；同时 `which` 命令扩展 `~/.local/bin`、`~/go/bin` 等用户级 PATH。

### 2. `/api/files/delete` 405 错误

**问题**：路由只接受 `DELETE` 方法，但 MCP 客户端发送的是 `POST`，永远返回 405。

**修复**：`@app.route("/api/files/delete", methods=["DELETE", "POST"])` 同时接受两种方法。

### 3. `/api/tools/summary_report` 500 错误

**问题**：代码调用了不存在的 `ModernVisualEngine.create_summary_report()` 方法（上游 bug），必然 500。

**修复**：改用引擎现有的 `banner()` / `section()` 静态方法拼装摘要报告。

### 4. httpx 端点参数不兼容

**问题**：服务端调用 `httpx -l <url>`（把 URL 当列表文件传）+ `-t`（新版含义变为 threads）+ `-probe`（新版已移除），对 projectdiscovery httpx v1.12+ 全部无效。

**修复**：改为 `httpx -u <url> -threads <N> -silent`。

> ⚠️ 注意区分：系统里若同时存在 Python `httpx` 库的 CLI（如 `/usr/bin/httpx`）与 Go 版 projectdiscovery httpx（`~/.local/bin/httpx`），务必让 Go 版在 PATH 中靠前，否则参数完全不兼容。

---

## 部署要点（踩坑记录）

### 启动脚本 start_hs.sh

必须显式扩展 PATH 后再启动，否则用户级安装的工具（Go 版 httpx、dalfox 等）会被系统同名二进制盖住：

```bash
#!/bin/bash
cd /path/to/Hexstrike-AI-master
export PATH="$HOME/.local/bin:$HOME/go/bin:$HOME/.gem/ruby/3.3.0/bin:$PATH"
exec setsid nohup python3 hexstrike_server.py > ~/hexstrike.log 2>&1 < /dev/null &
```

### 其他注意事项

| 坑点 | 说明 |
|---|---|
| `/tmp` 是独立小分区 | Go 编译会报 `no space left on device`，需 `export GOTMPDIR=$HOME/gotmp`；并用 `GOPROXY=https://goproxy.cn,direct` |
| 工具软链位置 | 服务进程 PATH 首项应是 `~/.local/bin`，Go/pip 安装的工具软链到这里才会被调用 |
| `/tmp/hexstrike_files` 属主 | 服务以 root 启动会留下 root 属主文件；切回普通用户后须 `chown -R $USER:$USER /tmp/hexstrike_files`，否则 create/delete 报 Permission denied |
| volatility3 入口 | pip 包提供的命令是 `vol`，上游代码按 Debian 惯例调 `vol.py`，需自建软链：`ln -s $(which vol) ~/.local/bin/vol.py` |
| `pkill` 自杀陷阱 | 重启服务时 `pkill -f hexstrike_server.py` 会匹配到执行它的 shell 自身，须用 `pkill -f '^python3 hexstrike_server.py'` |
| apt 逐包安装 | apt 一次失败会整体中止，缺包多的环境应逐包安装；metasploit-framework 体积大，需 nohup 后台安装 |
| MCP 客户端数值参数 | MCP 客户端对数值型可选参数（如 `vulnerabilities_found`）会序列化校验失败，调用时省略即可 |

---

## 验证结果

| 端点 | 修复前 | 修复后 |
|---|---|---|
| `/health` 工具计数 | 78/124（大量误报） | 103/124 |
| `/api/tools/httpx` | ❌ 参数错误 | ✅ |
| `/api/tools/dalfox` | ❌ 未安装 | ✅ |
| `/api/tools/volatility3_analyze` | ❌ 未安装 | ✅ |
| `/api/files/delete` | ❌ 405 | ✅ |
| `/api/tools/summary_report` | ❌ 500 | ✅ |
| `/api/files/create` / `list` | ⚠️ 权限问题 | ✅ |

## 文件结构

```
├── hexstrike_server.py      # 修复后的服务端（核心改动）
├── hexstrike_mcp.py         # MCP 客户端（未修改）
├── requirements.txt         # 依赖清单（上游）
├── hexstrike-ai-mcp.json    # MCP 注册配置示例
├── start_hs.sh              # 推荐启动脚本（含 PATH 修正）
├── patches/
│   └── hexstrike-fixes.patch  # 相对上游 v6.0.0 的完整 diff
└── README-upstream.md       # 上游原版 README
```

## 使用方法

```bash
# 服务端
pip install -r requirements.txt
./start_hs.sh                    # 或 python hexstrike_server.py

# MCP 客户端注册（Claude/Trae/任意 MCP host）
# 参考 hexstrike-ai-mcp.json，指向 http://<server>:8888
```

## 致谢

- 上游项目：[0x4m4/hexstrike-ai](https://github.com/0x4m4/hexstrike-ai)
- 本仓库仅包含 Bug 修复，不改变上游功能与架构

## License

遵循上游项目原许可证。
