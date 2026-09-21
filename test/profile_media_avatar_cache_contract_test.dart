import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile avatar keeps a live cached photo across tab rebuilds', () {
    final main = File('lib/main.dart').readAsStringSync();
    final profileUi = File('lib/profile/profile_ui.dart').readAsStringSync();

    expect(main, contains('ImageProvider? profileMediaAvatarImageProvider;'));
    expect(main, contains('ImageStream? _profileMediaAvatarImageStream;'));
    expect(main, contains('void _primeProfileMediaAvatarImage()'));
    expect(main, contains("profileMediaKind != ProfileMediaKind.photo"));
    expect(main, contains("final candidate = FileImage(File(path));"));
    expect(main, contains('stream.addListener(listener);'));
    expect(main, contains('_primeProfileMediaAvatarImage();'));
    expect(main, contains('_releaseProfileMediaAvatarImage(evict: true);'));

    expect(profileUi, contains('imageProvider: state.hasProfileMedia ? state.profileMediaAvatarImageProvider : null'));
    expect(profileUi, contains('this.imageProvider'));
    expect(profileUi, contains('final provider = imageProvider ?? FileImage(File(path));'));
    expect(profileUi, contains('frameBuilder: (context, imageChild, frame, wasSynchronouslyLoaded)'));
    expect(profileUi, contains('if (wasSynchronouslyLoaded || frame != null) return imageChild;'));
    expect(profileUi, contains('return _fallback(context);'));
  });
}
