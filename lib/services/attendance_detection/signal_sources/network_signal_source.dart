import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:network_info_plus/network_info_plus.dart';

/// Narrow interface for the *optional* workplace Wi-Fi signal (see
/// docs/AUTO_ATTENDANCE_DESIGN.md sections 4 and 10 —
/// "Wi-Fi must be treated as an optional additional signal, not a mandatory
/// dependency"). Returns:
///  - `true`/`false` when the currently-connected network could be compared
///    against a configured workplace SSID,
///  - `null` when unavailable for any reason (no SSID configured, no
///    permission, platform restriction, or a read failure) — the confidence
///    engine treats `null` as "this evidence type is unavailable" and
///    renormalizes around the remaining signals rather than penalizing the
///    episode. The engine reaches full confidence without this signal.
abstract class NetworkSignalSource {
  Future<bool?> isConnectedToWorkplaceNetwork();
}

/// Default no-op source: always unavailable. Used when the user hasn't
/// configured a workplace Wi-Fi network name.
class UnavailableNetworkSignalSource implements NetworkSignalSource {
  const UnavailableNetworkSignalSource();

  @override
  Future<bool?> isConnectedToWorkplaceNetwork() async => null;
}

/// [NetworkSignalSource] backed by `network_info_plus`, comparing the
/// currently-connected Wi-Fi SSID against a user-configured workplace SSID.
///
/// Deliberately Android-only: iOS restricts SSID access to apps holding the
/// "Access WiFi Information" entitlement (which this app does not request —
/// see docs section 10), and `network_info_plus` itself documents that iOS
/// 13+ returns null for `getWifiName()` without it. Rather than requesting
/// an entitlement for a signal the architecture already treats as optional,
/// this source reports unavailable on every non-Android platform.
class WifiNetworkSignalSource implements NetworkSignalSource {
  final String? Function() workplaceSsidProvider;
  final NetworkInfo _networkInfo;

  WifiNetworkSignalSource({
    required this.workplaceSsidProvider,
    NetworkInfo? networkInfo,
  }) : _networkInfo = networkInfo ?? NetworkInfo();

  @override
  Future<bool?> isConnectedToWorkplaceNetwork() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;

    final configured = workplaceSsidProvider()?.trim();
    if (configured == null || configured.isEmpty) return null;

    try {
      final current = await _networkInfo.getWifiName();
      if (current == null) return null;
      // Android commonly wraps the SSID in quotes (e.g. `"MyOfficeWifi"`).
      final normalized = current.replaceAll('"', '').trim();
      if (normalized.isEmpty) return null;
      return normalized.toLowerCase() == configured.toLowerCase();
    } catch (_) {
      return null;
    }
  }
}
