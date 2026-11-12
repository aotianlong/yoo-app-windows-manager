# Yoo Windows Manager

[English](README.md) | [简体中文](README.zh-CN.md)

macOS 下的轻量窗口管理器，采用 **二分法（BSP，Binary Space Partitioning）** 管理窗口布局。

## 下载

从 [GitHub Releases](https://github.com/aotianlong/yoo-app-windows-manager/releases/latest) 下载适用于 Apple Silicon 的 `YooWindowsManager-*-macos-arm64.app.zip`，解压后将应用拖入“应用程序”目录。

当前发布包使用 ad-hoc 签名。首次启动若被 macOS 拦截，请在 Finder 中右键应用并选择 **打开**。

## 功能概览

- 为每块屏幕维护独立的二分树布局
- 按树结构计算窗口 frame，并通过 Accessibility API 应用
- 菜单栏常驻，自动整理每块显示器上的窗口
- 将布局状态持久化到 `~/Library/Application Support/YooWindowsManager/`
- 自动跟随系统语言，内置简体中文和英文

## 环境要求

- macOS 14+
- Swift 6.0+
- **辅助功能**权限，用于控制窗口位置与大小
- **输入监控**权限（若 macOS 拦截全局快捷键）

## 构建与运行

```bash
git clone https://github.com/aotianlong/yoo-app-windows-manager.git
cd yoo-app-windows-manager
./Scripts/build-app.sh
open .build/YooWindowsManager.app
```

首次运行时，应用会打开系统的辅助功能设置。授权后应用将自动继续管理窗口，菜单中也会显示当前授权状态。

请启动生成的 `.app` 应用包，不要直接使用 `swift run`。裸可执行文件可能无法稳定显示在 macOS 的辅助功能列表中。

## 使用

应用会自动管理窗口。点击菜单栏图标并选择 **重新布局**，或按 **Control + Shift + R**，可在每块显示器内独立重建布局。

打开 **设置…（Command + ,）** 可以配置：

- 登录时自动启动、应用启动后自动布局
- 窗口间距、屏幕边距、交换阈值和检测频率
- 布局动画、拖动反馈和跨屏窗口排序
- 录制或禁用重新布局、窗口排序等全局快捷键

相邻窗口之间默认保留 10 pt 间距，屏幕边缘保留 5 pt。

拖动窗口边缘调整大小时，相邻窗口会实时填充或缩小；新的二分比例会在松手后保留。选择 **重新布局** 可恢复严格的 50/50 比例。

窗口顺序快捷键以当前聚焦窗口为对象：

- **Control + Shift + Enter**：移到布局顺序第一位
- **Control + Shift + I**：向前移动一位
- **Control + Shift + J**：向后移动一位

自动布局遵循以下模式：

- 1 个窗口：占满显示器
- 2 个窗口：左右各半
- 3 个窗口：左侧 1 个，右侧上下各 1 个
- 4 个窗口：左侧 1 个，右上 1 个，右下左右各 1 个
- 更多窗口：每次以 50/50 比例切分一个区域，并交替使用水平和垂直方向

## 架构

```text
Sources/
  YooWindowsManagerCore/     # 可测试核心库
    Models/                  # LayoutNode、LayoutWorkspace
    Services/                # LayoutEngine、WindowDiscovery、AX 控制

  YooWindowsManager/         # 菜单栏应用入口
```

### 二分布局思路

1. 每块屏幕拥有一棵布局树：`leaf` 对应窗口，`split` 按方向和比例切分区域。
2. 布局树通过 `resolvedPlacements` 计算窗口几何信息。
3. `AccessibilityWindowController` 将 frame 应用到对应的 macOS 窗口。

## 测试

```bash
swift test
```

## 后续计划

- 在相邻树节点之间移动窗口焦点
- 通过拖动调整上层 split 的比例
- 感知多个桌面 / Space
- Developer ID 签名与公证发布

## 许可证

[MIT](LICENSE)
