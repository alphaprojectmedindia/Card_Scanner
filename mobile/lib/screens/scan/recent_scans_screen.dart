import 'package:flutter/material.dart';
import '../../models/qr/qr_scan_models.dart';
import '../../services/qr/qr_content_parser.dart';
import '../../services/qr/qr_recent_scans_service.dart';
import '../../theme/app_spacing.dart';
import 'qr_result_screen.dart';

/// Screen displaying local, privacy-safe recent QR scans.
class RecentScansScreen extends StatefulWidget {
  final QrRecentScansService? storageService;

  const RecentScansScreen({super.key, this.storageService});

  @override
  State<RecentScansScreen> createState() => _RecentScansScreenState();
}

class _RecentScansScreenState extends State<RecentScansScreen> {
  late final QrRecentScansService _storageService;
  List<RecentQrScan> _scans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _storageService = widget.storageService ?? QrRecentScansService();
    _loadScans();
  }

  Future<void> _loadScans() async {
    setState(() => _isLoading = true);
    final items = await _storageService.getRecentScans();
    if (mounted) {
      setState(() {
        _scans = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Scan History?'),
        content: const Text(
          'This will delete all saved recent scans from this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm_clear_history_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storageService.clearHistory();
      await _loadScans();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scan history cleared'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _openScanResult(RecentQrScan scan) {
    final parsed = QrContentParser.parse(scan.safePayload);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QrResultScreen(scanResult: parsed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recent Scans'),
        actions: [
          if (_scans.isNotEmpty)
            IconButton(
              key: const Key('clear_history_button'),
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Clear History',
              onPressed: _handleClearHistory,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _scans.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 64,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'No Recent Scans',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Scanned QR codes will safely appear here.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: AppSpacing.pagePadding,
                  itemCount: _scans.length,
                  separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (ctx, index) {
                    final item = _scans[index];
                    return Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppSpacing.radiusMd,
                        side: BorderSide(color: theme.colorScheme.outlineVariant),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: AppSpacing.radiusSm,
                          ),
                          child: Icon(
                            Icons.qr_code_rounded,
                            color: theme.colorScheme.onPrimaryContainer,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          item.displayTitle,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          item.displaySubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openScanResult(item),
                      ),
                    );
                  },
                ),
    );
  }
}
