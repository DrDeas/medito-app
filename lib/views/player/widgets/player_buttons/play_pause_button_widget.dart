import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:medito/constants/icons/medito_icons.dart';
import 'package:medito/widgets/medito_icon.dart';

class PlayPauseButtonWidget extends ConsumerWidget {
  const PlayPauseButtonWidget({
    super.key,
    this.iconSize = 72,
    required this.isPlaying,
    required this.onPlayPause,
    this.isLoading = false,
    this.isRebuffering = false,
  });

  final double iconSize;
  final bool isPlaying;
  final Function() onPlayPause;

  /// While the audio is still spinning up, show a spinner in place of the
  /// icon (same box size, so nothing shifts) and ignore taps.
  final bool isLoading;

  /// The spinner is for a stall after playback had started. The button then
  /// still pauses and resumes, so a dropped connection never traps the user
  /// on a control that ignores them.
  final bool isRebuffering;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    if (isLoading) {
      final spinner = _spinner();
      if (!isRebuffering) {
        return Semantics(label: l10n.loading, child: spinner);
      }
      return Semantics(
        label: isPlaying ? l10n.pause : l10n.play,
        value: l10n.loading,
        button: true,
        child: InkWell(
          onTap: onPlayPause,
          borderRadius: BorderRadius.circular(iconSize / 2),
          child: ExcludeSemantics(child: spinner),
        ),
      );
    }
    return _button(l10n);
  }

  Widget _spinner() {
    return SizedBox(
      width: iconSize,
      height: iconSize,
      child: Center(
        child: SizedBox(
          width: iconSize * 0.5,
          height: iconSize * 0.5,
          child: const CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(ColorConstants.white),
          ),
        ),
      ),
    );
  }

  Widget _button(AppLocalizations l10n) {
    return Semantics(
      label: isPlaying ? l10n.pause : l10n.play,
      button: true,
      child: InkWell(
        onTap: onPlayPause,
        borderRadius: BorderRadius.circular(iconSize / 2),
        child: ExcludeSemantics(
          child: AnimatedCrossFade(
            firstChild: MeditoIcon(
              assetName: MeditoIcons.playSolid,
              size: iconSize,
              color: ColorConstants.white,
            ),
            secondChild: MeditoIcon(
              assetName: MeditoIcons.pause,
              size: iconSize,
              color: ColorConstants.white,
            ),
            crossFadeState: isPlaying
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 100),
          ),
        ),
      ),
    );
  }
}
