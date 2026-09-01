# USB iPhone 屏幕录制（Swift）

> 原文：[USB iPhone screen recording in Swift — CodeJam (2025/06)](https://www.codejam.info/2025/06/usb-iphone-screen-recording-swift.html)
> 本文为译文，代码块保留原文。

---

把 iPhone 通过 USB 插到 Mac 上，QuickTime 允许你把 iPhone 屏幕选为视频录制源。

这很酷，但如果你想在自己的 App 里做同样的事情，该怎么办？

我最近正好要做这件事，这篇博客汇总了我学到的一切，特别是**我遇到并解决掉的那些未文档化的坑**。

## `kCMIOHardwarePropertyAllowScreenCaptureDevices`

你首先需要做的是启用 [`kCMIOHardwarePropertyAllowScreenCaptureDevices`](https://developer.apple.com/documentation/coremediaio/kcmiohardwarepropertyallowscreencapturedevices)。

这是一个"硬件属性"（不管它到底是什么），设置之后，当前进程就能访问 USB 连接的移动设备进行屏幕录制。

你可以在网上找到[很多](https://gist.github.com/samjoch/d06f7fb39b2cbbca087ddcb1af59b28e)[写法](https://nadavrub.wordpress.com/2015/07/06/macos-media-capture-using-coremediaio/)，下面是我自己的版本：

```swift
import CoreMediaIO

// 设置 "硬件" 属性，允许发现 USB 移动设备用于屏幕录制。
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

这样，你就能在常规的 `AVCaptureDevice.DiscoverySession` 中发现 USB 移动设备了。

虽然这段代码用了相当啰嗦的底层老式 C 接口（因为目前这是唯一的办法），但逻辑很直白。精神上它就等价于执行 `kCMIOHardwarePropertyAllowScreenCaptureDevices = 1`（废话）。

但这个硬件属性并不像看上去那么无害，接下来我要把关于它发现的一切一股脑倒给你。做好准备吧（或者先跳到下一节，等遇到奇怪的问题再回来查阅 😂）。

## 它不是即时生效的

设置 `kCMIOHardwarePropertyAllowScreenCaptureDevices` 之后，效果**不是即时的**。也就是说，如果你设置完紧接着做一次 `AVCaptureDevice.DiscoverySession`，你基本上**必然**看不到已连接的 USB 移动设备。

这不一定是个问题。比如如果你的 Swift 进程是长时间运行的，启动时第一件事就是设置这个属性，而实际列设备是在稍后用户交互时，那一切都没问题。

但如果你在写 CLI（即 `my-cli list-devices` / `my-cli record-device <device>`），或者就是需要在应用启动后立即访问移动设备，那这招就不灵了。

设置属性之后，设备需要**最长几秒**才会"出现"，你可以监听 `NotificationCenter` 的 `AVCaptureDeviceWasConnected` 通知来得知它。[这个 Gist](https://gist.github.com/samjoch/d06f7fb39b2cbbca087ddcb1af59b28e) 里有个不错的例子。

```swift
// 为什么要这么做，见下文 "枚举设备的预热副作用" ...
let _ = AVCaptureDevice.devices()

NotificationCenter.default
  .addObserver(
    forName: NSNotification.Name.AVCaptureDeviceWasConnected, object: nil, queue: nil
  ) { (notif) -> Void in
    let device = notif.object! as! AVCaptureDevice
    // ...
  }
```

这能工作，但同时也意味着**无法立即判断当前没有设备连接**。如果你想实现 `my-cli list-devices`，这就是个问题。你的最佳选择是几秒后超时，但这并不理想，因为没有设备时会引入额外的延迟……

## 枚举设备的"预热"副作用

这个坑超级阴险，我在它上面浪费了大量时间。原来，**如果你不调用任何列设备的 API**（无论是已废弃的 `AVCaptureDevice.devices`，还是现在正规的 `AVCaptureDevice.DiscoverySession`），那么 `AVCaptureDeviceWasConnected` 通知**永远不会到达**。

所以你需要先启动一个 `DiscoverySession`，并且预期它会返回 0 个设备（因为你刚设置了硬件属性，效果不是即时的），目的只是给系统"预热"，这样系统之后才会真正发送通知。

在我前面链接的 [Gist](https://gist.github.com/samjoch/d06f7fb39b2cbbca087ddcb1af59b28e#file-avcapturedevice-playground-swift-L38) 中，`print("\(AVCaptureDevice.devices().count)")` 这一行其实是**有实际意义的**，没有它代码就**跑不起来**：

```swift
func start() {
  print("\(AVCaptureDevice.devices().count)")

  NotificationCenter.default
    .addObserver(
      forName: NSNotification.Name.AVCaptureDeviceWasConnected, object: nil, queue: nil
    ) { (notif) -> Void in
      self.iosDeviceAttached(device: notif.object! as! AVCaptureDevice)
    }
}
```

它不只是看起来那样是一句无害的调试打印。**调用 `AVCaptureDevice.devices` 这个行为本身**就是在给系统预热，让通知之后能真正被发出。没有它，通知**永远不会**到达。

我喜欢把它写得更明确一点：

```swift
// 我们并不需要这个数据，但它似乎是给系统 "预热" 所必需的。
// 如果不先调用一次获取设备的系统调用，
// 我们就无法通过 `AVCaptureDeviceWasConnected` 发现新设备。🤷
let _ = AVCaptureDevice.devices()
```

## 它被限流了？

这个坑也让我抓狂了好一阵。我的应用启动后设置上面那个硬件属性，监听设备连接通知，能看到 iPhone 可用于屏幕录制。

然后我迭代代码，加点日志或写点真正开始采集视频流的代码，再重启应用。

结果，设置 `kCMIOHardwarePropertyAllowScreenCaptureDevices` 不仅会**阻塞好几秒**才完成，而且尽管 iPhone 明明插着，我却**再也收不到**任何设备连接通知！

在我看来，设置这个属性似乎被某种方式**限流**了。我需要等上大约**一分钟**，再重新启动 CLI，行为才会"恢复正常"（设置属性几乎瞬时完成，并且能收到已插入设备的通知）。

不过，有意思的地方来了：我注意到如果电脑上有**任何其他进程**也设置了同一个硬件属性（比如 QuickTime），并且那个进程一直在后台运行，那么我的 CLI 每一次都能可靠地工作，哪怕我在短时间内启动很多次。所以看起来这个"限流"只有在你的 CLI 是**系统里唯一**设置该属性的进程时才是真正的问题。

那我怎么做的？我写了一个 `my-cli background` 命令，它唯一做的事情就是设置 `kCMIOHardwarePropertyAllowScreenCaptureDevices` 属性，然后无限 sleep。把它跑在后台，之后 `my-cli list-devices` 之类的命令就可以随便用了。

这不能用于生产环境，但至少对开发很有用，让我可以快速迭代。

## 真正的设备录制

这里我不展开讲细节，因为这一步实际上没有什么坑了。就是标准的 `AVFoundation` 录制，网上已经有大量资料覆盖。

首先通过 `DiscoverySession` 获取外置设备：

```swift
let devices = AVCaptureDevice.DiscoverySession(
  deviceTypes: [.external],
  // muxed 类型似乎是区分 USB 移动设备和其他外置设备
  //（例如 "OBS Virtual Camera"）的一个不错方式。
  mediaType: .muxed,
  position: .unspecified
).devices
```

这会返回一个 `AVCaptureDevice` 列表。或者如果你已经有了移动设备的 ID：

```swift
let device = AVCaptureDevice(uniqueID: "...")
```

然后从该设备创建 input：

```swift
let deviceInput = try AVCaptureDeviceInput(device: device)
```

剩下的就是常规的 [`AVCaptureSession` 流程](https://developer.apple.com/documentation/avfoundation/setting-up-a-capture-session)。

## 总结

如果你也遇到了上面这些坑，希望这篇文章帮到了你，希望你没像我一样在上面浪费那么多时间。设备录制愉快！
