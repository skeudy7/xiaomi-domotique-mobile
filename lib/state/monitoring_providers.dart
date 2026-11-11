import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/services/firewall_planner.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/utils/uci_values.dart';

/// The inventory available for the selected router, with tri-state presence.
final selectedInventoryProvider = FutureProvider.autoDispose<List<Client>?>((
  ref,
) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  return ref.read(appStateProvider).fetchClientsForSelectedRouter();
}, retry: (_, _) => null);

typedef WanFirewallSummary = ({
  Map<String, String?> inputPolicies,
  int enabledForwards,
});

final wanFirewallProvider = FutureProvider.autoDispose<WanFirewallSummary?>((
  ref,
) async {
  final session = ref.watch(sessionProvider);
  final api = ref.watch(apiServiceProvider);
  if (session == null || api == null || session.reviewerMode) return null;
  final response = await api.uciGetAll(
    session.ipAddress,
    session.sysauth,
    session.useHttps,
    config: 'firewall',
  );
  if (response is! List || response.length < 2 || response[0] != 0) {
    return null;
  }
  return summarizeWanFirewall(uciValuesOf(response, config: 'firewall'));
}, retry: (_, _) => null);

WanFirewallSummary? summarizeWanFirewall(Map<String, dynamic> values) {
  const wanNames = {'wan', 'wan6'};
  final policies = <String, String?>{};
  for (final zone in uciSections(values, 'zone')) {
    final name = uciText(zone.value['name']);
    if (name == null) continue;
    if (wanNames.contains(name) ||
        uciList(zone.value['network']).any(wanNames.contains)) {
      policies[name] = uciText(zone.value['input']);
    }
  }
  if (policies.isEmpty) return null;
  return (
    inputPolicies: policies,
    enabledForwards: FirewallPlanner.portForwards(values)
        .where((rule) => rule.enabled && policies.containsKey(rule.sourceZone))
        .length,
  );
}
