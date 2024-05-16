import SwiftUI

struct HeaderView: View {
    public var body: some View {
        VStack {
            Spacer()
            Image("ownidLogo")
                .resizable()
                .renderingMode(.template)
                .foregroundColor(.white)
                .scaledToFit()
                .frame(width: 168, height: 56)
                .padding(.bottom, 16)
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .background(Color("headerBackground"))
    }
}
