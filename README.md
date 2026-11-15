# 书读 iReader

**书读**（英文名 iReader）是一个仿微信读书界面的 iOS 阅读器，内置 **Legado / 阅读 3.0 书源规则引擎**，可直接导入书源 JSON，搜索、加书架、看目录、读正文。

> 由于当前交付环境是 Linux，没有 Xcode 与 Apple 签名证书，**无法直接生成可安装的 .ipa 二进制**。这里给的是完整、可直接编译的 Xcode 工程 + 一键打包脚本，你在 Mac 上（或 GitHub Actions 云端）跑一次就能得到 ipa。

---

## 一、三种拿到 ipa 的方式

| 方式 | 需要 | 产出 | 适合 |
|---|---|---|---|
| **A. Xcode 直接跑** | Mac + Xcode 15 | 装到真机 / 模拟器 | 想改代码、调试 |
| **B. 脚本打包** | Mac + Xcode 15 | 已签名 ipa 或未签名 ipa | 一次成型 |
| **C. GitHub Actions** | 一个 GitHub 仓库 | 未签名 ipa（Artifact 下载） | 没有 Mac |

### A. Xcode

```bash
open WeReadLike.xcodeproj
```

1. 选中 `WeReadLike` target → **Signing & Capabilities**
2. 勾选 *Automatically manage signing*，Team 选你的 Apple ID（免费账号也行，7 天有效期）
3. 改一个独一无二的 Bundle Identifier（默认 `com.yuejie.reader` 可能已被占用）
4. 选真机 → `⌘R`

免费账号签名需要在 iPhone 上信任证书：设置 → 通用 → VPN与设备管理 → 信任。

### B. 脚本打包

```bash
chmod +x build_ipa.sh

# 未签名（给 TrollStore / Sideloadly / Esign 用）
./build_ipa.sh

# 有开发者账号，产出可直接安装的 ipa
TEAM_ID=你的10位TeamID ./build_ipa.sh
```

产物在 `build/` 目录。

### C. GitHub Actions（无 Mac）

把整个目录推到 GitHub 仓库，`.github/workflows/build.yml` 会自动在 macOS 机器上编译，在 Actions 页面的 **Artifacts** 里下载 `iReader-ipa.zip`，解压得到 `iReader-unsigned.ipa`。

未签名 ipa 安装途径：

- **TrollStore**：iOS 14.0–16.6.1 / 17.0 部分版本，直接安装，无需证书
- **Sideloadly / AltStore / Esign**：用你自己的 Apple ID 自签，免费账号 7 天需重签
- 有企业/开发者证书：用 `build_ipa.sh` 的签名模式，或 Xcode → Product → Archive → Distribute

---

## 二、iPhone Duo 适配

iPhone Duo 是 2026 年 10 月开售的折叠屏，运行 iOS 27.1。Apple 把 App 在 Duo 上的表现分成三档，分水岭是**编译时用的 SDK**：

| 构建 SDK | Duo 上的表现 |
|---|---|
| iOS 26 及更早 | 居中显示、四周大片黑边，系统层面不知道有这块屏 |
| iOS 27 | 填满内屏大部分区域，但标签栏仍在底部，右侧状态栏位置空着 |
| iOS 27.1 | 铺满全屏，标签栏 / 工具栏自动移到右侧竖排 |

本工程已做的适配（**与 SDK 无关，任何档位都生效**）：

- 导航按**窗口宽度**切换形态：≥ 700pt 用左侧竖排侧栏，否则底部标签栏。不用屏幕尺寸判断，折叠展开、分屏、旋转都能正确响应
- 书架列数随可用宽度自适应（手机 3 列，内屏 5–8 列）
- 正文限宽 760pt、详情页限宽 980pt 并居中，避免宽屏长行
- 放开 iPhone 横屏（原工程锁竖屏，展开内屏必然横屏）
- 全工程不使用 `UIScreen.main.bounds`，也不按 orientation 分支判断布局

**构建 SDK 现状**：GitHub 托管运行器（`macos-26` 镜像）当前最高只有 Xcode 26.6 / iOS 26.5 SDK，没有 27.1（`macos-27` 镜像尚无运行器）。等镜像更新后，在 Actions → Run workflow 把 `xcode` 填 `27.1` 即可；本地有 Xcode 27.1 时直接 `./build_ipa.sh`。

## 三、界面：对齐微信读书

| 页面 | 实现要点 |
|---|---|
| **书架** | 三列封面网格、书名两行截断、进度小字、顶部搜索 + 更多、分组筛选条、左滑/长按菜单 |
| **发现** | 胶囊搜索框、搜索历史标签流、书源入口卡片 |
| **详情** | 悬浮返回/更多按钮、大封面 + 书名作者、蓝色胶囊「阅读」、简介展开收起、目录预览 |
| **阅读器** | 米黄护眼底、正文可调字号行距、点击呼出上下菜单、底部章节进度条、目录抽屉、四种背景（白/米黄/护眼/夜间）、左右滑动切章、章末上一章/下一章 |
| **书源管理** | 名称 + 域名 + 开关、滑动删除、搜索过滤、三种导入方式 |

配色取自微信读书的克制风格：主色 `#1E7BE0`，背景 `#F7F7F7`，正文深灰 `#1B1B1B`，阅读底色 `#F6F0E0`。

---

## 四、导入书源

三个入口，效果一致：

1. **我 → 书源管理 → 右上 +** → 从链接导入 / 粘贴 JSON / 从文件导入
2. **发现 → 书源卡片**
3. 书架空状态下的「导入书源」按钮

支持的格式：

```jsonc
// 1. 标准数组（阅读 3.0 导出格式）
[ { "bookSourceUrl": "...", "bookSourceName": "...", "ruleSearch": {...} } ]

// 2. 带包裹
{ "bookSources": [ ... ] }

// 3. 单个对象
{ "bookSourceUrl": "...", ... }

// 4. 混杂说明文字的文本（自动截取 [ ... ] 片段）
```

导入时按 `bookSourceUrl` 去重，重复的会更新规则但保留原有启用状态。

---

## 五、规则引擎支持范围

`RuleEngine.swift` 自己实现了 Legado 规则的解析，**零第三方依赖**（HTML 解析器、CSS 选择器、XPath 子集、JSONPath 都是手写的）。

| 能力 | 状态 |
|---|---|
| `@css:` CSS 选择器 | ✅ 标签 / `.class` / `#id` / `[attr=val]` / `[attr*=val]` / `[attr^=]` / `[attr$=]` / 后代 / `>` / `+` / `~` / `:first-child` / `:nth-child(n)` / `:not(.x)` / 逗号分组 |
| `@xpath:` | ✅ `//tag`、`/tag`、`[@a='b']`、`[contains(@a,'b')]`、`[n]`、`/text()`、`/@attr` |
| `@json:` JSONPath | ✅ `$.a.b[*].c`、`$..name`、数组下标 |
| 默认 HTML 规则 | ✅ `class.x`、`id.x`、`tag.li`、`tag.li.0`、`text`、`ownText`、`html`、`children`、`@attr` |
| `@` 多级串联 | ✅ `class.list@tag.li@tag.a@href` |
| `{{ }}` 内联 JS | ✅ 基于 JavaScriptCore，绑定了 `baseUrl` / `key` / `page` |
| `##` 正则替换 | ✅ `rule##pattern##replacement` |
| `&&` / `||` | ✅ 并 / 或 |
| POST 搜索 | ✅ `url,{"method":"POST","body":"..."}` |
| 目录翻页 | ✅ `nextTocUrl`，最多 12 页 |
| 正文翻页 | ✅ `nextContentUrl`，最多 6 页 |
| 编码识别 | ✅ UTF-8 / GBK / GB18030 / Big5 / meta charset |
| Cookie | ✅ 按域名保存并自动回传 |
| 请求头 | ✅ `header` 字段，JSON 或 `Key: Value` 换行格式 |

**未实现**：`{{ }}` 之外的书源 JS 全流程（如 `webJs`、登录态脚本）、WebView 正文嗅探、TTS、换源、本地导入 TXT/EPUB。

---

## 六、目录结构

```
iReader/
├── WeReadLike.xcodeproj          # 工程文件（工程/目标名沿用 WeReadLike，产物为 iReader.app）
├── WeReadLike/
│   ├── WeReadLikeApp.swift       # 入口
│   ├── Models.swift              # 书源/书籍/章节模型，容错 JSON 解码
│   ├── Theme.swift               # 配色、封面组件、阅读主题
│   ├── HTMLParser.swift          # HTML 解析 + CSS/XPath/JSONPath
│   ├── RuleEngine.swift          # Legado 规则执行器
│   ├── HTTPClient.swift          # 网络层、编码识别、Cookie
│   ├── BookSourceService.swift   # 搜索/详情/目录/正文
│   ├── LibraryStore.swift        # 书架、书源、进度、正文缓存
│   ├── RootTabView.swift         # 底部 Tab + 「我」
│   ├── BookshelfView.swift
│   ├── DiscoverView.swift        # 发现 + 搜索
│   ├── BookDetailView.swift      # 详情 + 目录面板
│   ├── ReaderView.swift          # 阅读器
│   ├── SourceManagerView.swift   # 书源管理 + 三种导入
│   ├── Assets.xcassets           # AppIcon
│   └── Info.plist                # 允许 HTTP（书源多为 http）
├── build_ipa.sh
├── project.yml                   # XcodeGen 备用
└── .github/workflows/build.yml
```

技术栈：SwiftUI + async/await + URLSession + JavaScriptCore，最低 iOS 16.0，无 SPM 依赖。

---

## 七、数据存在哪

全部本地，不上传任何服务器：

- 书架：`Documents/books.json`
- 书源：`Documents/sources.json`
- 阅读设置：`Documents/settings.json`
- 正文缓存：`Documents/chapter_cache/<sha256>.txt`（读过的章节离线可看）

---

## 八、常见问题

**Q：搜索一直转圈没结果？**
A：多半是书源本身失效。Legado 的书源跟网站改版强相关，找新书源或换一个源试。可以先把书源数量减到 1–2 个排查（每个源并发请求，太多会被限流）。

**Q：目录拿得到，正文是空的？**
A：正文规则不匹配。在书源管理里确认该源的 `ruleContent.content`；程序有兜底（`#content`、`.content`、`article` 等常见容器），兜不住就是规则问题。

**Q：编译报 Bundle Identifier 冲突？**
A：改 `Signing & Capabilities` 里的 Bundle ID，随便加个后缀。

**Q：`.xcodeproj` 打不开？**
A：用手写的工程文件偶发版本不兼容。装 `xcodegen` 后执行 `xcodegen generate` 会重新生成一份（配置见 `project.yml`）。

**Q：能上架 App Store 吗？**
A：不能。抓取第三方网页内容 + 动态加载书源规则，过不了审核。仅限自用或内部分发。

---

## 九、说明

本项目是一个**阅读器客户端 + 规则引擎**，不内置、不分发任何书源，也不附带任何书籍内容。请只对你有权访问的内容使用它（例如自建博客、已授权的付费内容、公共领域作品），并遵守目标站点的服务条款与当地法律。
