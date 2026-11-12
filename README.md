# yoo-app-windows-manager

macOS 下的轻量窗口管理器，采用 **二分法（BSP，Binary Space Partitioning）** 管理窗口布局。

## 下载

从 [GitHub Releases](https://github.com/aotianlong/yoo-app-windows-manager/releases/latest) 下载编译好的 `YooWindowsManager-*-macos-arm64.app.zip`（Apple Silicon），解压后将应用拖入“应用程序”目录。

当前发布包使用 ad-hoc 签名，首次启动若被 macOS 拦截，请在 Finder 中右键应用并选择“打开”。

## 功能概览

- 维护每块屏幕的二分树布局（水平左右 / 垂直上下）
- 按树结构计算窗口 frame，并通过 Accessibility API 应用
- 菜单栏常驻，按显示器上窗口数量自动二分
- 布局状态持久化到 `~/Library/Application Support/YooWindowsManager/`
- 自动跟随系统语言，支持简体中文和英文

## 环境要求

- macOS 14+
- Swift 6.0+
- **辅助功能**权限（控制窗口位置与大小）
- **输入监控**权限（若全局热键被系统拦截，需在「隐私与安全性 → 输入监控」中授权）

## 构建与运行

```bash
cd /Volumes/DataExt/workspace/yoo-app-windows-manager
./Scripts/build-app.sh
open .build/YooWindowsManager.app
```

首次运行会直接打开系统的辅助功能授权页，不再显示重复的应用内提示框。菜单会显示当前授权状态；打开开关后应用会自动继续布局。

## 使用

应用始终自动管理窗口。点击菜单栏图标并选择 **重新布局**，或按全局快捷键 **Control + Shift + R**，可立即在**每块显示器内部**重新执行布局：

菜单中的 **设置…（Command + ,）** 提供：

- 登录时自动启动、启动后自动布局
- 窗口间距、屏幕边距、交换阈值、检测频率
- 布局动画、拖动反馈、跨屏窗口排序
- 重新布局、排到第一位、向前 / 向后的全局快捷键录制与禁用

相邻窗口之间默认保留 10pt 间距，屏幕边缘保留 5pt。

拖动窗口边缘调整大小时，相邻窗口会实时填充或缩小；新的二分比例在松手后保留。选择 **重新布局** 可恢复严格 50/50 比例。

窗口顺序快捷键以当前聚焦窗口为对象：

- **Control + Shift + Enter**：移到布局顺序第一位
- **Control + Shift + I**：向前移动一位
- **Control + Shift + J**：向后移动一位

- 1 个：占满
- 2 个：左右各半
- 3 个：左 1 个，右侧上 / 下各 1 个
- 4 个：左 1 个，右上 1 个，右下左右各 1 个
- 更多：始终每次只切出 1 个窗口，严格按 50/50 比例左右 / 上下交替二分

请通过 `.build/YooWindowsManager.app` 启动。直接使用 `swift run` 会以裸可执行文件运行，macOS 可能不会在「辅助功能」列表中稳定显示应用条目。

## 架构

```
YooWindowsManagerCore/     # 可测试核心库
  Models/                  # LayoutNode、LayoutWorkspace
  Services/                # LayoutEngine、WindowDiscovery、AX 控制

YooWindowsManager/         # 菜单栏应用入口
```

### 二分布局思路

1. 每个屏幕一棵布局树：`leaf` 对应一个窗口，`split` 按方向与比例切分区域。
2. 对前台窗口执行「向左/右/上/下」时，在树中插入或扩展 split，并 `resolvedPlacements` 得到几何。
3. `AccessibilityWindowController` 将 frame 写给对应 AX 窗口。

## 测试

```bash
swift test
```

## 路径说明

在 macOS 上数据盘挂载点为 `/Volumes/DataExt`，对应你提到的 `/mnt/DataExt/workspace`。

## 后续可扩展

- 窗口焦点在树节点间跳转（←→↑↓ 只换焦点）
- 拖拽调整某层 split 的 `ratio`
- 多桌面 / Space 感知
- 打包为 `.app` 并签名分发

## 许可证

[MIT](LICENSE)
