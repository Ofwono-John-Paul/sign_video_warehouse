import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'replacement_video_preview_controller_io.dart'
    if (dart.library.html) 'replacement_video_preview_controller_web.dart';

Future<VideoPlayerController?> createReplacementPreviewController({
  String? fileName,
  String? path,
  Uint8List? bytes,
}) {
  return createReplacementPreviewControllerImpl(
    fileName: fileName,
    path: path,
    bytes: bytes,
  );
}
