import 'package:flutter_test/flutter_test.dart';
import 'package:office_log/services/attendance_detection/signal_sources/network_signal_source.dart';

void main() {
  group('isUnknownSsidSentinel', () {
    test('matches Android\'s "cannot determine SSID" sentinel', () {
      expect(isUnknownSsidSentinel('<unknown ssid>'), isTrue);
      expect(isUnknownSsidSentinel('<UNKNOWN SSID>'), isTrue);
    });

    test('does not match a real network name', () {
      expect(isUnknownSsidSentinel('OfficeGuestWifi'), isFalse);
      expect(isUnknownSsidSentinel(''), isFalse);
    });
  });
}
