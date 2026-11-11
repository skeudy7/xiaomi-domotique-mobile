import 'dart:collection';
import 'dart:math';

class ThroughputService {
  final Queue<double> _rxHistory = Queue<double>();
  final Queue<double> _txHistory = Queue<double>();

  double _currentRxRate = 0;
  double _currentTxRate = 0;
  Map<String, dynamic>? _lastStats;
  DateTime? _lastTimestamp;
  Set<String> _lastWanDevices = const {};

  // Per-interface tracking
  final Map<String, Queue<double>> _rxHistoryPerInterface = {};
  final Map<String, Queue<double>> _txHistoryPerInterface = {};
  final Map<String, double> _currentRxRatePerInterface = {};
  final Map<String, double> _currentTxRatePerInterface = {};
  final Map<String, Map<String, dynamic>?> _lastStatsPerInterface = {};
  final Map<String, DateTime?> _lastTimestampPerInterface = {};

  static const int _maxHistoryLength = 50;
  static const double _maxRate = 1000.0 * 1024.0 * 1024.0; // 1 GB/s
  static const double _minElapsedSeconds = 0.1;

  /// The interfaces in a `network.interface dump` that face the internet:
  /// those holding a default route, IPv4 or IPv6, and those named `wan…`.
  /// The name counts even without a route: a WAN that is down, or a
  /// standby `wanb` that takes over after the dump was read, still carries
  /// internet traffic, and the two-second poll reuses the dump. Empty when
  /// neither says - a dumb AP, or a dump that could not be read.
  static List<Map> upstreamInterfaces(Map? interfaceDump) {
    final interfaces = interfaceDump?['interface'];
    if (interfaces is! List) return const [];
    return [
      for (final i in interfaces)
        if (i is Map &&
            i['interface'] != 'loopback' &&
            i['interface'] != 'lo' &&
            (_hasDefaultRoute(i['route']) || _isNamedWan(i)))
          i,
    ];
  }

  /// Netifd's link state, independent of Internet reachability.
  static bool? reportedWanLink(Map? dump) {
    final states = upstreamInterfaces(dump)
        .map((interface) => interface['up'])
        .whereType<bool>();
    return states.isEmpty ? null : states.contains(true);
  }

  /// netifd protocols whose traffic is carried inside another interface's.
  static const _tunnelProtos = {
    'wireguard',
    'openvpn',
    'openconnect',
    'vpnc',
    'l2tp',
    'pptp',
    'sstp',
    'gre',
    'gretap',
    'grev6',
    'grev6tap',
    'ipip',
    'ipip6',
    '6in4',
    '6to4',
    '6rd',
    'dslite',
    'map',
    'xfrm',
    'vti',
    'vtiv6',
  };

  static bool _isTunnel(Map iface) => _tunnelProtos.contains(iface['proto']);

  static bool _isNamedWan(Map iface) =>
      iface['interface']?.toString().startsWith('wan') ?? false;

  static bool _hasDefaultRoute(Object? routes) {
    if (routes is! List) return false;
    return routes.any(
      (r) =>
          r is Map &&
          (r['target'] == '0.0.0.0' || r['target'] == '::') &&
          (r['mask'] == 0 || r['mask'] == '0'),
    );
  }

  /// One device per interface: the layer-3 one, which carries the IP
  /// traffic. Counting `device` as well counted PPPoE twice (the PPPoE
  /// frames on `eth0.2`, then the same traffic again on `pppoe-wan`).
  static String? _countedDevice(Map iface) {
    for (final key in const ['l3_device', 'device']) {
      final value = iface[key]?.toString();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// The devices the combined "all interfaces" graph adds up.
  ///
  /// Only internet-facing ones. Adding LAN devices too made both lines
  /// roughly download + upload: a download is received on the WAN and sent
  /// again on the LAN, so neither line said which way traffic went (#81).
  /// With no internet-facing interface to go by, every interface is counted,
  /// as before.
  ///
  /// A tunnel (a WireGuard full tunnel, an L2TP or 6in4 uplink) is left out
  /// when an active direct uplink is also counted: everything in the tunnel
  /// crosses that uplink as well, so adding both showed tunnelled traffic at
  /// about twice its rate. Counting the outer layer catches all of it once.
  /// A direct uplink that is down carries nothing, so it does not stand in
  /// for a tunnel that runs over some other link.
  static Set<String> combinedThroughputDevices(Map? interfaceDump) {
    final upstream = upstreamInterfaces(interfaceDump);
    if (upstream.isNotEmpty) {
      final carrierActive = upstream.any(
        (i) =>
            !_isTunnel(i) && (i['up'] == true || _hasDefaultRoute(i['route'])),
      );
      return {
        for (final i in upstream)
          if (!carrierActive || !_isTunnel(i)) ?_countedDevice(i),
      };
    }
    final interfaces = interfaceDump?['interface'];
    if (interfaces is! List) return const {};
    return {
      for (final i in interfaces)
        if (i is Map && i['interface'] != 'loopback' && i['interface'] != 'lo')
          ?_countedDevice(i),
    };
  }

  /// True when [device] faces the router's clients rather than the
  /// internet: a LAN bridge, a guest network.
  ///
  /// There, what the router *receives* is what its clients upload, so the
  /// graph swaps the two to keep "down" meaning traffic towards the user's
  /// devices. Swapping the wrong way is as bad as the bug, so it takes
  /// positive evidence: the device belongs to an interface the dump lists,
  /// and every interface on it is neither internet-facing nor named `wan…`
  /// and has no routes of its own - a secondary WAN or a VPN routing a
  /// remote subnet has some. Anything else - a device the dump does not
  /// list, or a router whose internet side cannot be told - is left alone.
  static bool isClientFacing(Map? interfaceDump, String device) {
    final upstream = upstreamInterfaces(interfaceDump);
    if (upstream.isEmpty) return false;
    final interfaces = interfaceDump?['interface'];
    if (interfaces is! List) return false;
    final owners = [
      for (final i in interfaces)
        if (i is Map &&
            (i['l3_device']?.toString() == device ||
                i['device']?.toString() == device))
          i,
    ];
    if (owners.isEmpty) return false;
    return owners.every(
      (i) =>
          !upstream.contains(i) &&
          !_isNamedWan(i) &&
          !(i['route'] is List && (i['route'] as List).isNotEmpty),
    );
  }

  List<double> get rxHistory => _rxHistory.toList();
  List<double> get txHistory => _txHistory.toList();
  double get currentRxRate => _currentRxRate;
  double get currentTxRate => _currentTxRate;

  // Interface-specific getters
  List<double> getRxHistoryForInterface(String interface) {
    return _rxHistoryPerInterface[interface]?.toList() ?? [];
  }

  List<double> getTxHistoryForInterface(String interface) {
    return _txHistoryPerInterface[interface]?.toList() ?? [];
  }

  double getCurrentRxRateForInterface(String interface) {
    return _currentRxRatePerInterface[interface] ?? 0.0;
  }

  double getCurrentTxRateForInterface(String interface) {
    return _currentTxRatePerInterface[interface] ?? 0.0;
  }

  void updateThroughput(
    Map<String, dynamic>? networkData,
    Set<String> wanDeviceNames, {
    String? specificInterface,
  }) {
    final now = DateTime.now();

    if (networkData == null) {
      clear();
      return;
    }
    final missingDevices = _lastStatsPerInterface.keys
        .where((name) => !networkData.containsKey(name))
        .toList();
    for (final name in missingDevices) {
      _clearInterface(name);
    }

    // Always update per-interface throughput for all interfaces
    networkData.forEach((devName, devData) {
      _updateInterfaceThroughput(devName, devData, now);
    });

    if (specificInterface != null && specificInterface.isNotEmpty) {
      _updateSpecificInterfaceThroughput(specificInterface);
      _lastStats = null;
      _lastTimestamp = null;
      return;
    }

    final valid =
        wanDeviceNames.isNotEmpty &&
        wanDeviceNames.every((name) => _hasCounters(networkData[name]));
    if (!valid) {
      _resetCombined();
      return;
    }
    final previous = _lastStats;
    final timestamp = _lastTimestamp;
    final sameDevices =
        _lastWanDevices.length == wanDeviceNames.length &&
        _lastWanDevices.containsAll(wanDeviceNames);
    if (previous == null ||
        timestamp == null ||
        !sameDevices ||
        wanDeviceNames.any(
          (name) => _countersReset(previous[name], networkData[name]),
        )) {
      _resetCombined();
      _lastStats = networkData;
      _lastTimestamp = now;
      _lastWanDevices = Set.of(wanDeviceNames);
      return;
    }

    final elapsed = now.difference(timestamp).inMilliseconds / 1000.0;
    if (elapsed < _minElapsedSeconds) return;

    final rx = _totalDelta(previous, networkData, wanDeviceNames, 'rx_bytes');
    final tx = _totalDelta(previous, networkData, wanDeviceNames, 'tx_bytes');
    _currentRxRate = min(rx / elapsed, _maxRate);
    _currentTxRate = min(tx / elapsed, _maxRate);
    _addToHistory(_currentRxRate, _currentTxRate);
    _lastStats = networkData;
    _lastTimestamp = now;
  }

  static num? _asNum(Object? value) {
    final number = value is num ? value : num.tryParse(value.toString());
    return number != null && number.isFinite && number >= 0 ? number : null;
  }

  static bool _hasCounters(Object? device) =>
      device is Map<String, dynamic> &&
      _asNum(_counterValue(device, 'rx_bytes')) != null &&
      _asNum(_counterValue(device, 'tx_bytes')) != null;

  static bool _countersReset(
    Map<String, dynamic> previous,
    Map<String, dynamic> next,
  ) =>
      _delta(previous, next, 'rx_bytes') < 0 ||
      _delta(previous, next, 'tx_bytes') < 0;

  static num _delta(
    Map<String, dynamic> previous,
    Map<String, dynamic> next,
    String key,
  ) =>
      _asNum(_counterValue(next, key))! - _asNum(_counterValue(previous, key))!;

  static num _totalDelta(
    Map<String, dynamic> previous,
    Map<String, dynamic> next,
    Set<String> devices,
    String key,
  ) => devices.fold<num>(
    0,
    (sum, name) => sum + _delta(previous[name], next[name], key),
  );

  /// Reads a byte counter that may live under `stats.<key>` or directly at
  /// `<key>`. Some firmware builds return a non-map `stats` value - treat
  /// that as absent and fall back to the direct field.
  static Object? _counterValue(Map<String, dynamic> device, String key) {
    final stats = device['stats'];
    if (stats is Map) {
      return stats[key] ?? device[key];
    }
    return device[key];
  }

  void _updateInterfaceThroughput(
    String interface,
    dynamic devData,
    DateTime now,
  ) {
    if (devData is! Map<String, dynamic> || !_hasCounters(devData)) {
      _clearInterface(interface);
      return;
    }
    final lastStats = _lastStatsPerInterface[interface];
    final lastTimestamp = _lastTimestampPerInterface[interface];
    if (lastStats == null ||
        lastTimestamp == null ||
        _countersReset(lastStats, devData)) {
      _clearInterface(interface);
      _lastStatsPerInterface[interface] = devData;
      _lastTimestampPerInterface[interface] = now;
      return;
    }

    final elapsed = now.difference(lastTimestamp).inMilliseconds / 1000.0;
    if (elapsed < _minElapsedSeconds) return;
    final rx = min(_delta(lastStats, devData, 'rx_bytes') / elapsed, _maxRate);
    final tx = min(_delta(lastStats, devData, 'tx_bytes') / elapsed, _maxRate);
    _currentRxRatePerInterface[interface] = rx;
    _currentTxRatePerInterface[interface] = tx;
    _addToInterfaceHistory(interface, rx, tx);
    _lastStatsPerInterface[interface] = devData;
    _lastTimestampPerInterface[interface] = now;
  }

  void _clearInterface(String interface) {
    _lastStatsPerInterface.remove(interface);
    _lastTimestampPerInterface.remove(interface);
    _rxHistoryPerInterface.remove(interface);
    _txHistoryPerInterface.remove(interface);
    _currentRxRatePerInterface.remove(interface);
    _currentTxRatePerInterface.remove(interface);
  }

  void _updateSpecificInterfaceThroughput(String interface) {
    _currentRxRate = _currentRxRatePerInterface[interface] ?? 0.0;
    _currentTxRate = _currentTxRatePerInterface[interface] ?? 0.0;
    _rxHistory.clear();
    _txHistory.clear();

    // Use the interface's history for the main display
    final rxHist = _rxHistoryPerInterface[interface];
    final txHist = _txHistoryPerInterface[interface];

    if (rxHist != null && txHist != null) {
      _rxHistory.addAll(rxHist);
      _txHistory.addAll(txHist);
    }
  }

  void _addToInterfaceHistory(String interface, double rxRate, double txRate) {
    final rxHist = _rxHistoryPerInterface.putIfAbsent(
      interface,
      () => Queue<double>(),
    );
    final txHist = _txHistoryPerInterface.putIfAbsent(
      interface,
      () => Queue<double>(),
    );

    rxHist.add(rxRate);
    txHist.add(txRate);

    // Maintain fixed queue size
    if (rxHist.length > _maxHistoryLength) {
      rxHist.removeFirst();
    }
    if (txHist.length > _maxHistoryLength) {
      txHist.removeFirst();
    }
  }

  void _addToHistory(double rxRate, double txRate) {
    _rxHistory.add(rxRate);
    _txHistory.add(txRate);

    // Maintain fixed queue size for O(1) performance
    if (_rxHistory.length > _maxHistoryLength) {
      _rxHistory.removeFirst();
    }
    if (_txHistory.length > _maxHistoryLength) {
      _txHistory.removeFirst();
    }
  }

  void _resetCombined() {
    _rxHistory.clear();
    _txHistory.clear();
    _currentRxRate = 0;
    _currentTxRate = 0;
    _lastStats = null;
    _lastTimestamp = null;
    _lastWanDevices = const {};
  }

  void clear() {
    _resetCombined();
    // Clear per-interface data
    _rxHistoryPerInterface.clear();
    _txHistoryPerInterface.clear();
    _currentRxRatePerInterface.clear();
    _currentTxRatePerInterface.clear();
    _lastStatsPerInterface.clear();
    _lastTimestampPerInterface.clear();
  }
}
