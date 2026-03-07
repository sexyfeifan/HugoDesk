# HugoDesk 0.4.0 ✨📝🚀

把 `Hugo + GitHub Pages` 这套原本偏命令行的流程，整理成一个能长期日常使用的 macOS 桌面软件。  
如果你想继续用 Hugo，但不想每天在“写作、配 Front Matter、管图片、查 Pages、盯 Actions、看日志”之间来回切，这版就是正式可用线。☕️

---

## 📌 HugoDesk 是做什么的？

一句话：

**HugoDesk = 一个面向 Hugo 项目的写作、内容管理、配置维护、发布检查和 GitHub Pages 部署工作台。**

它不只是 Markdown 编辑器，也不只是 Git 推送壳。
它的目标是把一条真实的 Hugo 工作链路收进一个上下文里：

- ✍️ 写正文
- 🧾 管 Front Matter
- 🖼️ 管图片和页面资源
- 🌲 看内容树结构
- 🌐 处理多语言内容目录
- 🔗 插入 `ref / relref`
- 🧩 插入 shortcode
- 🎨 调主题和站点配置
- 🧪 做发布前检查
- 🚀 提交、推送、部署 GitHub Pages
- 📜 看 Workflow、Pages 和日志

---

## 🌟 0.4.0 这版最重要的变化

### 1. 写作区终于不是“单文件编辑器”了 🌲

这版最大的升级，是 HugoDesk 开始真正理解 Hugo 的内容结构：

- ✅ 左侧树形内容浏览器
- ✅ 区分单文件、页面包（Leaf Bundle）、栏目包（Section Bundle）
- ✅ 新建内容时可选内容形态、Front Matter 格式、archetype
- ✅ 创建前就能看到目标路径和头部预览

这意味着它不再只是“编辑一篇 Markdown”，而是开始管理 Hugo 的内容模型本身。

### 2. 页面资源工作流正式进入主线 🖼️

现在图片和资源不再只有一种粗放的 `static/images/uploads` 模式。

你可以：

- ✅ 把资源导入当前页面包
- ✅ 从资源列表直接插入正文
- ✅ 改名 / 移动到子目录
- ✅ 删除无用资源
- ✅ 在普通博客模式下继续用静态目录策略

对 Hugo 来说，这一步非常关键，因为页面资源才是很多主题和内容组织方式真正依赖的工作流。

### 3. 多语言与内容引用能力终于接上了 🌍

这版已经能覆盖 Hugo 多语言项目里最常用的内容侧操作：

- ✅ 切换不同 `contentDir` 工作区
- ✅ 创建翻译副本
- ✅ 诊断缺失翻译
- ✅ 插入 `ref / relref`
- ✅ 选择标题锚点
- ✅ 扫描全工作区失效引用

如果你做的是文档站、双语站或者结构稍复杂的博客，这一版会比旧版实用很多。

### 4. Hugo 高级内容能力不再只能手写 🧩

这版把一批过去只能手改 Front Matter 或模板文件的能力做进了界面：

- ✅ 动态 taxonomy
- ✅ taxonomy 权重
- ✅ 菜单 Front Matter
- ✅ 菜单树预览
- ✅ `sectionPagesMenu`
- ✅ `build` 与 `cascade.build`
- ✅ shortcode 扫描、参数提示、插入

这不是“多了一些设置项”，而是把 Hugo 的高级内容能力图形化了。

### 5. 发布页继续保住 HugoDesk 的核心价值 🚀

HugoDesk 的重点一直不是只做编辑器，而是让“写完之后能发出去，出了问题知道卡在哪”。

现在发布页仍然能做：

- ✅ 发布前检查
- ✅ GitHub 连通性检测
- ✅ Pages 来源检查与修复
- ✅ Workflow 状态同步
- ✅ 本地时间显示运行时间
- ✅ 原始日志 + 分段日志查看
- ✅ 一键发布 / 提交并推送

---

## 🛠️ 当前核心功能清单

- 📝 正文编辑：默认 `Vditor`，保留兼容模式
- 👀 编辑器内预览：直接在新编辑器里完成
- 🤖 AI 写作：读取文字与链接素材，生成可追加正文的 Markdown
- 🧾 Front Matter：结构化 / 原始双模式，支持 `TOML / YAML / JSON`
- 🌲 树形内容浏览：识别 bundle / section 结构
- 🖼️ 页面资源管理：导入、插入、移动、删除
- 🌍 多语言工作区：切换、补翻译、缺失诊断
- 🔗 页面引用：`ref / relref` + 锚点
- 🧩 shortcode：扫描、提示、插入
- 🎨 主题检测与主题设置
- 🔐 GitHub Classic / Fine-grained Token 支持
- 🧪 发布前检查：配置、主题、文章、Pages、引用、翻译、GitHub 连通性等
- 📦 GitHub Pages 发布：推送、Workflow、日志、状态同步
- 📚 本地 wiki：应用内说明与使用文档

---

## 🧠 这个软件现在的开发思路

### 1. 先把 Hugo 的真实结构做进去

这版之后，HugoDesk 的方向已经比较明确：
不是继续堆“写作工具栏按钮”，而是优先把 Hugo 本身的结构能力做进软件。

所以你会看到它重点投入在：

- 页面包
- 页面资源
- 多语言内容目录
- taxonomy
- menus
- `build`
- `ref / relref`
- shortcode

### 2. 优先做确定性，不做花哨壳子

Hugo 项目真正容易出问题的地方，通常不是编辑器少一个按钮，而是：

- 配置不一致
- 内容结构不规范
- Pages 来源不对
- Workflow 缺失或重复
- Token 权限不对
- Git 推送和远端状态不一致
- 引用或翻译副本有缺口

所以 HugoDesk 现在仍然会把大量精力放在“检查、提示、修复入口”上。

### 3. 写作体验升级，但不脱离 Hugo 现实

新的编辑器已经正式进入主线，但方向不是做成富文本博客工具，
而是继续保持：

- Markdown 可控
- Hugo 路径和结构不失真
- Git 仓库可维护
- 内容资源真实落盘

也就是说，它是更好写的 Hugo 工具，不是脱离 Hugo 的内容平台。

---

## 🗂️ 页面结构

- `项目`：项目根目录、Git 远程、令牌、Hugo 工具、配置包
- `写作`：内容树、AI 写作、正文编辑、Front Matter、页面资源、引用、短代码
- `主题设置`：主题检测、切换、主题参数编辑
- `AI 设置`：模型地址、模型名、API Key
- `发布`：预检、Workflow、Pages、日志、修复操作

---

## 🚀 适合谁

- 想继续坚持 Hugo，但不想把日常流程全压在终端上
- 用 GitHub Pages 部署，想把检查和排障做得更稳
- 做文档站、多语言站、结构型博客的人
- 想把“写作 + 内容管理 + 发布”放进一个软件里的人

---

## 📦 本地运行

```bash
cd /Users/sexyfeifan/Library/Mobile\ Documents/com~apple~CloudDocs/Code/HugoDesk
swift run
```

Release 构建：

```bash
swift build -c release
```

---

## 📖 更新记录

详细变更见 [CHANGELOG.md](CHANGELOG.md)
