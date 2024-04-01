import SwiftUI

extension OwnID.UISDK {
    struct RTLLayoutCalculation: XAxisOffsetCalculating {
        func calculateXAxisOffset(viewBounds: CGRect, screenBounds: CGRect) -> CGFloat {
            var XOffset = 0.0
            if viewBounds.minX <= screenBounds.minX {
                XOffset = screenBounds.minX - viewBounds.minX
            }
            let computedOffset = viewBounds.origin.x - XOffset
            return computedOffset
        }
    }
}
