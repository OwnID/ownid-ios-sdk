import SwiftUI

struct LoginAndRegisterView: View {
    var body: some View {
        ScrollView {
            VStack {
                Text("Note📝: Please enroll FaceID in simulator: Features -> Face ID")
                    .font(.footnote)
                    .padding(.bottom)
                Text("Register Here⬇️")
                RegisterView()
                    .padding()
                    .background(Color.gray.opacity(0.088))
            }
            .padding()
            VStack {
                Text("Login Here⬇️")
                LogInView()
                    .padding()
                    .background(Color.gray.opacity(0.088))
            }
            .padding()
        }
    }
}
