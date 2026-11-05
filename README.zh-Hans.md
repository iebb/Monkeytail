<p align="center"><img src="docs/brand/monkeytail-banner.png" alt="Monkeytail — 适用于 iPhone、iPad 和 Mac 的 HTTP 与 cURL 工具，由 Kitta Co 出品" width="880"></p>

# Monkeytail

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · **简体中文**

**适用于 iPhone、iPad、Mac 和 visionOS 的原生请求调试工具，并配有精简的 Apple Watch 配套应用。** 导入一条命令，编辑请求，查看响应。使用 SwiftUI 构建，在 iPhone 上提供紧凑的编辑器，在桌面上提供自适应的工作区。

免费。无 App 内购买。无需账户。Kitta Co 不收集任何数据。

[产品](https://docs.kitta.co/monkeytail/) · [隐私](https://docs.kitta.co/monkeytail/privacy/) · [支持](https://docs.kitta.co/monkeytail/support/) · [API 工具](docs/APITools.md) · [脚本](docs/Scripting.md) · [浏览器配置](docs/BrowserProfiles.md) · [发布设置](docs/Release.md)

<p><img src="docs/screenshots/iphone-request.png" alt="iPhone 上的 Monkeytail 请求编辑器，带内联标头" width="285"> <img src="docs/screenshots/iphone-response.png" alt="iPhone 上的 Monkeytail JSON 响应查看器" width="285"></p>

参阅[验证结果和设备截图](docs/Verification.md)。仓库中附带可导入的[示例工作区](docs/examples)，分别适用于 Monkeytail、Postman 和 Insomnia。

## 运行

打开 **`Monkeytail.xcodeproj`**。iPhone/iPad 选择 **Monkeytail**，Mac 选择 **MonkeytailMac**，visionOS 选择 **MonkeytailVision**，Watch 配套应用选择 **MonkeytailWatch**。需要 iOS 17、macOS 14、visionOS 1 或 watchOS 10；在 Mac 上导入客户端证书需要 macOS 15。构建和验证使用 Xcode 27。在真机上运行以及构建启用 iCloud 的 Mac 版本时，请选择你的签名团队。Mac Debug 构建使用单独的沙盒权限，用于临时签名的本地测试；Release 构建启用共享的 iCloud 容器。

生成的 Xcode 项目已提交到仓库。如果你修改了 `project.yml` 中的目标设置，请使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 重新生成：

```sh
xcodegen generate
```

初始集合使用 httpbin.org。只有在你轻点 **发送** 或使用发送快捷键时才会发出请求。将 Playground 环境中的 `base_url` 替换为你自己的服务器即可使用。

## 包含的功能

- 原生请求编辑器：方法、URL、`:name` 路径变量、可启用/停用的标头和查询参数（支持 Postman 风格的批量编辑）、JSON/文本/URL 编码/multipart 正文和二进制文件上传、继承的身份验证、bearer/basic/Digest、API 密钥、OAuth 1.0 签名、JWT Bearer（HS/RS/PS/ES 256–512，每次发送时在本地签名，可放在标头或查询参数中）、带 PKCE 和刷新的 OAuth 2.0、AWS SigV4、超时、重定向。
- cURL 导入和导出，支持 shell 引号、多行命令、data、JSON、cookie、basic 和 `--digest` 身份验证以及代理选择。导入器只解析文本，从不调用 shell。
- 集合和嵌套文件夹，可继承标头、身份验证、变量和脚本；支持添加、重命名、复制、删除、搜索，并自动在本地保存。iCloud Drive 同步默认开启，使用设备现有的登录会话；无需 Monkeytail 账户。
- 命名环境、工作区全局变量，以及请求中各处的 `{{variable}}` 替换；支持嵌套变量，并检测缺失变量和循环引用，还支持 Postman 动态变量，如 `{{$guid}}`、`{{$timestamp}}` 和 `{{$randomEmail}}`。解析后的值显示在 URL 下方，输入 `{{` 时会提示可用变量。
- 集合和文件夹运行器：迭代次数、延迟、CSV/JSON 数据文件、`pm.execution.setNextRequest`/`skipRequest`、实时通过/失败结果，以及 JSON 或 JUnit 报告导出。在本地运行；无需账户或云端运行器。
- 真实的 HTTP 传输、取消、响应分享，以及逐跳的 DNS/连接/TLS/上传/服务器/下载诊断，包含传输层报告的标头和有大小上限的已发送正文。
- 可选的 [浏览器 TLS 和 HTTP/2 配置](docs/BrowserProfiles.md)，适用于 Chrome、Firefox 和 Safari，在 iOS 和 Mac 上还包括 iOS 和 Android 预设。visionOS 使用系统 TLS，因为固定版本的浏览器库没有 visionOS 架构切片。使用固定版本的 curl-impersonate 在本地运行；证书验证保持开启。
- JSON 美化输出、核心库中的压缩、语法着色、可展开的树视图、按行搜索、复制，以及请求正文格式化。
- 根据 MIME 类型显示图像预览并支持双指缩放，原生音频/视频播放，以及带偏移量/ASCII 的十六进制和二进制查看器。不支持的媒体可以按字节查看或保存。
- 本地 JavaScript 请求前和响应后钩子，提供与 Postman 兼容的 `pm` 子集：Chai 风格的 `pm.expect`、`pm.response.to.*`、`pm.sendRequest`、环境/集合/全局变量、cookie、内置的 CryptoJS、lodash 和 moment 子集，以及控制台日志。脚本在每次发送时运行，包括导入的脚本。
- 系统网络或自定义的 HTTP CONNECT、TLS 包装的 HTTPS CONNECT 和 SOCKS5 代理，可选凭据；自定义代理失败时不会回退到直连。
- OpenAPI/Swagger JSON 和 YAML 导入，提供参数提示、示例和可移植的 JSON Schema 验证。
- GraphQL 查询/变量/操作编辑、内省，以及可搜索的 schema 字段建议。
- WebSocket 和 SSE 时间线，支持文本/JSON/二进制查看、过滤、ping、取消和重新连接。
- 按环境区分的设备本地 cookie 存储、精确匹配主机的 PKCS#12 客户端身份，以及针对自签名证书的按主机信任（通过 SHA-256 指纹固定，而不是关闭验证）。系统传输诊断会显示证书链、有效期、协商的 TLS/加密套件标识和协议。
- 可视化的状态/时间/标头/JSONPath/schema 断言、通过/失败结果，以及可编辑的 JavaScript 检查。
- 代码片段，支持 cURL、JavaScript fetch、Node.js axios、Python requests、Go、Java HttpClient、C# HttpClient、PHP cURL、Ruby Net::HTTP、Swift URLSession、Kotlin OkHttp、HTTPie 和 PowerShell，可选隐藏凭据。
- 每个请求可保存响应示例（Postman `response` 示例），可基于示例、当前响应或快照提供离线响应模拟，支持延迟/状态/错误，并提供前台运行的本地回环模拟服务器。
- Mac 和 iPad 上的请求标签页（重新启动后恢复），请求、文件夹和集合的 Markdown 文档，以及沙盒化的 HTML 响应预览。
- 从 Postman（v1、v2/v2.1 集合、环境、全局变量和完整数据转储）、Insomnia（v4 JSON/YAML 和 v5 YAML）、Bruno（`.bru` 文件夹和 JSON 导出）、Hoppscotch、Thunder Client、HAR、VS Code REST Client/JetBrains `.http` 文件、OpenAPI 和 cURL 导入。可以一次选择多个文件或整个文件夹。
- 直接从其他应用导入：以与 Postman、Insomnia 或 Hoppscotch 自家应用相同的方式登录并拉取已同步的集合，或连接 GitHub 仓库。所有集合、环境和全局变量都会导入。会话和令牌仅用于本次导入，从不保存；Monkeytail 依然没有账户。
- Postman v2.1 集合导出和 Insomnia v4 JSON 导出。当前版本的 Insomnia 可以导入这种旧格式。
- 完整保真的 Monkeytail 工作区 JSON 导入/导出、“文件”App 集成和系统共享面板。
- 已保存的响应快照，支持搜索、JSON/状态/标头比较和 JSONPath 提取（`$`、键、索引、通配符）。快照保存在本地，最多保留 50 条，总大小不超过 60 MB。
- 历史记录中保留最近 50 个请求定义，包含状态和耗时；恢复时不会自动重新发送。
- 浅色/深色外观、动态字体、VoiceOver 标签、硬件键盘发送快捷键（⌘↵），以及自适应的竖屏/横屏布局。

## 设备布局

边栏的用法与 Postman 相同：顶部是工作区切换器，下面是该工作区中的所有集合，以嵌套文件夹和请求构成的树形结构显示。每个工作区都有自己的集合、环境和全局变量，现有数据位于 **我的工作区** 中。使用 **移到** 或拖动来移动请求和文件夹，并可通过 **+** 或任意集合、文件夹、请求的菜单添加文件夹。界面提供英语、西班牙语、法语、日语、韩语和简体中文，并跟随设备语言。

颜色默认遵循设计系统。**设置 → 主题与字体** 提供六种预设（Monkeytail、Navy、Ocean、Ember、Grape、Graphite）、系统/浅色/深色外观，以及按角色分别设置的浅色和深色颜色，涵盖强调色、画布、表面、警告、危险、信息、其他方法和错误。你还可以从设备已安装的字体中分别选择界面字体和代码字体。主题保存在设备上，并立即应用到所有窗口。

iPhone 布局会让方法和 URL 始终显示在紧凑编辑器的上方。**发送/取消** 和 **请求/响应** 位于底部，拇指即可触及，编辑时会移到键盘上方。标头和参数的名称与值共用一行，控件尺寸为 44 点。在手机上输入搜索内容时，响应标签页会收起，使匹配的行保持在键盘上方可见。可选的帮助默认收起，请求名称可以直接在导航栏中编辑。cURL 分享位于操作菜单中。

布局取决于 **可用窗口大小**：

| 可用空间 | 布局 |
| --- | --- |
| 窄屏手机 / 折叠后的窗口 | 底部为请求/响应切换；通过返回/边栏按钮访问集合 |
| iPad 详细区域至少 640 × 440 点 | 请求和响应并排显示 |
| 高度较小的横屏手机窗口 | 单栏，以保证编辑器可用 |
| 窗口宽度至少 1,100 点 | 集合边栏加上请求和响应面板 |
| 可折叠设备半开，折痕横贯屏幕（桌面模式） | 响应在铰链上方；URL、发送按钮和请求编辑器在铰链下方。没有内容跨越折痕 |
| 辅助功能文字大小 | 单栏编辑器，以保持文字可读 |

选择状态和编辑器状态在宽度变化、旋转、iPad 窗口调整大小以及可折叠设备尺寸变化时都会保留。在 iOS 27.1 及更高版本中，桌面模式布局遵循 `UIHingeInteraction`（部分打开）和系统的 `.division` 保留区域，因此分割线正好位于系统报告的折痕上，两侧各留 7 点间距。如果铰链展平或合上，或折痕不是水平方向，则使用常规布局。

## Apple Watch 配套应用

在 iPhone 的操作菜单中为请求加星标。打开 **Apple Watch**，轻点一个收藏项将其复制，然后在配对的应用已安装时轻点 **同步**。Watch 最多列出十个副本：打开其中一个并轻点 **发送** 或 **取消**，然后查看状态、耗时、标头，或以 Pretty/Raw/Hex 文本查看。Watch 上没有请求编辑器，也不会自动轮询。

复制时会解析所选环境以及继承的标头/身份验证。**包含凭据和正文** 是一个会保存的选项，除非你将其关闭，否则保持开启。副本默认使用本地文件，也可选择存储在钥匙串中，并使用 WatchConnectivity 的最新应用上下文。编辑请求或更换环境后需要重新复制；同步会移除不再是收藏项的副本。Watch 会自行发出 HTTP 请求，因此服务器必须能从 Watch 访问。响应仅保存在内存中。在实际配对的设备之间传输仍需硬件验证。

Watch 支持系统 HTTP/GraphQL、经过验证的 HTTPS，以及手动设置的 basic/bearer/API 密钥标头。代理、浏览器 TLS 预设、客户端身份、cookie、OAuth/JWT/AWS、脚本、模拟、WebSocket 和 SSE 仍只在完整应用中提供。不支持的配置会在复制前报错。超时最长 30 秒，复制的正文最大 32 KB，传输最大 60 KB，响应最大 256 KB，显示的正文最大 16 KB。

visionOS 窗口与 iPhone 和 Mac 共用完整的工作区编辑器、响应查看器、API 工具和 iCloud 容器。在 visionOS 上请选择系统 TLS；那里不提供浏览器 TLS 预设。仅系统传输的 Swift 包和 Watch Swift 包通过已提交的符号链接引用规范源代码，避免在不支持的平台上链接 iOS/Mac 的 curl 二进制文件。

1.4 版本已在 iPhone/iPad（含 Watch 配套应用）、Mac 和 visionOS 上提供。1.5 版本正在三个平台上等待 App 审核。构建和验证详情请参阅[发布记录](docs/app-store/README.md)。实际配对 Watch 之间的传输和实时 iCloud 传输尚未验证。

在 Mac 上，请求和响应默认以可调整大小的分割视图上下排列。选择 **工作区操作 → 工作区布局** 可将它们并排显示；每种布局都会记住各自的分割位置。调整窗口大小时，边栏会保持打开，直到你将其隐藏。设置在原生的设置窗口中打开。使用 ⌘F 查找请求，⇧⌘I 导入/导出，⇧⌘E 导出 cURL，⌘N 新建请求，⌘Return 发送或取消。

## 互通范围

Monkeytail 工作区 JSON 会保留所有模型字段、环境和代理设置。导入会追加集合和环境并生成新的 ID；原生导入还会应用其中保存的代理设置。与 Postman 一样，导入的脚本会在发送时运行；请在各个“脚本”标签页中检查它们，或关闭 **运行脚本** 以跳过。

Postman 导出会保留嵌套文件夹，并将 **当前环境** 导出为集合变量。Postman 导入会保留文件夹层级以及继承的标头、身份验证、变量和脚本。支持 raw、URL 编码、multipart、文件和 GraphQL JSON 正文。脚本会被保留；执行时支持的 API 见[脚本](docs/Scripting.md)。

Insomnia v4 JSON/YAML 导出和 v5 YAML 集合会连同文件夹树一起导入。基础环境变为集合变量，子环境变为环境，文件夹环境、标头、身份验证和脚本变为文件夹默认值。`{{ _.variable }}` 和 `{{ _['variable'] }}` 引用会被规范化。模板标签（例如响应链）会产生提示并保留为文本；gRPC 请求会被跳过。

Bruno 集合文件夹（`bruno.json`、`collection.bru`、`folder.bru`、`environments/`）和 JSON 导出会保留文件夹、默认值、机密环境变量、脚本和断言（转换为测试）。Hoppscotch 集合和环境会转换 `<<variable>>` 引用，并保留所有身份验证类型。Thunder Client 集合中的声明式测试会转换为脚本。HAR 文件会按主机对请求分组，并将录制的响应保留为已保存的示例。`.http`/`.rest` 文件会保留 `@variables`、`# @name`、正文和 `> {% %}` 响应处理程序。为这些客户端编写的导入脚本会借助兼容对象运行；参阅[脚本](docs/Scripting.md#other-clients)。

导入 → **从 Postman、Insomnia、Hoppscotch 或 GitHub 导入**：

- **Postman：** Monkeytail 以与 Postman 桌面应用相同的方式登录。**登录 Postman** 会在私密浏览器会话中显示 Postman 自己的登录页面（电子邮件和密码、GitHub 或 SSO），并从最终的重定向中读取会话。随后 Monkeytail 通过 Postman 的网关列出你的工作区，并从 Postman 的同步服务中拉取所选每个工作区的集合、环境和全局变量，采用桌面应用存储的 v1 格式。美国和欧盟账户均受支持。导入多个工作区时，环境名称会加上工作区名称作为前缀。
- **Insomnia：** Monkeytail 以与 Insomnia 桌面应用相同的方式登录。**登录 Insomnia** 会使用一次性密钥打开 Insomnia 网站；粘贴网站上显示的代码即可。Monkeytail 会打开加密的登录数据包，解锁账户的端到端加密密钥，列出每个组织的 Cloud Sync 项目，并拉取所选每个项目默认分支的最新快照。文档在设备上解密。本地项目和 Git Sync 项目不在 Insomnia 云端；请使用 GitHub 选项或导出文件。
- **Hoppscotch：** 输入你的电子邮件地址以接收登录链接，然后粘贴该链接，不要打开它。在 hoppscotch.io 上，这对应 Web 应用的电子邮件链接登录；在自托管服务器上（输入其后端 URL），这对应桌面应用的魔法链接。个人集合和环境、全局变量以及每个团队的集合和环境都会导入；团队环境会加上团队名称作为前缀。
- **GitHub：** 输入 `owner/repo`、`owner/repo@branch` 或文件夹 URL（`…/tree/branch/folder`）。所有 Postman、Insomnia Git Sync、Bruno、Thunder Client、Hoppscotch、`.http`、HAR 和 OpenAPI 文件都会导入，每个 Bruno 集合都会相对于其自身的 `bruno.json` 解析。公开仓库无需令牌；私有仓库请使用只读的细粒度令牌。最多导入 1,000 个文件和 40 MB 数据。

Bruno 和 Thunder Client 将集合存储为文件或存放在 Git 中。凭据和会话只会通过临时会话发送到所选服务，不使用 cookie 或缓存，并在导入后丢弃。

第三方格式不会保留所有 Monkeytail 设置，例如请求超时或全局代理选择。不支持的身份验证会产生导入提示；不支持的 cURL 标志会产生明确的错误。导入的文件路径仅作为元数据：发送前请使用“文件”或“照片”逐个选择文件。原生工作区导出包含文件字节；Postman/Insomnia/cURL 导出只引用文件名。使用 正文 → 导出文件 可在第三方导出旁一并传输实际的附件。gRPC、账户和团队工作区、云端监控/模拟以及其他客户端的完整脚本运行时不在此版本范围内；Monkeytail 从不要求登录。OpenAPI 导入和 JSON Schema 验证有明确支持的子集；参阅 [API 工具](docs/APITools.md)。

浏览器配置可通过原生 JSON 和 `curl-impersonate --impersonate` 命令往返转换。Postman 和 Insomnia 导出会携带 `_monkeytail` 元数据，以便重新导入 Monkeytail；这些应用本身不会应用浏览器配置。

## 数据与网络

工作区和历史记录存放在应用的 Application Support 目录中，使用平台的文件保护以及 Mac 应用沙盒。工作区凭据和历史记录默认使用本地文件。**使用钥匙串** 是可选项，适用于工作区凭据、cookie、客户端身份和 Watch 副本。关闭该选项时，启动时不会查询钥匙串。钥匙串中的旧值保持不变，开启该选项即可恢复；导出包含已保存的值。没有分析功能，也没有由 Kitta 运营的后端。iCloud Drive 同步默认开启，1.6.3 版本会为现有安装开启一次（在设置中关闭 **iCloud 同步** 即可只保留在本地），并在你的设备之间共享集合、环境、脚本和凭据，按每个实体的最新编辑合并，并保留删除标记。对不同请求的编辑在并发修改时都会保留；同一实体以最新编辑为准。应用远程更改前会保留一份受保护的本地恢复副本。应用离线时仍可使用，并在活跃期间和切换到前台时检查同步。**包含凭据** 控制身份验证和凭据字段是否参与 iCloud 同步；除非你将其关闭，否则保持开启，因此默认同步所有内容。cookie、客户端身份、附件、快照和请求历史记录仍保留在本地。`Authorization` 或 `X-API-Key` 等字段不会被自动标记为敏感，并保持可见；**标记为敏感** 可遮盖某个值。当 **包含凭据** 关闭、**使用钥匙串** 开启或代码隐藏开启时，类似凭据的名称仍会受到保护，除非标记为普通。导入或同步的脚本需要在每台设备上单独选择启用。切换设备的 iCloud 账户后，需要关闭再开启同步。响应正文保存在内存中，直到明确保存为快照或导出；音频/视频预览使用受保护的临时文件，并在其缓存的响应释放时删除。中断的会话遗留的文件会在一天后的启动时清理。明确保存时会导出原始字节。cookie 需按请求选择启用，每个环境都有单独的设备本地存储。会话从不使用 Safari 的 cookie。OAuth 会在临时浏览器会话中打开提供方页面；它不会创建 Monkeytail 账户。客户端身份保留在设备本地，存储在文件或可选的钥匙串中。模拟服务器只绑定到 127.0.0.1，并在应用进入后台时停止。TLS 信任验证保持开启；需要时请在 iOS 设置中安装并信任调试用 CA。ATS 允许 HTTP，因为本应用是通用的 API/调试客户端。

响应大小上限为 20 MB；文本/树视图和字节预览上限为 1 MB。图像解码为最大 2,048 像素的预览；保存时保留原图。音频/视频播放只使用已下载的文件，并禁用外部媒体引用。JSON 格式化、树视图准备和分行都在主线程之外运行。文本行和树视图行按需渲染，搜索时复用行数组，语法高亮使用一个预编译的表达式，并对长行设置长度上限。响应缓存最多保留 8 个响应，总大小不超过 40 MB。导入上限为 40 MB；上传上限为 20 MB；iCloud 元数据上限为 20 MB。JSONPath 和 JSON 差异比较适用于不超过 2 MB 的正文，并有节点/变更数量限制。JavaScript 上下文的时限为三秒，使用临时 WebKit 数据存储，并阻止直接的网络访问/DOM 导航。其唯一的原生桥接是 `pm.sendRequest`，每个脚本最多通过所选代理发送 10 个 HTTP(S) 请求；没有文件或应用桥接。超时的上下文会被丢弃。脚本是便利性 API，而不是通用的 Node.js 运行时。

## 验证

纯模型、解析器、集合、编码、JSON、代理配置、multipart、同步合并/删除标记/机密、JSONPath 和响应比较测试：

```sh
swift test
```

模拟器集成测试和 UI 测试使用本地 HTTP、TLS/HTTP2、CONNECT 和 SOCKS5 测试夹具，不依赖任何公共 API：

```sh
./Scripts/test.sh 'platform=iOS Simulator,name=iPhone Duo'
# Or pass another installed simulator destination, e.g.:
./Scripts/test.sh 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0'
```

测试套件验证传输、线路上的 TLS ClientHello 和 HTTP/2 SETTINGS、证书拒绝、浏览器标头覆盖、重定向、跨源时移除凭据、取消、各项限制、两种代理协议、脚本的修改/断言/错误/超时/网络阻止、钥匙串持久化、快照淘汰、两种传输方式下的 multipart/二进制上传、逐跳诊断，以及竖屏和横屏下“发送 → 查看 → 导入 → 编辑 → cURL 导出”的 UI 流程。UI 测试使用隔离的临时工作区，不会更改用户的常规集合。

## 项目结构

```text
Sources/MonkeytailCore/  Codable models, request builder, HTTP transport, cURL,
                        collection codecs, JSON formatting/tree
Sources/MonkeytailCurl/  Small C bridge for the static browser transport
Vendor/                 Pinned curl-impersonate XCFramework and provenance
Monkeytail/Services/    Observable workspace/persistence and WebKit script runner
Monkeytail/Views/       Native adaptive SwiftUI interface
Tests/                 Core Swift package tests
MonkeytailMac/         Mac sandbox/iCloud entitlements and app metadata
MonkeytailMacTests/    Shared advanced hosted integration tests
MonkeytailVision/      Native visionOS app and shared iCloud entitlements
MonkeytailWatch/       Compact favourite-request companion and WatchConnectivity
Packages/              System-only visionOS and bounded Watch core packages
MonkeytailTests/       Hosted simulator integration tests
MonkeytailUITests/     End-to-end device UI tests
Scripts/               Local verification and network fixtures, samples, icon packaging
docs/                  Scripting, release metadata, branding, screenshots
```

协议参考：[Apple 代理配置](https://developer.apple.com/documentation/network/proxyconfiguration)、[WebKit JavaScript 执行](https://developer.apple.com/documentation/webkit/wkwebview/callasyncjavascript(_:arguments:in:in:completionhandler:))、[Postman schema](https://schema.postman.com/)、[Insomnia 导入/导出](https://developer.konghq.com/insomnia/import-export/)。

## 许可证

基于 [BSD 3-Clause 许可证](LICENSE) 发布。公开的产品、支持和隐私页面托管在 [docs.kitta.co](https://docs.kitta.co/monkeytail/)。

第三方组件保留各自的许可证；其声明包含在 设置 → 许可 中。固定版本的二进制文件及其重新生成步骤见[供应商来源说明](Vendor/README.md)。
