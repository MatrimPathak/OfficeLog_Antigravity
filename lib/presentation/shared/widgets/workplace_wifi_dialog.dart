import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/providers.dart';

/// Lets the user optionally name their workplace Wi-Fi network so the
/// automatic attendance detection engine can use it as one extra evidence
/// signal (Android only — see docs/AUTO_ATTENDANCE_DESIGN.md sections 4 and
/// 10). Entirely optional: leaving this blank does not degrade automatic
/// detection, it just means the engine reaches its decisions from location
/// and activity evidence alone.
class WorkplaceWifiDialog extends ConsumerStatefulWidget {
  const WorkplaceWifiDialog({super.key});

  @override
  ConsumerState<WorkplaceWifiDialog> createState() => _WorkplaceWifiDialogState();
}

class _WorkplaceWifiDialogState extends ConsumerState<WorkplaceWifiDialog> {
  late TextEditingController _controller;
  bool _detecting = false;
  String? _detectError;

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(workplaceWifiSsidProvider) ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _useCurrentNetwork() async {
    setState(() {
      _detecting = true;
      _detectError = null;
    });
    try {
      final name = await NetworkInfo().getWifiName();
      final normalized = name?.replaceAll('"', '').trim();
      if (!mounted) return;
      if (normalized == null || normalized.isEmpty) {
        setState(() {
          _detectError = "Couldn't detect a connected Wi-Fi network.";
        });
      } else {
        setState(() {
          _controller.text = normalized;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _detectError = "Couldn't detect a connected Wi-Fi network.";
      });
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_rounded,
                color: AppTheme.primaryColor,
                size: 32,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Workplace Wi-Fi (Optional)',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'On Android, naming your office Wi-Fi network gives auto '
              'check-in one extra signal. This is optional — automatic '
              'detection works without it, and it has no effect on iOS.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF9E9E9E),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'e.g. OfficeGuestWifi',
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                  ),
                ),
              ),
              autofocus: true,
            ),
            if (_isAndroid) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _detecting ? null : _useCurrentNetwork,
                  icon: _detecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find_rounded, size: 18),
                  label: Text(_detecting ? 'Detecting…' : 'Use current Wi-Fi'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              if (_detectError != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _detectError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        backgroundColor: Theme.of(context).dividerColor.withValues(alpha: 0.05),
                        foregroundColor: Theme.of(context).colorScheme.onSurface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
                        await ref
                            .read(workplaceWifiSsidProvider.notifier)
                            .update(_controller.text);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
