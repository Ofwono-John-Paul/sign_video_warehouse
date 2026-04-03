import 'package:flutter/foundation.dart';

import 'install_prompt_service_stub.dart'
    if (dart.library.html) 'install_prompt_service_web.dart';

class InstallPromptService extends ChangeNotifier {
  InstallPromptService._() : _platform = InstallPromptPlatform();

  static final InstallPromptService instance = InstallPromptService._();

  final InstallPromptPlatform _platform;
  bool _initialized = false;

  bool get isSupported => _platform.isSupported;
  bool get canInstall => _platform.canInstall;
  bool get isInstalled => _platform.isInstalled;

  void initialize() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _platform.initialize(_notifyListeners);
  }

  Future<bool> install() => _platform.install();

  void _notifyListeners() {
    notifyListeners();
  }
}
