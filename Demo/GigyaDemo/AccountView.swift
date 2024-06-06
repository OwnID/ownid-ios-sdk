import SwiftUI

struct AccountModel: Identifiable, Decodable, Equatable {
    init(name: String, email: String) {
        self.name = name
        self.email = email
    }
    
    var id = UUID().uuidString
    let name: String
    let email: String
}

struct AccountView: View {
    init(model: AccountModel) {
        self.model = model
    }
    
    let model: AccountModel
    @ObservedObject private var viewModel = AccountViewModel()
    @EnvironmentObject var coordinator: AppCoordinator
    
    var body: some View {
        content()
    }
    
    func content() -> some View {
        ZStack {
            VStack {
                HeaderView()
                Spacer()
                BlueButton(text: "Enroll") {
                    viewModel.enroll(force: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
            }
            .ignoresSafeArea()
            VStack {
                Text("Welcome \(model.name)!")
                    .font(.title3)
                    .bold()
                    .padding(.bottom, 20)
                VStack(spacing: 0) {
                    Text("Name:")
                        .bold()
                    Text(model.name)
                        .padding(.bottom, 10)
                    Text("Email:")
                        .bold()
                    Text(model.email)
                }
                .padding(.bottom)
                BlueButton(text: "Log Out") {
                    viewModel.logOut()
                    coordinator.showLoggedOut()
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
