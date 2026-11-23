import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/design/window_size.dart';

void main() {
  group('WindowSize.ofWidth', () {
    final cases = <double, WindowSize>{
      0: WindowSize.compact,
      599.9: WindowSize.compact,
      600: WindowSize.medium,
      839.9: WindowSize.medium,
      840: WindowSize.expanded,
      1920: WindowSize.expanded,
    };
    for (final MapEntry(key: width, value: expected) in cases.entries) {
      test('$width is $expected', () {
        expect(WindowSize.ofWidth(width), expected);
      });
    }
  });

  test('only expanded has the top bar', () {
    expect(WindowSize.compact.hasTopBar, isFalse);
    expect(WindowSize.medium.hasTopBar, isFalse);
    expect(WindowSize.expanded.hasTopBar, isTrue);
  });
}
