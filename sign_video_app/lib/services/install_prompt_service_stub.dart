class InstallPromptPlatform {
  bool get isSupported => false;
  bool get canInstall => false;
  bool get isInstalled => false;

  void initialize(void Function() onChanged) {}

  Future<bool> install() async => false;
}
