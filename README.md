# RecordScreen

RecordScreen 是一个原生 SwiftUI 双端项目：

- **iOS**：使用 iPhone 后置摄像头采集视频，通过 WebRTC 推流。
- **macOS**：在同一局域网发现并接收 iPhone 视频，使用 Metal 实时预览。

当前版本已完成局域网内的设备发现、连接、WebRTC 视频传输与运行日志；尚未完成音频和视频录制。

## 当前能力与边界

| 能力 | 状态 | 说明 |
|---|---|---|
| iPhone 后置摄像头预览 | 已完成 | 首页全屏预览；推流前为原生 `AVCaptureSession`，推流后为 WebRTC 本地轨道。 |
| Mac 自动发现 | 已完成 | 使用 Bonjour 广播/发现 `_recordscreen._tcp`。 |
| 局域网连接 | 已完成 | TCP 长连接发送 JSON 信令，支持单个活动 iPhone。 |
| WebRTC 视频 | 已完成 | iPhone 创建 Offer，Mac 创建 Answer，双方交换 ICE Candidate。 |
| Mac WebRTC 实时预览 | 已完成 | `RTCMTLNSVideoView` 渲染接收到的视频轨道。 |
| Mac iPhone 直连相机预览 | 已完成 | 使用公开的 AVFoundation `external` 设备发现方式查找并预览可用 iPhone 摄像头。 |
| Mac USB iPhone 屏幕预览 | 已完成 | 启用 CoreMediaIO 屏幕采集设备后，以 `external + muxed` 发现并预览 USB 连接的 iPhone 屏幕。 |
| 运行日志 | 已完成 | `camera`、`discovery`、`signaling`、`webrtc` 四个分类。 |
| 音频 | 未实现 | 当前仅发送视频。 |
| Mac 自动录制 | 未实现 | 后续使用 `AVAssetWriter` 实现。 |
| 外网连接 | 未实现 | 当前没有配置 STUN/TURN，仅适用于同一局域网。 |
| 配对/认证 | 未实现 | 局域网中发现服务即可连接，不应直接用于不可信网络。 |
| 多 iPhone | 未实现 | Mac 收到第二个 TCP 连接时会拒绝它，以保护现有连接。 |

## 运行环境

- Xcode 26.3 或更高版本
- Swift 6
- iOS 17 或更高版本
- macOS 14 或更高版本
- iPhone 真机（模拟器不具备此项目所需的真实摄像头推流场景）
- iPhone 和 Mac 位于同一 Wi-Fi / 局域网

项目使用 Swift Package Manager 固定依赖：

```text
https://github.com/stasel/WebRTC.git
152.0.0
```

不要随意升级该依赖；升级 WebRTC 后必须在 iOS 真机和 macOS 上重新验证协商、编码、渲染和动态库嵌入。

## 快速运行

1. 用 Xcode 打开 `RecordScreen.xcodeproj`，等待 WebRTC Package 解析完成。
2. 为 `RecordScreeniOS`、`RecordScreenMac` 分别选择你的 Development Team；确保两个 Target 都能自动签名。
3. 运行 `RecordScreenMac`，点击 **Start Receiver**。若 macOS 防火墙请求允许传入连接，选择允许。
4. 使用 iPhone 真机运行 `RecordScreeniOS`，首次启动时允许**相机**和**本地网络**权限。
5. 在 iPhone 首页点击右上角设置图标，进入 **Stream Settings**。
6. 在 Mac 列表中点击 **Connect**。Mac 顶部显示 `Connected to <iPhone 名称>` 后，说明 TCP 握手完成。
7. 回到 iPhone 首页，点击顶部浮层中的 **Start**。Mac 预览区应显示实时视频。

> `Command-B` 只会编译；使用 `Command-R` 才会安装并运行应用。

### 使用 USB iPhone Camera

此模式与 iOS App 的 WebRTC 推流互不依赖：将可用的 iPhone 通过数据线连接到 Mac，或满足系统的 Continuity Camera 条件后，在 Mac App 点击 **Find iPhone Camera**，选择设备并点击 **Use Camera**。预览来源会切换为 **iPhone Camera**；使用来源选择器可切回仍在运行的 **WebRTC Stream**。

这是 iPhone 的**摄像头画面**，不是 iPhone 屏幕画面。首次使用时，请允许 macOS 的相机权限。

Continuity Camera 的发现必须使用 `AVCaptureDevice.DiscoverySession` 的 `.external` 设备类型；Apple 文档中的 `.externalUnknown` 是该 API 在旧 SDK 中的名称。不要改用 `.continuityCamera`，它无法按官方示例枚举 iPhone。

选择设备时必须遵循 AVFoundation 会话顺序：`beginConfiguration` → 添加输入与设置 preset → `commitConfiguration` → `startRunning`。在 `beginConfiguration` 和 `commitConfiguration` 之间调用 `startRunning` 会触发 `NSGenericException` 并终止 App。

### 使用 USB iPhone Screen

在 Mac App 点击 **Find iPhone Screen**。应用会在启动后尽早启用 `kCMIOHardwarePropertyAllowScreenCaptureDevices`，预热设备发现，并监听连接/断开通知。将 iPhone 通过 USB 连接、解锁并信任 Mac 后，等待数秒或点击 **Refresh**；在列表点击 **Show Screen** 会打开独立的 **iPhone Screen** 窗口。

该窗口先使用 iPhone 屏幕捕获设备的 `activeFormat` 设置初始内容尺寸，再在首个 `CMSampleBuffer` 到达时按实际视频帧宽高更新窗口比例。窗口可自由缩放，但 `contentAspectRatio` 会始终保持视频比例。点击窗口工具栏的 **Rotate 90 Degrees** 可顺时针旋转画面，旋转时会同步交换窗口宽高约束。

屏幕源使用 `AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, ...)`。不要将其与 Continuity Camera 的 `.video` 发现路径混用：前者是 USB iPhone **屏幕**，后者是 iPhone **摄像头**。首次使用时 macOS 会请求相机与麦克风权限，因为 USB 屏幕设备以 muxed 音视频源形式出现；当前应用仅显示视频，不会处理或保存音频。

## 架构与数据流

```text
┌──────────────────────────────── iPhone ────────────────────────────────┐
│ CameraScreen                                                            │
│  ├─ NativeCameraPreview / CameraPreview                                 │
│  ├─ StreamControlOverlay                                                │
│  ├─ StreamSettingsScreen                                                │
│  ├─ CameraCaptureService ── 原生预览与相机权限                         │
│  ├─ ReceiverDiscoveryService ── Bonjour 发现、连接状态                 │
│  ├─ TCPControlClient ── TCP JSON 换行分帧                              │
│  └─ WebRTCPublisher ── 后置摄像头、Offer、ICE、视频轨道                │
└─────────────────────────┬──────────────────────────────────────────────┘
                          │ Bonjour: _recordscreen._tcp
                          │ TCP: hello / ack / SDP / ICE
                          │ WebRTC: 局域网视频媒体流
┌─────────────────────────▼──────────────────────────────────────────────┐
│ macOS                                                                   │
│ ReceiverScreen                                                          │
│  ├─ LocalReceiverServer ── Bonjour 广播、单个 TCP 连接                 │
│  ├─ ReceiverService ── 连接/预览状态协调                               │
│  ├─ WebRTCReceiver ── Answer、ICE、远端视频轨道                        │
│  └─ RemoteVideoView ── RTCMTLNSVideoView Metal 渲染                    │
│  ├─ ContinuityCameraService ── 查找与管理 iPhone Continuity Camera    │
│  └─ ContinuityCameraPreview ── AVCaptureVideoPreviewLayer 渲染         │
│  ├─ IPhoneScreenCaptureService ── CoreMediaIO USB 屏幕设备发现/采集    │
│  └─ IPhoneScreenPickerScreen ── USB iPhone 屏幕选择界面                │
│  ├─ IPhoneScreenWindow ── 独立窗口、旋转与视频展示                     │
│  └─ AspectRatioWindowConfigurator ── 内容比例与初始窗口尺寸             │
└────────────────────────────────────────────────────────────────────────┘
```

### 连接时序

```text
Mac                  iPhone
 | Start Receiver      |
 | Bonjour 广播         |
 | <-------------------| Bonjour 发现并选择 Mac
 | <------ hello ------| TCP 建立，携带设备名
 | ------- ack ------->| TCP 握手完成
 | <------ offer ------| iPhone 创建 WebRTC Offer
 | ------ answer ----->| Mac 设置远端描述并创建 Answer
 | <---- candidate --->| 双向持续交换 ICE Candidate
 | <=== video media ===| WebRTC 局域网视频轨道
```

信令是**换行分隔的 `Codable` JSON**。不要把 SDP 或 Candidate 直接拼接为未转义的字符串，也不要更改换行分帧规则；SDP 中可能包含换行，必须整体编码在 JSON 字段中。

## 项目结构

```text
RecordScreenShared/
├── Diagnostics/AppLog.swift              # 统一 OSLog 分类
├── Domain/StreamConnection.swift         # 连接状态、流配置、发布/接收协议
├── Networking/PeerHandshake.swift        # Bonjour 服务常量、设备角色
├── Networking/Signaling.swift            # TCP/WebRTC 信令模型
├── Theme/Theme.swift                     # 语义颜色、间距、圆角、动效
└── ViewModifiers/ViewModifiers.swift     # 共享 SwiftUI 样式

RecordScreeniOS/
├── Components/
│   ├── NativeCameraPreview.swift          # 推流前的 AVCapture 预览
│   ├── CameraPreview.swift                # 推流中的 RTCMTLVideoView
│   └── StreamControlOverlay.swift         # 首页透明控制浮层
├── Screens/
│   ├── CameraScreen.swift                 # iOS 首页与状态协调
│   └── StreamSettingsScreen.swift         # Mac 连接/分辨率页面
└── Services/
    ├── CameraCaptureService.swift         # 权限与 AVCaptureSession 生命周期
    ├── ReceiverDiscoveryService.swift     # Bonjour 浏览、握手、信令分派
    ├── TCPControlClient.swift             # iOS TCP 信令客户端
    └── WebRTCPublisher.swift              # iOS WebRTC 发布端

RecordScreenMac/
├── Components/RemoteVideoView.swift       # RTCMTLNSVideoView 包装
├── Screens/ReceiverScreen.swift           # Mac 接收端界面
└── Services/
    ├── ContinuityCameraService.swift       # iPhone 直连摄像头发现与采集
    ├── IPhoneScreenCaptureService.swift    # USB iPhone 屏幕发现与采集
    ├── IPhoneScreenWindow.swift             # 独立屏幕预览窗口
    ├── IPhoneScreenPickerScreen.swift       # USB 屏幕选择界面
    ├── LocalReceiverServer.swift          # Bonjour/TCP 信令服务端
    ├── ReceiverService.swift              # Mac 连接与预览状态协调
    └── WebRTCReceiver.swift               # Mac WebRTC 接收端
```

共享目录的 Swift 文件以源文件形式编入两个 App Target，**不是独立 Swift Package**。新增共享文件时，必须同时添加到 iOS 和 macOS Target 的 Compile Sources。

## iOS 界面规则

- 首页必须保持为全屏视频预览，不应重新加入设备列表或画质设置。
- 首页浮层：左侧为状态，右侧为设置按钮和 Start / Stop 推流操作。
- `StreamSettingsScreen` 是设备连接和画质配置的唯一入口。
- 颜色、间距、圆角、动画使用 `AppTheme`；不要在 Screen 直接硬编码设计值。
- 原生预览和 WebRTC 采集不能长期并发占用同一摄像头。开始推流前停止 `CameraCaptureService` 预览；停止推流后恢复预览。

Mac 的 WebRTC、Continuity Camera 与 USB Screen 是可切换的预览来源。预览区域每次只显示一个来源；切换到 WebRTC 不得停止 WebRTC Receiver 服务或断开已建立的 iPhone 推流。切换到本地摄像头或 USB 屏幕来源时，必须停止另一个本地采集会话，避免同一 iPhone 的硬件资源争用。

USB Screen 不显示在主接收器的预览区。`IPhoneScreenCaptureService` 必须作为 `RecordScreenMacApp` 的共享 `StateObject` 注入主窗口和 `WindowGroup(id: "iphone-screen")`；否则新窗口会持有不同的 `AVCaptureSession`，无法显示已选屏幕。

`ContinuityCameraPickerScreen` 是 macOS Sheet，必须保留最小尺寸；`List` 在没有显式可用高度时可能被压缩到零高度，只显示标题和工具栏、却不显示已发现设备。

## 日志与排障

日志定义在 `RecordScreenShared/Diagnostics/AppLog.swift`，可在 Xcode Debug Console 或 macOS **Console.app** 查看。

| 分类 | 关键事件 |
|---|---|
| `camera` | 权限、原生预览启动/停止、相机配置失败 |
| `discovery` | Bonjour 浏览启动、发现 Mac 数量、浏览器失败 |
| `signaling` | TCP 建立、`hello` / `ack`、SDP / ICE 消息、断开与解析失败 |
| `webrtc` | Peer Connection、Offer/Answer、ICE 状态、视频轨道到达 |

Mac 上可使用：

```bash
log stream --style compact --level info \
  --predicate 'subsystem == "com.example.RecordScreenMac"'
```

遇到“iPhone 显示已连接、Mac 未显示”的问题，按此顺序检查 Mac 日志：

```text
Mac accepted a new TCP signaling connection.
Mac received signaling message: hello.
Mac sending signaling message: ack.
Mac completed handshake with iPhone: <device>.
Receiver service registered connected iPhone: <device>.
```

遇到“已连接但无视频”的问题，检查顺序为：

```text
iPhone WebRTC negotiation was requested.
Created and set iPhone WebRTC offer.
Mac received WebRTC offer.
Mac created and set WebRTC answer.
... generated a local ICE candidate.
... ICE connection state: connected/completed.
Mac remote video track received.
```

## AI 持续开发交接

在修改前，AI 应先阅读：

1. 本 README 的“当前能力与边界”“架构与数据流”和“iOS 界面规则”。
2. 与改动侧对应的 `CameraScreen` / `ReceiverScreen`。
3. 对应的 Service，以及 `Signaling.swift`、`StreamConnection.swift`。
4. `AppLog.swift`，并为新的连接状态、资源生命周期或失败路径补充同分类日志。

必须保持的行为：

- iPhone 创建 Offer，Mac 创建 Answer。
- Remote Description 设置完成前收到的 ICE Candidate 必须暂存，完成后再添加。
- TCP 信令保持单条活动连接，Mac 不得用新入站连接静默覆盖已连接的 iPhone。
- WebRTC delegate 回调不是主线程回调；入口使用 `nonisolated`，只有 UI 状态更新才切换回 `@MainActor`。
- 不使用 `try!`、强制解包或 `as!`；网络、相机、编码和文件写入错误必须更新状态并记录日志。
- 任何动态 Framework 依赖都要同时满足链接、嵌入和 rpath。当前工程已配置 `WebRTC.framework` 的运行路径，勿删除 `LD_RUNPATH_SEARCH_PATHS`。

新增源文件时，除创建文件外还必须把它加入 `RecordScreen.xcodeproj/project.pbxproj` 的文件引用、Group、对应 Target 的 Sources Build Phase；否则 Xcode 不会编译它。

## 后续路线图

### 1. 音频推流

- iOS 请求麦克风权限，添加 `NSMicrophoneUsageDescription`。
- 使用 WebRTC 音频源/轨道发送音频。
- Mac 接收并监听远端音频轨道。
- 验证音视频同步、蓝牙设备切换和中断恢复。

### 2. Mac 自动录制

- 新建独立的 `RecordingService`，不要把 `AVAssetWriter` 逻辑放进 SwiftUI View 或 `WebRTCReceiver`。
- 将接收的视频和音频帧按统一时间戳写入 `AVAssetWriter`。
- 使用临时文件写入，完成后原子移动至目标目录。
- 实现开始、停止、WebRTC 断开、磁盘不足、写入失败和清理损坏文件。
- 明确文件格式、保存目录、录像库 UI 和空间预警策略。

### 3. 连接安全与可靠性

- 增加二维码/一次性 token 配对，并在 Keychain 保存已配对设备。
- 为信令加入协议版本、会话 ID、超时与心跳。
- 增加有界重连、网络变化处理和连接质量反馈。
- 允许替换活动 iPhone 前要求 Mac 用户明确确认。

### 4. 外网访问

- 部署受鉴权保护的 HTTPS/WSS 信令服务。
- 部署带短期凭证的 TURN 服务（例如 coturn）。
- 配置 STUN/TURN `RTCIceServer`，但不要把 TURN 密码硬编码在 App。
- 在蜂窝网络、双 NAT、弱网下测试候选地址与重连。

## 验证命令

可在项目根目录执行：

```bash
xcodebuild -project RecordScreen.xcodeproj \
  -scheme RecordScreenMac \
  -sdk macosx \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild -project RecordScreen.xcodeproj \
  -scheme RecordScreeniOS \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

摄像头和真实局域网 WebRTC 传输必须使用 iPhone 真机进行端到端验证。
