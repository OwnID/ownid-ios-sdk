import UIKit

struct AccountModel: Identifiable, Decodable, Equatable {
    init(name: String, email: String) {
        self.name = name
        self.email = email
    }
    
    var id = UUID().uuidString
    let name: String
    let email: String
}

final class AccountViewController: UIViewController {
    @IBOutlet weak var emailLabel: UILabel!
    
    var model: AccountModel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        emailLabel.text = model.email
    }
    
    @IBAction func logOutTapped(_ sender: UIButton) {
        dismiss(animated: true)
    }
}
