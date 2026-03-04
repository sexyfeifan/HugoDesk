# HugoDesk 🚀

HugoDesk 是一款面向 macOS 的 Hugo 博客桌面客户端（SwiftUI），目标是让你在图形界面中完成 **写作 → 构建 → 检测 → 推送 → GitHub Pages 发布** 的完整流程，减少对命令行的依赖。

## 为什么做这个软件 🤔

Hugo 本身非常强大，但日常发布通常要在终端里反复执行 `hugo`、`git pull --rebase`、`git push`、排查冲突和部署状态。

HugoDesk 的定位就是：

- ✍️ 把文章编辑和元数据维护放到一个界面
- 🧱 把构建、同步、推送过程做成可追踪的按钮流程
- 🔎 把故障定位信息统一沉淀到日志窗口
- 🌐 把 GitHub Pages 的关键部署链路（Workflow）内置为一键操作

## 核心能力一览 ✨

- 📝 Markdown 写作：支持右键工具、选区工具、常用 Markdown 模板
- 🖼️ 图片处理：导入图片到 `static/images/uploads`，并自动修正文章图片链接
- 🧾 元数据辅助：标题可由文件名生成、摘要可由正文提取
- 🧠 AI 能力：可配置 API 地址/Key/模型，在写作页执行 Markdown 排版与错误排障建议
- 🔐 安全推送：支持 GitHub Token，推送和检测可在无交互终端下执行
- 🧪 发布检测：检查 Git/Hugo、远程可达性、dry-run 推送、Pages Workflow 完整性
- 🧭 Pages 来源治理：可检测 `build_type/source` 并一键修复为 GitHub Actions（workflow）
- 🧱 结构体检：可检测 Hugo 目录结构缺失并自动补齐
- ⚙️ 配置包机制：项目根目录 `.hugodesk.local.json` 自动读写（不进入 Git）

## 页面结构（当前）🧭

- `项目`：博客根目录、Git 目标、远程与凭据、项目配置包
- `写作`：文章列表、Front Matter、文本工具、编辑器/预览切换
- `主题设置`：主题参数编辑与保存
- `AI 设置`：AI Base URL / API Key / Model
- `发布`：同步、检测、Workflow 生成、提交推送、日志中心

## 发布流程（推荐）📦

1. 在 `项目` 页确认博客根目录（包含 `hugo.toml`、`content`、`themes`）。
2. 在 `项目` 页填写仓库地址、Token、Workflow 名称。
3. 点击 `一键生成 Pages Workflow`（首次或缺失时）。
4. 点击 `检查 Pages 来源`，确认 `build_type=workflow`（若不是，点击 `修复为 GitHub Actions`）。
5. 点击 `同步远程`，解决潜在 non-fast-forward 风险。
6. 点击 `一键检测推送与部署`，确认链路健康。
7. 点击 `提交并推送`。

> 当前策略固定为 **GitHub Actions 部署**，并且 `hugo.toml` 会随项目一起推送。

## 运行与构建 🛠️

```bash
cd /Users/sexyfeifan/Library/Mobile\ Documents/com~apple~CloudDocs/Code/HugoDesk
swift run
```

发布构建：

```bash
swift build -c release
```

## 目录约定 📁

- `latest/`：当前最新可用产物（`.app` / `.dmg` / `source.zip`）
- `HugoDeskArchive/versions/<version>/`：历史版本归档

## 安全与隐私 🔒

- Token 通过系统钥匙串与本地配置包协同保存
- 发布日志不会明文输出 Token
- `.hugodesk.local.json` 默认不进入 Git

## 更新说明（v0.3.13）🆕

本版本围绕“发布页工作流重排（替代命令行）”完成更新：

- ✅ 合并“Actions 状态 + 发布控制台”为单一 `发布工作流` 界面
- ✅ 发布流程改成线性步骤：结构检查→workflow→Pages来源→构建→同步→推送
- ✅ 新增 `一键发布（推荐）`，自动串行执行完整发布流程
- ✅ 预检改为折叠详情，减少重复区域与操作跳转
- ✅ 日志继续统一承载所有命令输出，便于排障与复盘

## 历史更新速览 📚

- `v0.3.12`：Pages 来源检查/修复、Hugo 结构体检
- `v0.3.11`：配置去重、重复 workflow 清理、最终渲染预览
- `v0.3.10`：配置去重、Hugo 工具快捷操作、最终渲染预览
