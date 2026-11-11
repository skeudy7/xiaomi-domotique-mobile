import 'dart:convert';

import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/station_info.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';

/// First confirmed sightings, scoped to a saved router and stored on-device.
class KnownDevices {
  KnownDevices(this._storage);

  final SecureStorageService _storage;
  final _pending = <String, Future<Set<String>>>{};
  static const recentWindow = Duration(hours: 24);
  static final _macPattern = RegExp(r'^(?:[0-9a-f]{2}:){5}[0-9a-f]{2}$');

  static String? individualMac(String address) {
    final mac = StationInfo.normalizeMac(address).toLowerCase();
    if (!_macPattern.hasMatch(mac) || mac == '00:00:00:00:00:00') return null;
    final firstByte = int.parse(mac.substring(0, 2), radix: 16);
    return firstByte.isEven ? mac : null;
  }

  static bool isLocalMac(String address) {
    final mac = individualMac(address);
    return mac != null && (int.parse(mac.substring(0, 2), radix: 16) & 2) != 0;
  }

  Future<Set<String>> observe(String routerId, List<Client> clients) {
    final candidates = {
      for (final client in clients)
        if (client.isOnline == true)
          if (individualMac(client.macAddress) case final String mac)
            if (!isLocalMac(mac)) mac,
    };
    if (candidates.isEmpty) return Future.value(const {});
    final previous = _pending[routerId];
    final operation = (previous ?? Future.value(const <String>{})).then(
      (_) => _record(routerId, candidates),
      onError: (Object _, StackTrace _) => _record(routerId, candidates),
    );
    _pending[routerId] = operation;
    return operation.whenComplete(() {
      if (identical(_pending[routerId], operation)) _pending.remove(routerId);
    });
  }

  Future<Set<String>> _record(String routerId, Set<String> candidates) async {
    final key = 'knownDevices:$routerId';
    final stored = await _storage.readValue(key);
    final previous = stored == null
        ? <String, dynamic>{}
        : jsonDecode(stored) as Map<String, dynamic>;
    final now = DateTime.now().millisecondsSinceEpoch;
    final threshold = now - recentWindow.inMilliseconds;
    final updated = Map<String, dynamic>.of(previous);
    for (final mac in candidates) {
      updated.putIfAbsent(mac, () => stored == null ? null : now);
    }
    if (updated.length != previous.length) {
      await _storage.writeValue(key, jsonEncode(updated));
    }
    return {
      for (final mac in candidates)
        if (updated[mac] case final int seenAt)
          if (seenAt >= threshold && seenAt <= now) mac,
    };
  }
}
