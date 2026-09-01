# iPhone USB 屏幕采集（CoreMediaIO）调研总结

> 资料来源：
> 1. [USB iPhone screen recording in Swift — CodeJam (2025/06)](https://www.codejam.info/2025/06/usb-iphone-screen-recording-swift.html)
> 2. [MacOS Media Capture using CoreMediaIO — nadavrub (2015/07)](https://nadavrub.wordpress.com/2015/07/06/macos-media-capture-using-coremediaio/)
> 3. [Gist: samjoch AVCaptureDevice Playground](https://gist.github.com/samjoch/d06f7fb39b2cbbca087ddcb1af59b28e)

---

## 1. 主题与定位

这三篇资料解决的是同一个问题：**iPhone 通过 USB 连接 Mac 后，在自己的 App 中把 iPhone 屏幕作为视频源进行采集/录制**——即 QuickTime「新建影片录制 → 选择 iPhone 屏幕」的能力，但用自己的代码实现。

⚠️ 注意区分（与本系列之前的调研对比）：

| 方案 | 采集内容 | 连接方式 | 核心技术 |
|---|---|---|---|
| 连续互通相机 (Continuity Camera) | iPhone **摄像头**画面 | 无线 / USB | AVFoundation + systemPreferredCamera |
| **本方案（USB 屏幕采集）** | iPhone **屏幕**画面 | **USB（有线）** | **CoreMediaIO + AVFoundation** |

对 RecordScreen 项目来说：录"屏幕"选本方案，录"人脸"选连续互通相机，两者可以共存。

---

## 2. 核心原理

USB 连接且开启屏幕采集开关后，iPhone 会以**外置采集设备**的身份出现在 macOS 的采集设备体系中（底层由 CoreMediaIO 的 DAL 插件实现）。之后既可以走上层的 AVFoundation 路线，也可以走底层 CoreMediaIO 直接拿原始数据。

**所有方案的共同入口 —— 开启开关：**

```swift
import CoreMediaIO

func allowScreenCaptureDevices() {
    let element: CMIOObjectPropertyElement
    if #available(macOS 12.0, *) {
        element = CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    } else {
        element = CMIOObjectPropertyElement(kCMIOObjectPropertyElementMaster)
    }

    var prop = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: element)

    var allow: UInt32 = 1
    let dataSize: UInt32 = 4
    let zero: UInt32 = 0

    CMIOObjectSetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject), &prop, zero, nil, dataSize, &allow)
}
```

三篇资料中该函数几乎逐字相同（只有 Swift/ObjC++ 语法和 `Master/Main` 兼容性差异），说明这是**唯一且必经**的入口。本质等价于 `kCMIOHardwarePropertyAllowScreenCaptureDevices = 1`，作用是让当前进程能发现 USB 移动设备的屏幕采集源。

---

## 3. 两条技术路线

### 路线 A：AVFoundation（上层，推荐，资料 1 + 3）

设置开关后，iPhone 出现在常规设备发现中：

```swift
let devices = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.external],
    mediaType: .muxed,        // .muxed 可有效区分 USB 移动设备与其他外置设备（如 OBS 虚拟摄像头）
    position: .unspecified
).devices
// 或已知 ID: AVCaptureDevice(uniqueID: "...")
```

随后就是标准的 `AVCaptureSession` 流程：`AVCaptureDeviceInput` → 输出（`AVCaptureVideoDataOutput` / `AVCaptureMovieFileOutput` / `AVCaptureVideoPreviewLayer` 预览）。

Gist（资料 3）提供了完整可运行的 Playground 示例：开启开关 → 监听 `AVCaptureDeviceWasConnected` 通知 → 匹配 `modelID == "iOS Device"` → 建 Session → `AVCaptureVideoPreviewLayer` 直接显示到窗口。

### 路线 B：CoreMediaIO（底层，资料 2）

适用场景：AVFoundation 会对设备数据做解复用/解码，如果需要**直接访问设备输出的原始（可能已压缩/复用的）数据流**，则必须用 CoreMediaIO：

- 设备以 `CMIODeviceID` 标识，可通过 `kCMIOHardwarePropertyDevices` 枚举，用 `kCMIODevicePropertyDeviceUID` 与 AVFoundation 的 uniqueID 对应（`FindDeviceByUniqueId`）
- 每个设备暴露若干 `CMIOStreamID`（视频流、音频流、复用流），通过 `kCMIODevicePropertyStreams` 枚举
- 流的格式通过 `kCMIOStreamPropertyFormatDescription` 解析（`CMFormatDescriptionGetMediaType/GetMediaSubType`）
- 取数据：`CMIOStreamCopyBufferQueue` 注册回调，从 `CMSimpleQueue` 中 `Dequeue` 出 `CMSampleBufferRef`，再用 `CMBlockBufferGetDataPointer` 拿裸字节

缺点：无官方文档、示例陈旧、代码量大。

### 路线选择结论

| 需求 | 选择 |
|---|---|
| 预览 / 录制成文件 / 拿到解码后帧 | ✅ 路线 A（AVFoundation） |
| 拿到未解码的原始 H.264/muxed 裸流 | 路线 B（CoreMediaIO） |

RecordScreen 录屏场景 → 优先路线 A；若要低延迟转发原始流再考虑路线 B。

---

## 4. 踩坑清单（资料 1 的精华，重点！）

这篇 2025 年的文章记录了多个**未文档化的坑**，实战价值最高：

### 坑 1：开关生效不是即时的
设置 `kCMIOHardwarePropertyAllowScreenCaptureDevices` 后，设备需要**最长几秒**才会出现。紧接着做 `DiscoverySession` 几乎必然看不到设备。
- ✅ 对策：常驻进程在启动时尽早设置开关；需要即时感知就监听 `AVCaptureDeviceWasConnected` 通知
- ❌ 副作用：无法立即判断"当前没有设备"，CLI 类 `list-devices` 只能靠超时兜底

### 坑 2："预热"副作用（最隐蔽）
**如果不调用一次设备枚举（`AVCaptureDevice.devices()` 或 `DiscoverySession`），`AVCaptureDeviceWasConnected` 通知永远不会到达。**
- Gist 里那行看似无害的 `print("\(AVCaptureDevice.devices().count)")` 实际上是**必需**的，删掉整个程序就不工作
- ✅ 对策：设完开关后先"空跑"一次枚举做预热：

```swift
// 不需要结果，但必须先枚举一次设备来"预热"系统，
// 否则永远收不到 AVCaptureDeviceWasConnected 通知 🤷
let _ = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.external], mediaType: .muxed, position: .unspecified
).devices
```

### 坑 3：疑似"限流"
短时间内反复重启进程设置该开关，会出现：设置开关阻塞数秒 + 收不到设备通知，约 **1 分钟后**才恢复正常。
- 有趣发现：如果系统中有**其他进程**（如 QuickTime）也设置了同一开关并保持运行，则本进程行为完全正常 → 说明"限流"只针对系统中唯一设置该开关的进程
- ✅ 开发期对策：跑一个只设置开关然后永久 sleep 的后台进程（`my-cli background`），之后随便重启调试

### 其他注意点（资料 2 补充）
- 通知依赖 **RunLoop** 运转，命令行程序需保证 `[[NSRunLoop mainRunLoop] run]`
- 实际采集格式可能**要等到第一个采样到达后**才能解析（如音频格式需从 `CMSampleBufferRef` 中取）
- 旧代码中 `kCMIOObjectPropertyElementMaster` 在 macOS 12+ 应改用 `kCMIOObjectPropertyElementMain`

---

## 5. 推荐整合流程（可直接落地到 RecordScreen）

```
App 启动
  │
  ├─ 1. allowScreenCaptureDevices()          // 设开关，越早越好
  ├─ 2. 预热：跑一次 DiscoverySession        // 否则收不到通知！
  ├─ 3. 监听 AVCaptureDeviceWasConnected / WasDisconnected
  │
设备出现（modelID == "iOS Device" 或 mediaType == .muxed 的 external 设备）
  │
  ├─ 4. AVCaptureDeviceInput(device:)
  ├─ 5. 加入 AVCaptureSession + 输出
  │      - 预览:      AVCaptureVideoPreviewLayer
  │      - 拿帧处理:  AVCaptureVideoDataOutput
  │      - 直接录制:  AVCaptureMovieFileOutput
  └─ 6. session.startRunning()
```

关键代码骨架：

```swift
import AVFoundation
import CoreMediaIO

final class IPhoneScreenCapture {
    private let session = AVCaptureSession()

    func setup() {
        allowScreenCaptureDevices()
        // 预热（必需，见坑 2）
        _ = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external], mediaType: .muxed, position: .unspecified
        ).devices

        NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected, object: nil, queue: nil
        ) { [weak self] note in
            guard let device = note.object as? AVCaptureDevice else { return }
            if device.modelID == "iOS Device" {   // 或按需放宽匹配
                self?.startCapture(device: device)
            }
        }
    }

    private func startCapture(device: AVCaptureDevice) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        // output.setSampleBufferDelegate(...)  // 接录制/处理管线
        if session.canAddOutput(output) { session.addOutput(output) }

        DispatchQueue.global().async { self.session.startRunning() }
    }
}
```

---

## 6. 各资料一句话总结

| 资料 | 一句话 |
|---|---|
| CodeJam (2025) | 最新最全的实战指南，贡献了 3 个未文档化的坑（非即时生效、预热副作用、限流）及 `.external + .muxed` 的现代发现方式 |
| nadavrub (2015) | CoreMediaIO 底层路线：拿原始未解码数据流时必须用它，给出了设备/流枚举和回调取数的完整 C++ 骨架 |
| Gist (samjoch) | 最小可运行示例（Playground），验证"开关 + 通知 + 预览"最短路径；其中的 `devices().count` 预热调用是关键 |

## 7. 参考链接

- Apple 官方：[kCMIOHardwarePropertyAllowScreenCaptureDevices](https://developer.apple.com/documentation/coremediaio/kcmiohardwarepropertyallowscreencapturedevices)
- Apple 官方：[Setting up a capture session](https://developer.apple.com/documentation/avfoundation/setting-up-a-capture-session)
- 原文 1：https://www.codejam.info/2025/06/usb-iphone-screen-recording-swift.html
- 原文 2：https://nadavrub.wordpress.com/2015/07/06/macos-media-capture-using-coremediaio/
- Gist：https://gist.github.com/samjoch/d06f7fb39b2cbbca087ddcb1af59b28e
