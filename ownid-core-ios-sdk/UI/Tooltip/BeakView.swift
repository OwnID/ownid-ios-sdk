import SwiftUI

public extension OwnID.UISDK {
    struct BeakView: View {
        static let bottomlineWidth = 1.3
        static let width = 14.0
        static let height = 8.0
        
        private let tooltipConfig: TooltipConfig
        
        public init(tooltipConfig: OwnID.UISDK.TooltipConfig) {
            self.tooltipConfig = tooltipConfig
        }
        
        public var body: some View {
            ZStack {
                Triangle()
                    .fill(tooltipConfig.backgroundColor)
                Triangle()
                    .stroke(tooltipConfig.borderColor, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                TriangleSide()
                    .stroke(tooltipConfig.backgroundColor, style: StrokeStyle(lineWidth: Self.bottomlineWidth, lineCap: .square, lineJoin: .bevel))
            }
            .frame(width: Self.width, height: Self.height)
            .compositingGroup()
        }
    }
}
