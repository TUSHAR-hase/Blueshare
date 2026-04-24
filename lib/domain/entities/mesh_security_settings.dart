class MeshSecuritySettings {
  const MeshSecuritySettings({this.passkey = ''});

  final String passkey;

  String get normalizedPasskey => passkey.trim();
  bool get isEnabled => normalizedPasskey.isNotEmpty;

  String get maskedPasskey {
    final value = normalizedPasskey;
    if (value.isEmpty) {
      return 'Not configured';
    }
    if (value.length <= 4) {
      return '*' * value.length;
    }
    return '${value.substring(0, 2)}${'*' * (value.length - 4)}${value.substring(value.length - 2)}';
  }

  MeshSecuritySettings copyWith({String? passkey, bool clearPasskey = false}) {
    return MeshSecuritySettings(
      passkey: clearPasskey ? '' : passkey ?? this.passkey,
    );
  }
}
