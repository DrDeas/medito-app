import 'package:flutter_test/flutter_test.dart';
import 'package:medito/views/search/search_view.dart';

void main() {
  test('accented letters keep their base letter', () {
    expect(asciiSearchQuery('meditación'), 'meditacion');
    expect(asciiSearchQuery('respiração'), 'respiracao');
    expect(asciiSearchQuery('Überblick über Stille'), 'Uberblick uber Stille');
    expect(asciiSearchQuery('sueño'), 'sueno');
    expect(asciiSearchQuery('Straße'), 'Strasse');
  });

  test('plain queries pass through, trimmed', () {
    expect(asciiSearchQuery('  sleep  '), 'sleep');
    expect(asciiSearchQuery('body scan 10'), 'body scan 10');
  });

  test('text with no ASCII equivalent leaves an empty query', () {
    expect(asciiSearchQuery('瞑想'), '');
    expect(asciiSearchQuery('😀 calm'), 'calm');
  });
}
