/// Production developer benchmark utility for recording and formatting
/// real-world business card scan tests without storing any PII.
class CardScanBenchmarkEntry {
  final String cardId;
  final bool cardDetectionSuccess;
  final String captureQualityResult;
  final String perspectiveCorrectionUsed; // 'perspective_rectified', 'viewfinder_roi_crop', 'full_image_fallback'
  final bool? nameCorrect;
  final bool? companyCorrect;
  final bool? jobTitleCorrect;
  final bool? phoneCorrect;
  final bool? emailCorrect;
  final bool? websiteCorrect;
  final bool? addressCorrect;
  final int mlKitProcessingTimeMs;
  final int paddleProcessingTimeMs;
  final int totalProcessingTimeMs;

  const CardScanBenchmarkEntry({
    required this.cardId,
    required this.cardDetectionSuccess,
    required this.captureQualityResult,
    required this.perspectiveCorrectionUsed,
    this.nameCorrect,
    this.companyCorrect,
    this.jobTitleCorrect,
    this.phoneCorrect,
    this.emailCorrect,
    this.websiteCorrect,
    this.addressCorrect,
    required this.mlKitProcessingTimeMs,
    required this.paddleProcessingTimeMs,
    required this.totalProcessingTimeMs,
  });

  Map<String, dynamic> toJson() => {
        'cardId': cardId,
        'cardDetectionSuccess': cardDetectionSuccess,
        'captureQualityResult': captureQualityResult,
        'perspectiveCorrectionUsed': perspectiveCorrectionUsed,
        'nameCorrect': nameCorrect,
        'companyCorrect': companyCorrect,
        'jobTitleCorrect': jobTitleCorrect,
        'phoneCorrect': phoneCorrect,
        'emailCorrect': emailCorrect,
        'websiteCorrect': websiteCorrect,
        'addressCorrect': addressCorrect,
        'mlKitProcessingTimeMs': mlKitProcessingTimeMs,
        'paddleProcessingTimeMs': paddleProcessingTimeMs,
        'totalProcessingTimeMs': totalProcessingTimeMs,
      };

  String toMarkdownRow() {
    String boolStr(bool? val) {
      if (val == null) return 'N/A';
      return val ? 'PASS' : 'FAIL';
    }

    return '| $cardId '
        '| ${cardDetectionSuccess ? "YES" : "NO"} '
        '| $captureQualityResult '
        '| $perspectiveCorrectionUsed '
        '| ${boolStr(nameCorrect)} '
        '| ${boolStr(companyCorrect)} '
        '| ${boolStr(jobTitleCorrect)} '
        '| ${boolStr(phoneCorrect)} '
        '| ${boolStr(emailCorrect)} '
        '| ${boolStr(websiteCorrect)} '
        '| ${boolStr(addressCorrect)} '
        '| ${mlKitProcessingTimeMs}ms '
        '| ${paddleProcessingTimeMs}ms '
        '| ${totalProcessingTimeMs}ms |';
  }
}

/// Development-only benchmark reporter aggregating manual test runs for 30-50 real cards.
class CardScanBenchmarkReporter {
  final List<CardScanBenchmarkEntry> _entries = [];

  List<CardScanBenchmarkEntry> get entries => List.unmodifiable(_entries);

  void recordEntry(CardScanBenchmarkEntry entry) {
    _entries.add(entry);
  }

  void clear() {
    _entries.clear();
  }

  String generateMarkdownReport() {
    if (_entries.isEmpty) {
      return 'No benchmark entries recorded.';
    }

    final buffer = StringBuffer();
    buffer.writeln('# Physical Business Card Scanner Benchmark Report');
    buffer.writeln();
    buffer.writeln('> [!NOTE]');
    buffer.writeln(
        '> This benchmark log records categorical correctness and performance metrics ONLY. No PII is collected.');
    buffer.writeln();
    buffer.writeln(
        '| Card ID | Detected | Quality | Geometry Used | Name | Company | Title | Phone | Email | Web | Addr | ML Kit | Paddle | Total |');
    buffer.writeln(
        '| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |');

    for (final e in _entries) {
      buffer.writeln(e.toMarkdownRow());
    }

    buffer.writeln();
    buffer.writeln('## Summary Statistics');
    buffer.writeln();
    final total = _entries.length;
    final detectedCount = _entries.where((e) => e.cardDetectionSuccess).length;
    final qualityPassCount = _entries.where((e) => e.captureQualityResult.toLowerCase() == 'good').length;
    final rectifiedCount = _entries.where((e) => e.perspectiveCorrectionUsed == 'perspective_rectified').length;
    final roiCropCount = _entries.where((e) => e.perspectiveCorrectionUsed == 'viewfinder_roi_crop').length;

    double pct(int count, int total) => total == 0 ? 0.0 : (count / total) * 100.0;

    buffer.writeln('- **Total Cards Tested**: $total');
    buffer.writeln('- **Card Detection Rate**: $detectedCount / $total (${pct(detectedCount, total).toStringAsFixed(1)}%)');
    buffer.writeln('- **Quality Passing Rate**: $qualityPassCount / $total (${pct(qualityPassCount, total).toStringAsFixed(1)}%)');
    buffer.writeln('- **Transformations**: $rectifiedCount rectified, $roiCropCount ROI cropped');

    // Field accuracies
    final namePass = _entries.where((e) => e.nameCorrect == true).length;
    final compPass = _entries.where((e) => e.companyCorrect == true).length;
    final titlePass = _entries.where((e) => e.jobTitleCorrect == true).length;
    final phonePass = _entries.where((e) => e.phoneCorrect == true).length;
    final emailPass = _entries.where((e) => e.emailCorrect == true).length;
    final webPass = _entries.where((e) => e.websiteCorrect == true).length;
    final addrPass = _entries.where((e) => e.addressCorrect == true).length;

    buffer.writeln();
    buffer.writeln('### Field Extraction Rates');
    buffer.writeln('- **Name**: $namePass / $total (${pct(namePass, total).toStringAsFixed(1)}%)');
    buffer.writeln('- **Company**: $compPass / $total (${pct(compPass, total).toStringAsFixed(1)}%)');
    buffer.writeln('- **Job Title**: $titlePass / $total (${pct(titlePass, total).toStringAsFixed(1)}%)');
    buffer.writeln('- **Phone**: $phonePass / $total (${pct(phonePass, total).toStringAsFixed(1)}%)');
    buffer.writeln('- **Email**: $emailPass / $total (${pct(emailPass, total).toStringAsFixed(1)}%)');
    buffer.writeln('- **Website**: $webPass / $total (${pct(webPass, total).toStringAsFixed(1)}%)');
    buffer.writeln('- **Address**: $addrPass / $total (${pct(addrPass, total).toStringAsFixed(1)}%)');

    // Latency averages
    if (total > 0) {
      final avgMlKit = _entries.map((e) => e.mlKitProcessingTimeMs).reduce((a, b) => a + b) ~/ total;
      final avgPaddle = _entries.map((e) => e.paddleProcessingTimeMs).reduce((a, b) => a + b) ~/ total;
      final avgTotal = _entries.map((e) => e.totalProcessingTimeMs).reduce((a, b) => a + b) ~/ total;
      buffer.writeln();
      buffer.writeln('### Average Execution Times');
      buffer.writeln('- **Google ML Kit**: ${avgMlKit}ms');
      buffer.writeln('- **PaddleOCR PP-OCRv5**: ${avgPaddle}ms');
      buffer.writeln('- **Total End-to-End**: ${avgTotal}ms');
    }

    return buffer.toString();
  }
}
