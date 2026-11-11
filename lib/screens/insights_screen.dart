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

/// Read-only visibility into what the router is doing: logs, diagnostics and
/// activity.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isFrench = Localizations.localeOf(context).languageCode == 'fr';
    return Scaffold(
      appBar: LuciAppBar(title: l10n.insights),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: Semantics(
              label: isFrench
                  ? 'Surveillance locale, informations de sécurité'
                  : 'Local monitoring, security information',
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shield_outlined,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isFrench ? 'Surveillance domotique' : 'Home network monitoring',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isFrench
                            ? 'Consulte les événements, journaux et mesures disponibles sur ton routeur.'
                            : 'Review the events, logs and measurements available from your router.',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isFrench
                            ? 'Ces informations ne constituent pas un détecteur d’intrusion. Aucun équipement n’est bloqué depuis cet écran.'
                            : 'This is not an intrusion detector. No devices are blocked from this screen.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          LuciSectionHeader(l10n.insights),
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
    );
  }
}
