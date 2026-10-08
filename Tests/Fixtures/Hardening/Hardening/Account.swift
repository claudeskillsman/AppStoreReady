import GoogleSignIn

final class AccountService {
    func signIn() { GIDSignIn.sharedInstance.signIn(withPresenting: UIViewController()) { _, _ in } }
    func signUp(email: String) {}
}
