//  Created by jasu on 2022/02/27.
//  Copyright (c) 2022 jasu All rights reserved.

import SwiftUI

extension OwnID.UISDK {
    /// The position mode of the tooltip.

    enum ATAxisMode: Equatable {
        case top
        case bottom
        case leading
        case trailing
        
        static func mode(configPosition: TooltipPositionType) -> ATAxisMode {
            switch configPosition {
            case .bottom:
                return .bottom
            case .top:
                return .top
            case .leading:
                return .leading
            case .trailing:
                return .trailing
            }
        }
    }

    /// Defines the settings for the tooltip.
    struct ATConstant: Equatable {
        var axisMode: ATAxisMode
        var border: ATBorderConstant
        var arrow: ATArrowConstant
        var shadow: ATShadowConstant
        var distance: CGFloat
        var animation: Animation?
        
        /// Initializes `ATConstant`
        /// - Parameters:
        ///   - axisMode: The position mode of the tooltip.
        ///   - border: The definition of a border.
        ///   - arrow: The definition of arrow indication.
        ///   - shadow: Defines the shadow of the tooltip.
        ///   - distance: The distance between the view and the tooltip. The default value is `8`.
        ///   - animation: An animation of the tooltip. The default value is `.easeInOut(duration: 0.28)`.
        init(axisMode: ATAxisMode = .bottom,
                    border: ATBorderConstant = .init(),
                    arrow: ATArrowConstant = .init(),
                    shadow: ATShadowConstant = .init(),
                    distance: CGFloat = 8,
                    animation: Animation? = .easeInOut(duration: 0.28)) {
            self.axisMode = axisMode
            self.border = border
            self.arrow = arrow
            self.shadow = shadow
            self.distance = distance
            self.animation = animation
        }
    }
}
