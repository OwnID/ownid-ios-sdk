import SwiftUI

extension OwnID.UISDK {
    struct SpinnerLoaderView: View {
        let spinnerColor: Color
        let circleColor: Color
        let viewBackgroundColor: Color
        
        private let lineStyle = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
        @State private var circleLineLength: Double = 0.011
        @State private var circleRotation = 0.0
        @Binding var isLoading: Bool
        private let animationDuration = 2.0
        private let maximumCircleLength: CGFloat = 1/3
        
        private var rotationAnimation: Animation {
            Animation
                .linear(duration: animationDuration)
                .repeatForever(autoreverses: false)
        }
        
        private var lineLengthAnimation: Animation {
            Animation
                .linear(duration: animationDuration)
                .repeatForever(autoreverses: true)
        }
        
        var body: some View {
            VStack {
                ZStack {
                    backgroundCircle()
                    increasingCircle()
                }
                .background(viewBackgroundColor)
            }
            .onChange(of: isLoading, perform: { value in
                applyAnimation(isLoading: value)
            })
            .onAppear(perform: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    applyAnimation(isLoading: isLoading)
                }
            })
        }
        
        private func applyAnimation(isLoading: Bool) {
            if isLoading {
                withAnimation(rotationAnimation) {
                    circleRotation = 1
                }
                withAnimation(lineLengthAnimation) {
                    circleLineLength = 1
                }
            }
        }
        
        @ViewBuilder
        private func increasingCircle() -> some View {
            Circle()
                .trim(from: 0, to: min((circleLineLength), maximumCircleLength))
                .stroke(style: lineStyle)
                .foregroundColor(spinnerColor)
                .rotationEffect(.degrees(-(90)))
                .rotationEffect(.degrees(360 * circleRotation))
        }
        
        @ViewBuilder
        private func backgroundCircle() -> some View {
            Circle()
                .stroke(style: lineStyle)
                .foregroundColor(circleColor)
        }
    }
}
