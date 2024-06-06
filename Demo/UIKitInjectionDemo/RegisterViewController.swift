import UIKit
import SwiftUI
import Combine
import OwnIDGigyaSDK
import Gigya

final class RegisterViewController: UIViewController {
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var ownIdContainerView: UIView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    var ownIDViewModel: OwnID.FlowsSDK.RegisterView.ViewModel!
    private lazy var ownIdButton = makeOwnIDButton()
    private var isOwnIDEnabled = false
    private var bag = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let emailPublisher = NotificationCenter.default
            .publisher(for: UITextField.textDidChangeNotification, object: emailTextField)
            .map({ ($0.object as? UITextField)?.text ?? "" })
        
        let ownIDViewModel = OwnID.GigyaSDK.registrationViewModel(instance: Gigya.sharedInstance(), loginIdPublisher: emailPublisher.eraseToAnyPublisher())
        self.ownIDViewModel = ownIDViewModel
        subscribe(to: ownIDViewModel.integrationEventPublisher)
        emailTextField.addTarget(self, action: #selector(RegisterViewController.textFieldDidChange(_:)), for: .editingChanged)
        addChild(ownIdButton)
        ownIdContainerView.addSubview(ownIdButton.view)
        ownIdButton.didMove(toParent: self)
    }
    
    func makeOwnIDButton() -> UIHostingController<OwnID.FlowsSDK.RegisterView> {
        let headerView = OwnID.GigyaSDK.createRegisterView(viewModel: ownIDViewModel)
        let headerVC = UIHostingController(rootView: headerView)
        headerVC.view.translatesAutoresizingMaskIntoConstraints = false
        return headerVC
    }
    
    @objc func textFieldDidChange(_ textField: UITextField) {
    }
    
    @IBAction func registerTapped(_ sender: UIButton) {
        activityIndicator.startAnimating()
        if isOwnIDEnabled {
            ownIDViewModel.register()
        } else {
            Gigya.sharedInstance().register(email: emailTextField.text ?? "",
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
    }
    
    func subscribe(to eventsPublisher: OwnID.RegistrationPublisher) {
        eventsPublisher
            .sink { [unowned self] event in
                switch event {
                case .success(let event):
                    switch event {
                    case .readyToRegister:
                        isOwnIDEnabled = true
                        
                    case .userRegisteredAndLoggedIn:
                        fetchProfile()
                        
                    case .loading:
                        break
                        
                    case .resetTapped:
                        isOwnIDEnabled = false
                    }
                    
                case .failure(let error):
                    print(error.localizedDescription)
                }
            }
            .store(in: &bag)
    }
    
    func fetchProfile() {
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

