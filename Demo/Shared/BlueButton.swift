import SwiftUI

public struct BlueButton: View {
    public init(text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }
    
    public let text: String
    public let action: () -> Void
    
    public var body: some View {
        HStack {
            Button(action: action, label: {
                Text(text)
                    .font(.system(size: 16, weight: .bold))
                    .fullWidthTextWithMultiline()
            })
        }
        .padding(EdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8))
        .background(Color("blue"))
        .foregroundColor(.white)
        .cornerRadius(6)
    }
}

public extension View {
    func fullWidthTextWithMultiline() -> some View {
        self
            .frame(
                minWidth: 0,
                maxWidth: .infinity,
                alignment: .center
            )
    }
}
