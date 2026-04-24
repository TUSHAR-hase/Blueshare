class BluetoothPeer {
  static const Duration availabilityWindow = Duration(seconds: 75);
  static const String unknownLabel = 'Unknown device';

  const BluetoothPeer({
    required this.address,
    required this.name,
    this.nickname,
    this.rssi,
    this.deviceClass,
    this.majorDeviceClass,
    this.isBonded = false,
    this.isConnected = false,
    this.lastSeen,
  });

  final String address;
  final String name;
  final String? nickname;
  final int? rssi;
  final int? deviceClass;
  final int? majorDeviceClass;
  final bool isBonded;
  final bool isConnected;
  final DateTime? lastSeen;

  String get displayName {
    final alias = nickname?.trim();
    if (alias != null && alias.isNotEmpty) {
      return alias;
    }
    final trimmed = name.trim();
    if (hasResolvedName) {
      return trimmed;
    }
    return unknownLabel;
  }

  bool get hasResolvedName {
    final trimmed = name.trim().toLowerCase();
    return trimmed.isNotEmpty &&
        trimmed != 'unknown device' &&
        trimmed != 'unknown';
  }

  String get signalLabel {
    final value = rssi;
    if (value == null) {
      return isConnected ? 'Connected' : 'Scan to measure';
    }
    if (value >= -55) {
      return 'Strong ($value dBm)';
    }
    if (value >= -70) {
      return 'Good ($value dBm)';
    }
    if (value >= -85) {
      return 'Fair ($value dBm)';
    }
    return 'Weak ($value dBm)';
  }

  bool get isPhone => majorDeviceClass == BluetoothMajorDeviceClass.phone;
  bool get isLikelyMobileDevice {
    if (_hasExcludedDeviceKeywords) {
      return false;
    }

    switch (majorDeviceClass) {
      case BluetoothMajorDeviceClass.phone:
        return true;
      case BluetoothMajorDeviceClass.audioVideo:
      case BluetoothMajorDeviceClass.peripheral:
      case BluetoothMajorDeviceClass.imaging:
      case BluetoothMajorDeviceClass.wearable:
      case BluetoothMajorDeviceClass.toy:
      case BluetoothMajorDeviceClass.health:
      case BluetoothMajorDeviceClass.computer:
        return false;
      default:
        return true;
    }
  }

  bool get isAvailableNow {
    if (isConnected) {
      return true;
    }
    final seenAt = lastSeen;
    if (seenAt == null) {
      return false;
    }
    return DateTime.now().difference(seenAt) <= availabilityWindow;
  }

  bool get isTransferCandidate => isLikelyMobileDevice && isAvailableNow;

  bool get _hasExcludedDeviceKeywords {
    final value = displayName.toLowerCase();
    const keywords = <String>[
      'buds',
      'earbud',
      'earbuds',
      'airpods',
      'tws',
      'headset',
      'headphone',
      'headphones',
      'speaker',
      'soundbar',
      'tv',
      'android tv',
      'smart tv',
      'bravia',
      'watch',
      'band',
      'laptop',
      'notebook',
      'desktop',
      'printer',
      'projector',
      'car',
    ];
    return keywords.any(value.contains);
  }

  BluetoothPeer copyWith({
    String? address,
    String? name,
    String? nickname,
    bool clearNickname = false,
    int? rssi,
    bool clearRssi = false,
    int? deviceClass,
    bool clearDeviceClass = false,
    int? majorDeviceClass,
    bool clearMajorDeviceClass = false,
    bool? isBonded,
    bool? isConnected,
    DateTime? lastSeen,
  }) {
    return BluetoothPeer(
      address: address ?? this.address,
      name: name ?? this.name,
      nickname: clearNickname ? null : nickname ?? this.nickname,
      rssi: clearRssi ? null : rssi ?? this.rssi,
      deviceClass: clearDeviceClass ? null : deviceClass ?? this.deviceClass,
      majorDeviceClass:
          clearMajorDeviceClass
              ? null
              : majorDeviceClass ?? this.majorDeviceClass,
      isBonded: isBonded ?? this.isBonded,
      isConnected: isConnected ?? this.isConnected,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

class BluetoothMajorDeviceClass {
  const BluetoothMajorDeviceClass._();

  static const int computer = 0x0100;
  static const int phone = 0x0200;
  static const int audioVideo = 0x0400;
  static const int peripheral = 0x0500;
  static const int imaging = 0x0600;
  static const int wearable = 0x0700;
  static const int toy = 0x0800;
  static const int health = 0x0900;
}
