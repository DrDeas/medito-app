import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/medito_text.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/donation/donation_snooze_provider.dart';
import 'package:medito/views/home/widgets/bottom_sheet/row_item_widget.dart';
import 'package:medito/views/settings/widgets/announce_setting.dart';
import 'package:medito/widgets/radio_option_card.dart';

/// Settings row that turns requests to donate on or off for good. A timed
/// "Hide for now" already existed on the ask itself; this is the standing
/// choice for people who have given elsewhere or simply do not want to be
/// asked.
class DonationAsksTile extends ConsumerWidget {
  const DonationAsksTile({
    super.key,
    required this.icon,
    this.hasUnderline = true,
  });

  final Widget icon;
  final bool hasUnderline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final muted = ref.watch(donationSnoozeProvider.select((s) => s.isMuted));

    return RowItemWidget(
      icon: icon,
      title: l10n.donationAsksTitle,
      subTitle: muted ? l10n.donationAsksOff : l10n.donationAsksOn,
      hasUnderline: hasUnderline,
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
        builder: (_) => const DonationAsksSheet(),
      ),
    );
  }
}

/// Explains what the setting covers and offers the two choices. Tapping one
/// applies it and closes the sheet.
class DonationAsksSheet extends ConsumerWidget {
  const DonationAsksSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final muted = ref.watch(donationSnoozeProvider.select((s) => s.isMuted));
    final onSurface = Theme.of(context).colorScheme.onSurface;

    Future<void> choose(bool mute) async {
      await ref.read(donationSnoozeProvider.notifier).setMuted(mute);
      if (!context.mounted) return;
      announceSettingChoice(
        context,
        l10n.donationAsksTitle,
        mute ? l10n.donationAsksOff : l10n.donationAsksOn,
      );
      Navigator.of(context).pop();
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.donationAsksTitle,
                style: context.text.label.copyWith(color: onSurface),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.donationAsksSheetBody,
              style: context.text.muted.bodySmall,
            ),
            const SizedBox(height: 16),
            RadioOptionCard(
              title: l10n.donationAsksOn,
              description: l10n.donationAsksOnDescription,
              selected: !muted,
              onTap: () => choose(false),
            ),
            const SizedBox(height: 12),
            RadioOptionCard(
              title: l10n.donationAsksOff,
              description: l10n.donationAsksOffDescription,
              selected: muted,
              onTap: () => choose(true),
            ),
          ],
        ),
      ),
    );
  }
}
