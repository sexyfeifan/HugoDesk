# HugoDesk ✨  
把 Hugo 写作 + 发布变成桌面 App 的一条龙体验（macOS）

> 一句话安利：如果你每次发博客都要在终端里反复敲 `hugo`、`git pull`、`git push`，那 HugoDesk 就是给你省时间和省心的。🧃

## 🌟 小红书风推荐文（可直接转发）

最近在用一个本地博客发布工具 `HugoDesk`，体验真的很像“把命令行工作流装进了可视化面板”：

- ✍️ 写作区直接编辑 Markdown，支持常用模板和文本工具  
- 👀 预览支持软件内查看，不用来回切浏览器  
- 🧠 AI 排版可做 Markdown 符号体检、清理无意义字符、给进度反馈  
- 🚀 发布页支持一键发布，自动做发布前检查  
- 🔧 Pages 来源、Workflow、冲突状态都能在一个页面看到  
- 📜 日志可折叠、可刷新、可复制，排障更快

最爽的是：它不是“玩具编辑器”，而是把 **Hugo + GitHub Pages** 真实发布链路做成了可操作流程。  
对不想长期被命令行绑架的人，真的很友好。✅

---

## 🧭 这个项目解决什么问题

Hugo 很强，但日常流程通常是：

1. 写 Markdown
2. 本地构建看效果
3. 检查目录/配置
4. 同步远端
5. 提交推送
6. 看 GitHub Actions 和 Pages 是否正常

HugoDesk 把这套流程做成图形界面，目标是：**减少重复操作，降低出错率，提升发布确定性**。

## 🎯 核心能力

- 📝 Markdown 写作：文章管理、Front Matter、文本快捷工具
- 🖼️ 图片处理：导入到 `static/images/uploads`，自动归一化图片链接
- 👁️ 软件内预览：支持 Hugo 渲染与内置兜底预览
- 🧠 AI 文本能力：Markdown 结构检查与排版修正，带进度显示
- 🔐 双 Token 支持：Fine-grained + Classic（API 优先用 Classic）
- 🧪 发布前检查：配置、Token、Pages 来源、Workflow、主题、冲突、连通性等
- 🌐 Pages 治理：检查/修复到 GitHub Actions workflow 模式
- 🧱 Hugo 结构体检：检测缺失并可一键修复
- 📦 项目配置包：`.hugodesk.local.json` 自动读写，不入 Git
- 📊 部署状态追踪：自动轮询 Actions 最新运行状态

## 🧩 页面结构

- `项目`：项目路径、发布分支、远程地址与凭据、Hugo 工具、配置包
- `写作`：文章编辑、文本工具、预览
- `主题设置`：主题参数编辑、主题检测与切换
- `AI 设置`：AI 地址/模型/API Key
- `发布`：预检、发布执行、部署修复、工作流状态、日志中心

## 🎨 主题设置升级（重点）

当前版本支持：

- 🔍 自动扫描 `themes/` 下的主题目录
- 🖱️ 手动选择主题或手动输入主题名并应用
- 🧠 根据主题能力动态精简设置项（如 Gitalk / 搜索 / 外链 / 数学公式）
- 🧷 若主题来自 Hugo Modules（不在本地 `themes/`），也会保留可选项

## 🚀 推荐发布流程

1. 在 `项目` 页确认博客根目录（含 Hugo 配置）
2. 填写远程地址与 Token（建议 Classic + Fine-grained 都配置）
3. 执行发布前检查，确认主要项为正常/可接受
4. 点击 `一键发布`
5. 在发布页查看 Workflow 状态与日志

> 发布策略固定为 **GitHub Actions**，避免分支直部署带来的冲突和覆盖问题。

## 🆕 最近更新亮点（v0.3.25）

- 🕒 修复 Workflow 时间显示：`创建时间/更新时间` 改为本地时区显示
- 🪟 预检卡片布局稳定：错误详情改为点击弹窗，不再撑乱排版
- 🧭 主题检测与动态设置：可扫描主题并按能力显示配置项
- 📡 Actions 状态自动同步：周期性刷新最新运行信息

详细历史请看：[`CHANGELOG.md`](./CHANGELOG.md)

## 🛠️ 本地运行与构建

```bash
cd /Users/sexyfeifan/Library/Mobile\ Documents/com~apple~CloudDocs/Code/HugoDesk
swift run
```

Release 构建：

```bash
swift build -c release
```

## 📁 目录约定

- `latest/`：当前最新可用产物（`.app` / `.dmg` / `source.zip`）
- `HugoDeskArchive/versions/<version>/`：历史版本归档

## 🔒 安全与隐私

- Token 通过系统钥匙串与本地配置包协同保存
- 日志不输出 Token 明文
- `.hugodesk.local.json` 默认不进入 Git

---

## 📌 适合谁

- 想持续写 Hugo，但不想每次都手敲完整命令
- 用 GitHub Pages 部署，希望流程更稳定可控
- 想要“可视化 + 可排障 + 可追踪”发布体验

## 💬 小红书标签建议

`#Hugo` `#GitHubPages` `#独立博客` `#程序员效率工具` `#开源工具` `#MacApp`

