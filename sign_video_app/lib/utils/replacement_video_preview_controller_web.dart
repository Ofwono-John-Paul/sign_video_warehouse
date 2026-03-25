import 'dart:html' as html;
import 'dart:typed_data';

import 'package:video_player/video_player.dart';

Future<VideoPlayerController?> createReplacementPreviewControllerImpl({
  String? fileName,
  String? path,
  Uint8List? bytes,
}) async {
  // Handle bytes directly first - this is needed for file picker uploads
  if (bytes != null && bytes.isNotEmpty) {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    return VideoPlayerController.networkUrl(Uri.parse(url));
  }

  final value = path?.trim() ?? '';
  if (value.startsWith('http://') ||
      value.startsWith('https://') ||
      value.startsWith('blob:')) {
    return VideoPlayerController.networkUrl(Uri.parse(value));
  }

  return null;
}
