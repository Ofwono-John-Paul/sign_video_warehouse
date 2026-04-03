class VideoDownloadPlatform {
  VideoDownloadPlatform._();

  static final VideoDownloadPlatform instance = VideoDownloadPlatform._();

  Future<void> download({
    required String url,
    required String fileName,
  }) async {}
}
