const passwordRequirements =
    'Use 8–128 characters with at least one lowercase letter (a–z), '
    'uppercase letter (A–Z), number (0–9), and special character (such as !, @, or #).';

String? validateNewPassword(String? value) {
  if (value == null || value.isEmpty) return 'Please enter a password.';
  if (value.length < 8) return 'Password must contain at least 8 characters.';
  if (value.length > 128) {
    return 'Password must contain at most 128 characters.';
  }
  if (!RegExp(r'[a-z]').hasMatch(value)) {
    return 'Password must contain at least one lowercase letter (a–z).';
  }
  if (!RegExp(r'[A-Z]').hasMatch(value)) {
    return 'Password must contain at least one uppercase letter (A–Z).';
  }
  if (!RegExp(r'[0-9]').hasMatch(value)) {
    return 'Password must contain at least one number (0–9).';
  }
  // Printable ASCII punctuation; spaces do not count as special characters.
  if (!RegExp(r'[\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E]').hasMatch(value)) {
    return 'Password must contain at least one special character (such as !, @, or #).';
  }
  return null;
}
