import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('onboarding branding blends with the page and accent icons animate', () {
    final branding = File('lib/branding_widgets.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(branding, contains("assets/icons/koinly_mark.png"));
    expect(branding, isNot(contains("assets/icons/app_icon.png")));
    expect(main, contains('_AnimatedOnboardingGlyph(icon: icon)'));
    expect(main, contains('class _AnimatedOnboardingGlyph'));
    expect(main, contains('MediaQuery.of(context).disableAnimations'));
  });
}
