# Android 开发环境

本项目第一阶段仅开发 Android。使用项目专用 Flutter SDK 和依赖缓存，复用上游的 Android 补丁与锁定依赖。

## 工具要求

| 工具 | 要求 |
| --- | --- |
| Flutter | 3.47.7，与项目版本配置一致 |
| Dart | 使用上述 Flutter 自带的 SDK，满足项目要求的 3.13.0 及以上版本 |
| Git | 已加入 PATH，能够读取公开 GitHub 依赖 |
| Android SDK | Android API 37；插件构建还可能需要 API 36 |
| Android Build Tools | 由 Android 构建工具按项目要求选择并安装 |
| Android NDK | 使用 Flutter 指定的 28.2.13676358 |
| JDK | 使用 Android Studio 自带的 JDK；项目 Java／Kotlin 源码目标为 Java 17 |
| Android 许可证 | 通过 Flutter doctor 确认已经接受 |

## 初始化

在项目根目录的 PowerShell 中运行：

```powershell
.\tool\dev.ps1 setup
.\tool\dev.ps1 doctor
```

首次初始化从 PATH 上已安装的匹配版本 Flutter 创建 `.fvm/flutter_sdk`，复用可用引擎缓存，并按上游顺序应用 25 个 Android Flutter 补丁。依赖安装在项目的 `.pub-cache` 中，随后为实际解析到的 `material_ui` 应用 9 个 Android 补丁。

脚本使用补丁指纹记录初始化状态，重复执行会复用已经准备好的补丁。若 Flutter 版本或补丁发生变化，脚本会停止并提示准备新的副本，避免在旧副本上混用版本。

使用 `pub.dev` 与上游锁文件中的包来源保持一致，并用 `pub get --enforce-lockfile` 验证锁定版本；不执行依赖升级命令。Flutter 引擎下载仍沿用当前环境配置。Gradle 缓存放在项目的 `.gradle` 中。

脚本为本次运行和项目 Git 依赖缓存启用长路径支持，不修改全局 Git 配置。若缓存来自不完整的 Windows checkout，初始化会从该依赖的锁定提交恢复缺失的已跟踪文件。本次修复了 WebView 缓存中因原路径过长而缺失的 10 个 Java 文件，插件 Java 编译已通过。

若 Git 已配置本机 HTTP 代理，且项目尚无 Gradle 缓存配置，初始化会将同一代理写入项目 `.gradle/gradle.properties`，帮助 Gradle 下载分发包和依赖。该配置保留在本地，不修改全局代理；已有配置保持原样。

上游的补丁脚本面向 CI，包含重置 Flutter SDK、修改全局 Git 用户信息和依赖缓存清理等操作。本地开发使用 `tool/dev.ps1`，将 SDK 和 UI 包补丁限制在项目目录内。

## 常用命令

```powershell
# 静态分析
.\tool\dev.ps1 analyze

# 沿用上游已有 info 提示，只让错误／警告阻止检查
.\tool\dev.ps1 analyze --no-fatal-infos

# 运行现有测试
.\tool\dev.ps1 test

# 构建 Android 调试 APK
.\tool\dev.ps1 build

# 构建 Android Release 通用 APK
.\tool\dev.ps1 flutter build apk --release --no-pub

# 查看设备与模拟器
.\tool\dev.ps1 devices
.\tool\dev.ps1 emulators

# 启动本机已准备的项目模拟器（在单独终端运行）
.\tool\dev.ps1 emulator

# 在已连接的 Android 设备上运行
.\tool\dev.ps1 run -d <设备ID>

# 转发其他 Flutter 或 Dart 命令
.\tool\dev.ps1 flutter --version
.\tool\dev.ps1 dart --version
```

依赖或补丁发生调整后，重新执行 `setup`。普通分析、测试和构建命令使用 `--no-pub`，避免在这些步骤中重新解析依赖。

调试 APK 的默认输出位置为 `build/app/outputs/flutter-apk/app-debug.apk`。调试构建使用 Android 调试签名，无需配置上游发布密钥。

Release 通用 APK 的默认输出位置为 `build/app/outputs/flutter-apk/app-release.apk`，包含 ARM 32 位、ARM 64 位和 x86_64 架构。现有 Gradle 配置在没有 `android/key.properties` 时也使用本机 Android 调试密钥签名；这是经过 Release 优化的安装包，签名身份仍是开发密钥。若配置独立发布密钥，密钥及 `key.properties` 应保持在本地，不能提交到 Git。

## 编辑器

VS Code 请通过 **File → Open Workspace from File** 打开初始化生成的 `.fvm/piliminus.code-workspace`。该本地工作区带有实际展开的缓存路径，并结合项目设置使用 `.fvm/flutter_sdk`。工作区文件属于忽略的本地环境文件，每次初始化都会按当前项目位置重新生成。

项目关闭编辑器自动 `pub get`；调整依赖后运行开发脚本的 `setup`，以确保新解析到的 UI 包也应用补丁。其他编辑器也应使用同一份 Flutter SDK，并在运行依赖解析时传入相同缓存目录和包来源。

直接运行全局 `flutter` 会使用机器原有 SDK 和缓存；本项目的补丁环境通过开发脚本或编辑器的项目设置使用。

## 本机模拟器

已使用本机现有的 Android API 35 x86_64 系统镜像创建 `PiliMinus_API35`，设备配置放在项目 `.fvm/avd` 中，WHPX 硬件加速可用。API 35 是运行测试系统版本；应用仍按项目配置以 API 37 为目标构建。

本机旧模拟器的 Vulkan 初始化有兼容问题，开发脚本的 `emulator` 命令使用 SwiftShader 并关闭 Vulkan。该调整仅作用于启动命令，不修改其他项目的模拟器配置。

模拟器创建属于本次机器准备记录，`setup` 不会在其他机器自动创建同名设备；也可以连接开启 USB 调试的 Android 真机，再通过 `devices` 查看设备 ID。

## 验证记录

2026-10-11 本机准备记录：

| 项目 | 实际结果 |
| --- | --- |
| Flutter／Dart | Flutter 3.47.7，Dart 3.13.5 |
| SDK 补丁 | 项目专用 SDK 已应用 25 个 Android 补丁 |
| 依赖与 UI 补丁 | 解析到 254 个包（含项目和 SDK 包），`material_ui` 已应用 9 个 Android 补丁 |
| 依赖版本 | 上游 `pubspec.lock` 保持原样，未升级依赖 |
| JDK | Android Studio 自带的 OpenJDK 21.0.6；源码编译目标沿用 Java 17 |
| Gradle | 9.5.0 已下载并解压；项目独立缓存和本机代理配置已准备 |
| Android SDK | API 37 与 API 36 已安装，Android 许可证已接受 |
| Android NDK | 28.2.13676358 已安装 |
| 静态分析 | 0 个 error、0 个 warning、37 个上游已有 info；严格模式退出码为 1，`--no-fatal-infos` 检查通过 |
| 现有测试 | 2 个账号删除生命周期测试通过 |
| 模拟器 | `PiliMinus_API35` 已创建并成功启动，Android 15／API 35，WHPX 可用 |
| 调试 APK | `build/app/outputs/flutter-apk/app-debug.apk` 构建通过，大小 145,003,751 字节（约 138 MiB） |
| 安装与启动 | APK 在 API 35 模拟器安装成功；`am start -W` 返回 `Status: ok`，首页及推荐封面加载正常，检查时无崩溃日志或未处理的 Flutter 异常 |

37 条 info 主要来自上游复制的 Flutter 组件中的弃用 API 与风格提示，以及现有包名风格。本次环境准备记录这个基线，未修改业务源码或降低项目分析规则。

本次 APK 是上游应用的调试构建，应用 ID 为 `com.example.piliplus.debug`。启动检查覆盖安装、首页渲染和基础网络加载；账号登录与视频播放留待功能开发时验收。本次用于验证的后台模拟器在检查后已关闭，日常调试可用上面的 `emulator` 命令重新启动。
