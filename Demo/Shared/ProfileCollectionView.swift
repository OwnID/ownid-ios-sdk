import SwiftUI
import OwnIDCoreSDK

struct ProfileCollectionView: View {
    private enum Constants {
        static let termsOfUse = URL(string: "https://ownid.com/terms.html")!
        static let privacy = URL(string: "https://ownid.com/privacy.html")!
    }
    
    @ObservedObject var viewModel: ProfileCollectionViewModel
    
    private let loginId: String
    private let closeClosure: () -> Void
    
    init(coordinator: AppCoordinator, loginId: String, closeClosure: @escaping () -> Void) {
        self.loginId = loginId
        self.closeClosure = closeClosure
        viewModel = ProfileCollectionViewModel(coordinator: coordinator, loginId: loginId)
    }
    
    var body: some View {
        page()
    }
    
    @ViewBuilder
    func page() -> some View {
        switch viewModel.state {
        case .loading:
            content()
                .loading()
            
        case .initial:
            content()
        }
    }
    
    func content() -> some View {
        VStack {
            Text("Profile Collection")
                .font(.title)
                .padding(.bottom)
            VStack(alignment: .leading, content: {
                Text("Email:")
                Text(loginId)
            })
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom)
            Group {
                if #available(iOS 15.0, *) {
                    TextField("", text: $viewModel.name, prompt: Text("Name").foregroundColor(.gray))
                } else {
                    TextField("Name", text: $viewModel.name)
                }
                if #available(iOS 15.0, *) {
                    SecureField("", text: $viewModel.password, prompt: Text("Password").foregroundColor(.gray))
                } else {
                    SecureField("", text: $viewModel.password)
                }
            }
            .padding()
            .frame(height: 44)
            .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.white, lineWidth: 1)
                )
            .padding(.bottom)
            BlueButton(text: "Create Account", action: {
                viewModel.register()
            })
            .padding(.bottom)
            Text(viewModel.errorMessage)
                .font(.caption)
                .foregroundColor(.red)
                .padding(.top)
            terms()
        }
        .overlay(closeButton(), alignment: .topTrailing)
        .foregroundColor(.white)
        .padding()
        .background(Rectangle()
            .fill(Color("headerBackground"))
            .cornerRadius(15))
        .padding(.horizontal, 20)
    }
    
    private func closeButton() -> some View {
        Button {
            closeClosure()
        } label: {
            Image(systemName: "xmark.circle")
                .resizable()
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
        }
    }
    
    func terms() -> some View {
        VStack(spacing: 0) {
            Text("By creating an account you agree to our")
                .font(.system(size: 12))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 3)
            HStack {
                Button(action: { UIApplication.shared.open(Constants.termsOfUse) }) {
                    Text("Terms of use")
                        .font(.system(size: 12))
                        .foregroundColor(OwnID.Colors.blue)
                }
                Text("&")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                Button(action: { UIApplication.shared.open(Constants.privacy) }) {
                    Text("Privacy")
                        .font(.system(size: 12))
                        .foregroundColor(OwnID.Colors.blue)
                }
            }
        }
    }
}
