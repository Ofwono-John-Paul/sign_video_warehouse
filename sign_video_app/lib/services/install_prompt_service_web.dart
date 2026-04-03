import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

class InstallPromptPlatform {
  web.Event? _deferredPrompt;
  bool _canInstall = false;
  bool _isInstalled = false;

  bool get isSupported => true;
  bool get canInstall => _canInstall;
  bool get isInstalled => _isInstalled;

  void initialize(void Function() onChanged) {
    _isInstalled = _isAlreadyInstalled();
    _canInstall = false;

    web.window.addEventListener(
      'beforeinstallprompt',
      ((web.Event event) {
        event.preventDefault();
        _deferredPrompt = event;
        if (!_isInstalled) {
          _canInstall = true;
        }
        onChanged();
      }).toJS,
    );

    web.window.addEventListener(
      'appinstalled',
      ((web.Event event) {
        _isInstalled = true;
        _canInstall = false;
        _deferredPrompt = null;
        onChanged();
      }).toJS,
    );

    onChanged();
  }

  Future<bool> install() async {
    final promptEvent = _deferredPrompt;
    if (promptEvent == null || _isInstalled) {
      return false;
    }

    final jsPromptEvent = promptEvent as JSObject;
    jsPromptEvent.callMethod('prompt'.toJS);

    final choicePromise =
        jsPromptEvent.getProperty('userChoice'.toJS) as JSPromise<JSObject>;
    final choice = await choicePromise.toDart;

    final outcome = choice.getProperty('outcome'.toJS).dartify()?.toString();
    final accepted = outcome == 'accepted';

    if (accepted) {
      _isInstalled = true;
      _canInstall = false;
    }

    _deferredPrompt = null;
    return accepted;
  }

  bool _isAlreadyInstalled() {
    final standaloneMode = web.window
        .matchMedia('(display-mode: standalone)')
        .matches;
    final iosStandalone =
        (web.window.navigator as JSObject)
            .getProperty('standalone'.toJS)
            .dartify() ==
        true;
    return standaloneMode || iosStandalone;
  }
}
