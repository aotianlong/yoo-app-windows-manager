# yoo-app-windows-manager

macOS 下的轻量窗口管理器，采用 **二分法（BSP，Binary Space Partitioning）** 管理窗口布局。

## 功能概览

- 维护每块屏幕的二分树布局（水平左右 / 垂直上下）
- 按树结构计算窗口 frame，并通过 Accessibility API 应用
- 菜单栏常驻，按显示器上窗口数量自动二分
- 布局状态持久化到 `~/Library/Application Support/YooWindowsManager/`

## 环境要求

- macOS 14+
- Swift 6.0+
- **辅助功能**权限（控制窗口位置与大小）
- **输入监控**权限（若全局热键被系统拦截，需在「隐私与安全性 → 输入监控」中授权）

## 构建与运行

```bash
cd /Volumes/DataExt/workspace/yoo-app-windows-manager
swift build
swift run YooWindowsManager
```

首次运行请在菜单「申请辅助功能权限」中完成授权。

## 使用

点击菜单栏图标，选择 **启用** 或 **停用**。启用后会在**每块显示器内部**，对该屏上的窗口做螺旋二分：

- 1 个：占满
- 2 个：左右各半
- 3 个：左 1 个，右侧上 / 下各 1 个
- 4 个：左 1 个，右上 1 个，右下左右各 1 个
- 更多：始终每次只切出 1 个窗口，左右 / 上下方向交替

若从命令行 `swift run` 启动，请在「辅助功能」列表中允许 `.build/debug/YooWindowsManager`（弹窗会显示完整路径）。

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
