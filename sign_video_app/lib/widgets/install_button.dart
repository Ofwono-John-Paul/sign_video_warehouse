import 'package:flutter/material.dart';

import '../services/install_prompt_service.dart';

class InstallButton extends StatefulWidget {
  const InstallButton({super.key});

  @override
  State<InstallButton> createState() => _InstallButtonState();
}

class _InstallButtonState extends State<InstallButton> {
  final InstallPromptService _service = InstallPromptService.instance;

  @override
  void initState() {
    super.initState();
    _service.initialize();
    _service.addListener(_handleServiceChange);
  }

  @override
  void dispose() {
    _service.removeListener(_handleServiceChange);
    super.dispose();
  }

  void _handleServiceChange() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handlePressed() async {
    final accepted = await _service.install();
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(content: Text(accepted ? 'App installed' : 'Install dismissed')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.isSupported || _service.isInstalled || !_service.canInstall) {
      return const SizedBox.shrink();
    }

    return IconButton(
      icon: const Icon(Icons.install_mobile_outlined),
      tooltip: 'Install App',
      onPressed: _handlePressed,
    );
  }
}
