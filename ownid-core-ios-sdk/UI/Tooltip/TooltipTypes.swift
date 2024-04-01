import SwiftUI

public extension OwnID.UISDK {
    /// The side of the button that tooltip should be placed on.
    /**

                          top
            X──────────────X──────────────X
            |                             |
            |                             |
   leading  X           button            X  trailing
            |                             |
            |                             |
            X──────────────X──────────────X
                         bottom
     */
    enum TooltipPositionType: String {
        case top, bottom, leading, trailing
    }
}

public extension OwnID.UISDK {
    struct TooltipConfig: Equatable {
        public init(isEnabled: Bool = false,
                    tooltipPosition: OwnID.UISDK.TooltipPositionType = .bottom,
                    textSize: CGFloat = 16,
                    fontFamily: String? = nil,
                    textColor: Color = OwnID.Colors.defaultBlackColor,
                    borderColor: Color = OwnID.Colors.biometricsButtonBorder,
                    backgroundColor: Color = OwnID.Colors.biometricsButtonBackground) {
            self.isEnabled = isEnabled
            self.tooltipPosition = tooltipPosition
            self.textSize = textSize
            self.fontFamily = fontFamily
            self.textColor = textColor
            self.borderColor = borderColor
            self.backgroundColor = backgroundColor
        }
        
        public var isEnabled: Bool
        public var tooltipPosition: TooltipPositionType
        public var textSize: CGFloat
        public var fontFamily: String?
        public var textColor: Color
        public var borderColor: Color
        public var backgroundColor: Color
    }
}

extension OwnID.UISDK.TooltipPositionType {
    var beakViewRotationAngle: Double {
        switch self {
        case .top:
            return 180
        case .bottom:
            return 0
        case .leading:
            return 90
        case .trailing:
            return -90
        }
    }
}
