# HugoDesk ✨📣💥

把 `Hugo + GitHub Pages` 从“终端 + 配置文件 + 网页来回切”改成“一站式桌面工作流”💻  
一句话：**写得爽、结构稳、发得出去、出错能定位。**

---

## 这是什么软件？🧭

HugoDesk 是一个专门给 Hugo 项目做的 macOS 桌面工具，不是普通 Markdown 编辑器壳子。

它解决的是这条完整链路：

- ✍️ 写正文
- 🧾 管 Front Matter
- 🌲 管内容结构（单文件 / 页面包 / 栏目包）
- 🖼️ 管页面资源和图片
- 🌍 管多语言内容目录
- 🔗 管 `ref / relref` 页面引用
- 🧩 管 shortcode
- 🎨 管主题设置和项目配置
- 🧪 做发布前检查
- 🚀 提交推送到 GitHub Pages
- 📜 看 Actions / Pages / 日志并排障

---

## 现在这版（v0.4.3）到底强在哪？🔥

### 1. 写作区不是“单文本框”了，是真的 Hugo 工作台 🌲

- ✅ 左侧树形内容浏览器
- ✅ 识别单文件 / 页面包（Leaf Bundle）/ 栏目包（Branch Bundle）
- ✅ 新建内容支持内容形态 + Front Matter 格式 + archetype
- ✅ 新建后立即落盘、刷新列表并选中，不再“创建了但左侧看不见”

### 2. 页面资源工作流终于实战可用 🖼️

- ✅ 导入资源到当前页面包
- ✅ 从资源列表直接插入正文
- ✅ 资源改名 / 移动 / 删除
- ✅ 继续兼容 `static` 静态目录模式

### 3. Front Matter 不再写到眼花 🧾

- ✅ 结构化 + 原始双模式
- ✅ 支持 `TOML / YAML / JSON`
- ✅ taxonomy、taxonomy 权重、menu、`build`、`cascade.build` 图形化维护

### 4. 多语言和引用问题提前暴露，不用发布后踩雷 🌍

- ✅ `contentDir` 工作区切换
- ✅ 翻译副本创建
- ✅ 缺失翻译诊断
- ✅ `ref / relref` + 标题锚点
- ✅ 全工作区失效引用扫描

### 5. 发布页不是“一个按钮”，是完整闭环 🚀

- ✅ 发布前检查
- ✅ GitHub 连通性检测
- ✅ Pages 来源检查与修复
- ✅ Workflow 状态同步
- ✅ 本地时间显示运行时间
- ✅ 原始日志 + 分段日志
- ✅ 一键发布 / 提交并推送

### 6. v0.4.3 的关键修正（基于真实使用反馈）🛠️

- ✅ 标签/分类支持“历史候选项勾选 + 手动新建”
- ✅ 标签候选项布局更紧凑，不再分散
- ✅ AI 写作升级为对话弹窗（历史、复制、清空、按条插入正文）
- ✅ AI 对话落地到项目目录 `HugoDeskStorage/ai-writing-history.json`
- ✅ 摘要字段默认手动，Front Matter 转义稳定性增强

---

## 谁最适合用？👀

- 🎯 想继续用 Hugo，但不想天天切终端的人
- 🎯 用 GitHub Pages 部署，想把排障做稳的人
- 🎯 做文档站 / 多语言站 / 结构型博客的人
- 🎯 希望“写作 + 配置 + 发布”在一个软件里完成的人

---

## 设计理念（很关键）🧠

HugoDesk 的目标不是“功能多”，而是“链路稳”：

- 不是只做编辑器，而是做 **写作到发布的完整上下文**
- 不是只做 UI，而是做 **结构一致、可落盘、可维护**
- 不是只报错，而是做 **可定位、可修复、可复现**

说白了：它不是给演示做的，是给每天真的要更新站点的人做的。📌

---

## 页面结构 🗂️

- `项目`：项目根目录、Git 远端、令牌、Hugo 工具、配置包
- `写作`：内容树、AI 写作、正文编辑、Front Matter、页面资源、引用、shortcode
- `主题设置`：主题检测、切换、参数编辑
- `AI 设置`：模型地址、模型名、API Key
- `发布`：预检、Workflow、Pages、日志、修复操作

---

## 本地运行 💻

```bash
cd /Users/sexyfeifan/Library/Mobile\ Documents/com~apple~CloudDocs/Code/HugoDesk
swift run
```

Release 构建：

```bash
swift build -c release
```

---

## 更新记录 📝

详细变更见 [CHANGELOG.md](CHANGELOG.md)
