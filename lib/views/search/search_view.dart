import 'package:medito/widgets/adaptive/adaptive_page_body.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/constants/icons/medito_icons.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/utils/utils.dart';
import 'package:medito/views/search/search_query_logger.dart';
import 'package:medito/views/search/search_results.dart';
import 'package:medito/widgets/medito_icon.dart';
import 'package:medito/widgets/widgets.dart';

/// The Search tab. A search field pinned to the top, results below, with the
/// bottom nav bar staying visible — you leave search by switching tabs, like
/// any other tab, rather than dismissing an overlay.
class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key});

  @override
  ConsumerState<SearchView> createState() => SearchViewState();
}

class SearchViewState extends ConsumerState<SearchView> {
  static const _searchDebounce = Duration(milliseconds: 500);

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  String _query = '';
  late final SearchQueryLogger _queryLogger;

  @override
  void initState() {
    super.initState();
    // Captured here, not read per event: the logger flushes from dispose(),
    // where ref can no longer be used.
    final analytics = ref.read(analyticsServiceProvider);
    _queryLogger = SearchQueryLogger(
      log: (name, parameters) =>
          unawaited(analytics.logEvent(name: name, parameters: parameters)),
    );
  }

  /// Called by the nav host when the Search tab is selected, so tapping Search
  /// drops the cursor straight into the field ready to type. Re-tapping the
  /// already-active tab re-opens the keyboard too: [FocusNode.requestFocus] is
  /// a no-op when the field already holds focus (e.g. the keyboard was
  /// dismissed by scrolling), so in that case we ask the platform to show it.
  void focusInput() {
    if (!mounted) return;
    if (_focusNode.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryLogger.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () {
      if (!mounted) return;
      final asciiQuery = asciiSearchQuery(value);
      setState(() => _query = asciiQuery);
      _queryLogger.onQuery(asciiQuery);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _queryLogger.commit();
    _controller.clear();
    setState(() => _query = '');
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return AdaptivePageBody(
      maxWidth: 960,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                padding16,
                32,
                padding16,
                padding8,
              ),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) {
                  return MeditoTextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    hintText: l10n.searchMeditations,
                    textInputAction: TextInputAction.search,
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 14, right: 10),
                      child: MeditoIcon(
                        assetName: MeditoIcons.search,
                        color: onSurface.withOpacityValue(0.6),
                        size: 18,
                      ),
                    ),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l10n.clearSearch,
                            iconSize: 20,
                            onPressed: _clear,
                            icon: Icon(
                              Icons.cancel,
                              color: onSurface.withOpacityValue(0.6),
                            ),
                          ),
                    onChanged: _onChanged,
                    onSubmitted: (_) => _queryLogger.commit(),
                  );
                },
              ),
            ),
            Expanded(
              child: SearchResults(
                query: _query,
                onBeforeNavigate: () {
                  _focusNode.unfocus();
                  _queryLogger.commit();
                },
                onResults: (query, hasResults) =>
                    _queryLogger.onResults(query, hasResults: hasResults),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _accentFolds = {
  'a': 'àáâãäåāăą',
  'c': 'çćčĉċ',
  'd': 'ďđ',
  'e': 'èéêëēĕėęě',
  'g': 'ĝğġģ',
  'h': 'ĥħ',
  'i': 'ìíîïĩīĭįı',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľŀł',
  'n': 'ñńņňŉ',
  'o': 'òóôõöøōŏő',
  'r': 'ŕŗř',
  's': 'śŝşšș',
  't': 'ţťŧț',
  'u': 'ùúûüũūŭůűų',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
  'ae': 'æ',
  'oe': 'œ',
  'ss': 'ß',
};

final _accentToAscii = {
  for (final entry in _accentFolds.entries)
    for (final rune in entry.value.runes) String.fromCharCode(rune): entry.key,
};

/// What is sent to the search backend, which is ASCII-only. Accented letters
/// are folded to their base letter ("meditación" searches "meditacion");
/// dropping them instead searched for "meditacin" and found nothing. Anything
/// still outside ASCII is removed and the ends are trimmed.
String asciiSearchQuery(String input) {
  final folded = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    if (rune < 0x80) {
      folded.write(char);
      continue;
    }
    final lower = char.toLowerCase();
    final base = _accentToAscii[lower];
    if (base == null) continue;
    folded.write(char == lower ? base : base.toUpperCase());
  }
  return folded.toString().trim();
}
