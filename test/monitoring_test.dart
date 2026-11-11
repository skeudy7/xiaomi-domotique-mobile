import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/services/known_devices.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/services/throughput_service.dart';
import 'package:luci_mobile/state/monitoring_providers.dart';

class _MemoryStorage extends SecureStorageService {
  final values = <String, String>{};

  @override
  Future<String?> readValue(String key) async => values[key];

  @override
  Future<void> writeValue(String key, String value) async {
    values[key] = value;
  }
}

Client _client(String mac, {bool? online = true}) =>
    Client(ipAddress: '', hostname: '', macAddress: mac, isOnline: online);

void main() {
  test(
    'first sightings are scoped to each router and stored locally',
    () async {
      final storage = _MemoryStorage();
      final known = KnownDevices(storage);
      final baseline = _client('00:10:00:00:00:01');
      final fresh = _client('00-10-00-00-00-02');
      final local = _client('02:10:00:00:00:03');
      final unknown = _client('00:10:00:00:00:04', online: null);

      expect(await known.observe('A', [baseline]), isEmpty);
      expect(await known.observe('B', [fresh]), isEmpty);
      expect(await known.observe('A', [baseline, fresh, local, unknown]), {
        '00:10:00:00:00:02',
      });
      expect(await KnownDevices(storage).observe('A', [fresh]), {
        '00:10:00:00:00:02',
      });
      expect(await known.observe('B', [fresh]), isEmpty);
      expect(KnownDevices.isLocalMac(local.macAddress), isTrue);
      expect(KnownDevices.individualMac('FF:FF:FF:FF:FF:FF'), isNull);
    },
  );

  test('WAN status requires an identifiable interface with reported state', () {
    expect(ThroughputService.reportedWanLink(null), isNull);
    expect(
      ThroughputService.reportedWanLink({
        'interface': [
          {'interface': 'lan', 'up': true},
          {'interface': 'wan'},
        ],
      }),
      isNull,
    );
    expect(
      ThroughputService.reportedWanLink({
        'interface': [
          {'interface': 'wan', 'up': false},
          {
            'interface': 'lte',
            'up': true,
            'route': [
              {'target': '::', 'mask': 0},
            ],
          },
        ],
      }),
      isTrue,
    );
  });

  test('firewall summary uses reported WAN zones and enabled DNAT rules', () {
    expect(summarizeWanFirewall({}), isNull);
    final summary = summarizeWanFirewall({
      'outside': {
        '.type': 'zone',
        'name': 'outside',
        'network': ['wan', 'wan6'],
      },
      'lan': {'.type': 'zone', 'name': 'lan', 'masq': '1'},
      'forward': {'.type': 'redirect', 'src': 'outside', 'target': 'DNAT'},
      'disabled': {'.type': 'redirect', 'src': 'outside', 'enabled': '0'},
      'snat': {'.type': 'redirect', 'src': 'outside', 'target': 'SNAT'},
      'internal': {'.type': 'redirect', 'src': 'lan'},
    });
    expect(summary?.inputPolicies, {'outside': null});
    expect(summary?.enabledForwards, 1);
  });

  test('throughput needs two comparable counter samples', () async {
    final service = ThroughputService();
    service.updateThroughput(
      {
        'eth0': {'rx_bytes': 10, 'tx_bytes': 10},
      },
      {'eth0'},
    );
    expect(service.rxHistory, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 130));
    service.updateThroughput(
      {
        'eth0': {'rx_bytes': 10, 'tx_bytes': 10},
      },
      {'eth0'},
    );
    expect(service.rxHistory, [0.0]);
    service.updateThroughput(
      {
        'eth0': {'rx_bytes': 1, 'tx_bytes': 10},
      },
      {'eth0'},
    );
    expect(service.rxHistory, isEmpty);
    service.updateThroughput(
      {
        'eth0': {'rx_bytes': 12},
      },
      {'eth0'},
    );
    expect(service.rxHistory, isEmpty);
    expect(service.getRxHistoryForInterface('eth0'), isEmpty);
  });
}
