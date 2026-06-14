class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final Map<String, String> _credentials = {
    'admin': 'admin123',
    'guru': 'guru123',
  };

  String? login(String username, String password) {
    final normalizedUsername = username.trim().toLowerCase();
    final normalizedPassword = password.trim();

    final expectedPassword = _credentials[normalizedUsername];
    if (expectedPassword == null || expectedPassword != normalizedPassword) {
      return null;
    }

    if (normalizedUsername == 'admin') {
      return 'Admin';
    }

    return 'Guru';
  }
}
