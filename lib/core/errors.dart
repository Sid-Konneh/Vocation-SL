/// Typed failures surfaced by the data layer. The UI maps these to
/// friendly messages with [AppException.userMessage].
sealed class AppException implements Exception {
  const AppException(this.message);
  final String message;

  String get userMessage;

  static String describe(Object error) =>
      error is AppException ? error.userMessage : 'Something went wrong. Please try again.';

  @override
  String toString() => '$runtimeType: $message';
}

class NetworkException extends AppException {
  const NetworkException([super.message = 'No internet connection']);
  @override
  String get userMessage => 'You\'re offline. Check your connection and try again.';
}

class ServerException extends AppException {
  const ServerException([super.message = 'Server error']);
  @override
  String get userMessage => message == 'Server error' || message.isEmpty
      ? 'Our servers had a problem. Please try again in a moment.'
      // Show the server's reason so problems can be reported and fixed.
      : 'That didn\'t work: ${message.length > 160 ? '${message.substring(0, 160)}…' : message}';
}

class AuthException extends AppException {
  const AuthException(super.message);
  @override
  String get userMessage => message;
}

/// Not a failure: the account was created but the email must be confirmed.
class EmailConfirmationRequired extends AppException {
  const EmailConfirmationRequired(this.email) : super('Email confirmation required');
  final String email;
  @override
  String get userMessage => 'We sent a confirmation link to $email. Open it, then sign in.';
}

class NotFoundException extends AppException {
  const NotFoundException([super.message = 'Not found']);
  @override
  String get userMessage => 'This item is no longer available.';
}

class ValidationException extends AppException {
  const ValidationException(super.message);
  @override
  String get userMessage => message;
}
