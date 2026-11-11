import ApplicationServices
import CoreGraphics

@_silgen_name("_AXUIElementGetWindow")
func AXUIElementGetWindowID(
    _ element: AXUIElement,
    _ identifier: UnsafeMutablePointer<CGWindowID>
) -> AXError
