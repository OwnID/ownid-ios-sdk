import UIKit
import SwiftUI
import Combine
import OwnIDGigyaSDK
import Gigya

final class LoginViewController: UIViewController {
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var ownIDContainerView: UIView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    private var ownIDViewModel: OwnID.FlowsSDK.LoginView.ViewModel!
    private lazy var ownIDButton = makeOwnIDButton()
    private var bag = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let emailPublisher = NotificationCenter.default
            .publisher(for: UITextField.textDidChangeNotification, object: emailTextField)
            .map({ ($0.object as? UITextField)?.text ?? "" })
        
        let ownIDViewModel = OwnID.GigyaSDK.loginViewModel(instance: Gigya.sharedInstance(), loginIdPublisher: emailPublisher.eraseToAnyPublisher())
        self.ownIDViewModel = ownIDViewModel
        subscribe(to: ownIDViewModel.integrationEventPublisher)
        addChild(ownIDButton)
        ownIDContainerView.addSubview(ownIDButton.view)
        ownIDButton.didMove(toParent: self)
    }
    
    private func makeOwnIDButton() -> UIHostingController<OwnID.FlowsSDK.LoginView> {
        let ownIDView = OwnID.GigyaSDK.createLoginView(viewModel: ownIDViewModel)
        let ownIDVC = UIHostingController(rootView: ownIDView)
        ownIDVC.view.translatesAutoresizingMaskIntoConstraints = false
        return ownIDVC
    }
    
    @IBAction func loginTapped(_ sender: UIButton) {
        activityIndicator.startAnimating()
        Gigya.sharedInstance().login(loginId: emailTextField.text ?? "",
                                     password: passwordTextField.text ?? "") { [weak self] result in
            switch result {
            case .success:
                self?.fetchProfile()
            case .failure(let error):
                self?.activityIndicator.stopAnimating()
                print(error.error.localizedDescription)
            }
        }
    }
    
    private func subscribe(to eventsPublisher: OwnID.LoginPublisher) {
        eventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] event in
                switch event {
                case .success(let event):
                    switch event {
                    case .loggedIn:
                        fetchProfile()
                        
                    case .loading:
                        print("Loading state")
                    }
                    
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
            .store(in: &bag)
    }
    
    private func fetchProfile() {
        Task.init {
            if let profile = try? await Gigya.sharedInstance().getAccount(true).profile {
                let email = profile.email ?? ""
                let name = profile.firstName ?? ""
                let model = AccountModel(name: name, email: email)
                await MainActor.run {
                    activityIndicator.stopAnimating()
                    let storyboard = UIStoryboard(name: "Main", bundle: nil)
                    if let viewController = storyboard.instantiateViewController(withIdentifier: "AccountViewController") as? AccountViewController {
                        viewController.model = model
                        present(viewController, animated: true, completion: nil)
                    }
                }
            } else {
                activityIndicator.stopAnimating()
                print("Cannot find logged in profile")
            }
        }
    }
}
