import 'dart:html' as html;

class VideoDownloadPlatform {
  VideoDownloadPlatform._();

  static final VideoDownloadPlatform instance = VideoDownloadPlatform._();

  Future<void> download({required String url, required String fileName}) async {
    final anchor = html.AnchorElement(href: url)
      ..download = fileName
      ..target = '_blank'
      ..rel = 'noopener noreferrer';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  }
}
