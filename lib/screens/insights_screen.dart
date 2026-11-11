import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/screens/diagnostics_screen.dart';
import 'package:luci_mobile/screens/traffic_screen.dart';
import 'package:luci_mobile/screens/event_feed_screen.dart';
import 'package:luci_mobile/screens/log_screen.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';
import 'package:luci_mobile/widgets/luci_hub_tile.dart';
import 'package:luci_mobile/navigation/tab_bar_inset.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/monitoring_providers.dart';

/// Read-only visibility into what the router is doing: logs, diagnostics and
/// activity.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(sessionProvider);
    final firewall = ref.watch(wanFirewallProvider);
    final report = firewall.isLoading || firewall.hasError
        ? null
        : firewall.value;
    final unknown = firewall.isLoading ? l10n.connecting : l10n.noDataAvailable;
    return Scaffold(
      appBar: LuciAppBar(title: l10n.insights),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            ref.invalidate(wanFirewallProvider);
            await ref.read(wanFirewallProvider.future);
          } catch (_) {
            // The provider's error state is presented as unavailable.
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: TabBarInset.of(context)),
          children: [
            LuciSectionHeader(l10n.firewall),
            LuciHubSection(
              tiles: [
                LuciHubTile(
                  icon: Icons.shield_outlined,
                  title: l10n.wanInputPolicy,
                  subtitle:
                      report?.inputPolicies.entries
                          .map(
                            (entry) => [
                              entry.key,
                              entry.value ?? l10n.unknown,
                            ].join(' · '),
                          )
                          .join('\n') ??
                      unknown,
                ),
                LuciHubTile(
                  icon: Icons.lan_outlined,
                  title: l10n.configuredWanForwards,
                  subtitle: report?.enabledForwards.toString() ?? unknown,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: LuciSpacing.md),
              child: Text(
                l10n.firewallConfigSnapshot,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            LuciHubSection(
              tiles: [
                LuciHubTile(
                  icon: Icons.router_outlined,
                  title: l10n.managementConnection,
                  subtitle: session == null || session.reviewerMode
                      ? l10n.noDataAvailable
                      : (session.useHttps ? 'HTTPS' : 'HTTP'),
                  iconColor: session?.useHttps == false
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ],
            ),
            LuciHubSection(
              tiles: [
                LuciHubTile(
                  icon: Icons.history,
                  title: l10n.activity,
                  subtitle: l10n.activityHubSubtitle,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const EventFeedScreen(),
                    ),
                  ),
                ),
                LuciHubTile(
                  icon: Icons.article_outlined,
                  title: l10n.systemLog,
                  subtitle: l10n.logHubSubtitle,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const LogScreen()),
                  ),
                ),
                LuciHubTile(
                  icon: Icons.data_usage,
                  title: l10n.trafficHistory,
                  subtitle: l10n.trafficHistorySubtitle,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TrafficScreen(),
                    ),
                  ),
                ),
                LuciHubTile(
                  icon: Icons.network_ping,
                  title: l10n.diagnostics,
                  subtitle: l10n.diagnosticsHubSubtitle,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DiagnosticsScreen(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuciSpacing.lg),
          ],
        ),
      ),
    );
  }
}
