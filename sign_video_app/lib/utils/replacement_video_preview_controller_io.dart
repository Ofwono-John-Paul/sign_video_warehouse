import 'dart:io';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';

Future<VideoPlayerController?> createReplacementPreviewControllerImpl({
  String? fileName,
  String? path,
  Uint8List? bytes,
}) async {
  final value = path?.trim() ?? '';

  // Handle bytes directly - this is the key fix for file picker uploads
  if (bytes != null && bytes.isNotEmpty) {
    final safeName = (fileName ?? 'replacement_video.mp4').trim().isEmpty
        ? 'replacement_video.mp4'
        : (fileName ?? 'replacement_video.mp4').trim();
    final tempDir = Directory.systemTemp.createTempSync('usl_replace_');
    final tempFile = File('${tempDir.path}${Platform.pathSeparator}$safeName');
    await tempFile.writeAsBytes(bytes, flush: true);
    return VideoPlayerController.file(tempFile);
  }

  if (value.isEmpty) return null;

  if (value.startsWith('http://') ||
      value.startsWith('https://') ||
      value.startsWith('blob:')) {
    return VideoPlayerController.networkUrl(Uri.parse(value));
  }

  if (value.startsWith('file:')) {
    return VideoPlayerController.file(File.fromUri(Uri.parse(value)));
  }

  final file = File(value);
  if (await file.exists()) {
    return VideoPlayerController.file(file);
  }

  return null;
}
