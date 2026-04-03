import 'video_download_service_stub.dart'
    if (dart.library.html) 'video_download_service_web.dart';

class VideoDownloadService {
  VideoDownloadService._();

  static final VideoDownloadService instance = VideoDownloadService._();

  Future<void> download({required String url, required String fileName}) {
    return VideoDownloadPlatform.instance.download(
      url: url,
      fileName: fileName,
    );
  }
}
