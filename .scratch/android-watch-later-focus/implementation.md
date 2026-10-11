# Android 稍后再看专注模式：实施与验证记录

Implemented: 2026-10-11
Spec: [Android 稍后再看专注模式规格](android-watch-later-focus-spec.md)

## 已实现的行为

- Android 冷启动进入稍后再看首页。未登录时使用原有登录页；登录后将该账号用于队列和播放，首页保留退出账号入口。
- 从主账号读取稍后再看，固定为最早添加优先、全部观看状态；首页只保留并展示队首，不提供排序、筛选、跳过、完整队列或添加入口。
- 点击播放使用现有原生播放器，保留标题、UP 主名称、播放控制、字幕、弹幕观看、合集及分 P 选集。关闭评论、相关推荐、社交操作、下载入口和其他浏览跳转。
- 合集和分 P 内支持手动切换及自动续播，末尾停止。Android 固定使用顺序播放，旧循环偏好与设置不能恢复跨队列、相关推荐或循环播放。
- “完成”仅在首页出现，移除最初打开的队列项。切换合集中的其他集不会改变完成对象；播放结束和进度上报不会移除队列项。
- 完成请求期间防止重复提交。远端移除失败保留当前项目并提示重试；移除成功后重新读取第一页，避免删除造成分页位移而漏项。若移除成功但读取失败，只允许重试读取，不重复删除旧项。
- 队列读取、移除和异步播放导航绑定触发时的账号；退出或切换账号后，迟到的旧响应不会覆盖新首页会话。
- 设置只开放音视频、播放器和相关外观设置。Android 路由只保留首页、登录、播放及相关设置；移除内容链接 intent filter、启动器快捷入口，并关闭运行时内容 scheme 路由。
- 继续保留原工程的其他平台流程、无关源码及依赖。没有新增后端、本地独立队列或数据库迁移。

## 主要实现位置

| 文件 | 用途 |
| --- | --- |
| `lib/utils/watch_later_focus.dart` | Android 固定生效的精简策略 |
| `lib/pages/later/focus_queue.dart` | 队首读取、移除、失败重试和会话隔离；统一可替换的队列数据边界 |
| `lib/pages/later/focus_view.dart` | 单视频首页、原有登录与播放入口、完成及退出账号 |
| `lib/pages/setting/focus_view.dart`、`lib/pages/setting/common_setting.dart` | 设置入口及可访问设置过滤 |
| `lib/router/app_pages.dart`、`lib/utils/app_scheme.dart`、`android/app/src/main/AndroidManifest.xml` | Android 导航及外部链接入口收窄 |
| `lib/pages/video/`、`lib/plugin/pl_player/controller.dart`、`lib/utils/storage_pref.dart` | 播放页精简、选集保留与连播边界 |
| `lib/http/user.dart`、`lib/pages/login/controller.dart`、`lib/utils/page_utils.dart` | 捕获请求账号、复用登录、阻止旧会话导航 |
| `test/pages/later/focus_flow_test.dart` | 首页与队列的自动化流程验证 |

## 自动化验证

通过项目隔离环境运行：

```powershell
.\tool\dev.ps1 test
.\tool\dev.ps1 analyze --no-fatal-infos
.\tool\dev.ps1 build
```

- 全部 **9 项测试通过**：新增 7 项专注模式测试，以及原有 2 项账号删除生命周期测试。
- 覆盖唯一队首、最早添加排序、已看完项目仍参与排队、滚动及窗口尺寸变化、播放返回后完成原项目、重复提交与移除失败重试、移除成功但读取失败、25 项队列跨页推进、空状态、账号变化与迟到响应，以及旧偏好和内容链接策略。
- 测试通过统一的假队列数据源控制读写结果，不依赖真实账号或网络，不删除真实账号数据。
- 静态分析没有错误或警告，剩余 **37 条 info** 与开发环境准备时的原项目基线一致；没有新增分析提示。
- 正式 `lib/main.dart` 入口的 Android Debug APK 构建成功。`pubspec.lock` 无变更，`git diff --check` 通过。

## Android 模拟器运行验证

环境：Android 15 / API 35，`PiliMinus_API35` AVD，项目现有原生媒体引擎。

- 正式 APK 安装成功，冷启动进入真实的未登录稍后再看首页；原有密码、短信、二维码和 Cookie 登录入口可打开。
- 设置首页仅提供音视频、播放器、外观三类入口。
- Android HTTPS B 站内容链接解析到浏览器；`bilibili://video/...` 没有可处理活动。正式 APK 的 crash 日志无记录。
- 使用临时验证入口，把内存队首接入实际首页和实际播放器，在匿名状态下播放公开视频；没有读取或修改真实账号的稍后再看。最终安装包已重新用正式入口构建并安装，临时验证入口已删除。
- 合集视频 `BV1xTpG6iEbV`：实际原生播放成功，21 集选集保留，手动切集成功。第一集播放结束后自动进入第二集，切到最后一集后不再推进。
- 多 P 视频 `BV1wD4y1o7AS`：实际原生播放成功，200 个分 P 选集保留。第一 P 播放结束后自动进入第二 P，最后一 P 后不再推进。横屏布局、标题、UP 主名称、选集和播放控制显示正常。
- 验证入口预存旧的列表循环偏好，实际播放器仍使用顺序播放；评论和相关推荐关闭，发弹幕与恢复循环模式的入口隐藏。

本地验证日志和截图保存在被忽略的 `.fvm/focus-*` 文件中。原生验证日志只保留检查结果标记，避免在记录中复制临时媒体签名 URL。

## 安装包与开发命令

可安装的验证包：`build/app/outputs/flutter-apk/app-debug.apk`。这是 Debug 通用 APK，复用原项目包名和图标；本次没有做发布签名、品牌调整或安装包瘦身。

Release 通用包使用 `.\tool\dev.ps1 flutter build apk --release --no-pub` 构建，输出为 `build/app/outputs/flutter-apk/app-release.apk`。当前机器没有配置独立发布密钥，沿用项目的 Android 调试密钥回退签名；Release 编译模式与签名身份是两项独立配置。安装包及本地构建元数据属于忽略的构建产物，不提交到 Git。

开发环境及补丁使用方式见 [开发说明](../../docs/development.md)。重新构建使用上述命令，连接 Android 设备后可执行：

```powershell
.\tool\dev.ps1 devices
.\tool\dev.ps1 run -d <device-id>
```

## 尚需真实设备与账号验收

本次没有使用实体 Android 手机或真实 B 站账号，因此以下结果不能用模拟器及假队列测试替代：

1. 各种登录方式实际登录成功，以及退出后再次登录的完整交互。
2. 在官方客户端添加视频后刷新本应用，以及完成后在官方客户端确认远端移除。
3. 实体设备上的画质、音频、字幕、弹幕、全屏与横竖屏体验；会员、番剧／课程等账号或权限相关的视频类型。
4. 真实网络断开及服务端异常时的界面和重试行为。

实现与上述自动化、模拟器验证已经完成；这些真实设备和服务端检查保留为安装后的验收事项。
