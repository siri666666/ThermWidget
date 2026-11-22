# ThermWidget — iOS 硬件温度只读监控与桌面/锁屏小组件

一个开源、极简、只读的 iOS 硬件温度监控 App 与 `WidgetKit` 小组件，专为已越狱或带有 **TrollStore / TrollStore Lite** 环境的 iOS 16+ 设备设计。

## 特性
- **纯只读读取：** 通过 `dlopen` 动态调用 `IOKit`（`IOHIDEventSystemClient` + `AppleSmartBattery`）及系统 `NSProcessInfo` / `com.apple.system.thermalpressurelevel`，**不写入 `AppleSMC`，不注入任何其他 App（微信、SpringBoard 等）**。
- **核心与明细全覆盖：**
  - **核心概览：** 电池温度、SoC 核心、电源 / 充电区、NAND 闪存、多传感器机身均值、最高热点、系统温控等级（正常 / 温热 / 较热降频 / 过热保护）。
  - **明细列表：** 按部位分组展示所有可读 HID 热传感器实时读数（支持 °C / °F 切换）。
- **多种小组件尺寸：**
  - 桌面 **小号**（电池 + 核心 + 均温 + 温控状态）
  - 桌面 **中号**（电池 / SoC 核心 / 电源区 / 机身均温 + 最热传感器）
  - 锁屏 **矩形 / 单行** 小组件

## 关于 iOS 16 刷新机制说明
受 iOS 16 系统 `chronod` 调度策略限制，第三方桌面小组件无法每秒自动跳数（系统通常按每日预算每 15–60 分钟后台自动刷一次）。
- **主动点按秒刷：** 点击任意桌面或锁屏小组件会立即打开本 App，在前台瞬间重读硬件传感器并强制 `WidgetCenter.shared.reloadAllTimelines()` 同步回桌面；按 Home 键回到桌面即可看到最新数据（App 前台触发不计入每日后台预算）。

## 构建与安装
1. 推送到 GitHub 后，`.github/workflows/build.yml` 会在 macOS runner 上使用 `xcodegen`、`xcodebuild` 与 `ldid` 自动编译并签名打包 `ThermWidget-TrollStore.ipa`。
2. 在 Actions 的 Workflow 产物中下载 `ThermWidget-TrollStore-IPA`。
3. 在手机上用 **TrollStore / TrollStore Lite** 导入安装即可；若桌面小组件列表未立刻出现，在 TrollStore 内执行一次 **Refresh Icon Cache（刷新图标缓存）**。

## 目录结构
- `Shared/`：跨 App 与小组件共享的 Objective-C `IOKit` 只读采集桥接与 Swift 数据分类模型
- `ThermWidgetApp/`：主程序 SwiftUI 界面
- `ThermWidgetExtension/`：`WidgetKit` 小组件扩展
- `Entitlements/`：`ldid` 签名权限配置（`platform-application`、App Groups、只读 HID/Battery 权限）
- `.github/workflows/build.yml`：GitHub Actions 自动打包工作流
