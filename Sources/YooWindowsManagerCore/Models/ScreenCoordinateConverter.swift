import CoreGraphics

enum ScreenCoordinateConverter {
    /// Cocoa 使用左下原点，Quartz/Accessibility 使用左上原点。
    /// 两套坐标只需围绕主屏顶部翻转 Y 轴；该变换可双向使用。
    static func flipVertically(_ frame: CGRect, mainScreenMaxY: CGFloat) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: mainScreenMaxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}
