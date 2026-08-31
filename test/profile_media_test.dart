import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/profile/profile_media.dart';

void main() {
  test('profile media accepts exactly 500 KB', () {
    expect(
      () => ProfileMediaStorage.validateSelection(
        name: 'avatar.gif',
        sizeBytes: kProfileMediaMaxBytes,
      ),
      returnsNormally,
    );
  });

  test('profile media rejects files larger than 500 KB', () {
    expect(
      () => ProfileMediaStorage.validateSelection(
        name: 'avatar.mp4',
        sizeBytes: kProfileMediaMaxBytes + 1,
      ),
      throwsA(
        isA<ProfileMediaException>().having(
          (error) => error.message,
          'message',
          kProfileMediaSizeMessage,
        ),
      ),
    );
  });

  test('profile media recognizes photos, animated GIFs, and videos', () {
    expect(ProfileMediaStorage.kindForFileName('avatar.PNG'), ProfileMediaKind.photo);
    expect(ProfileMediaStorage.kindForFileName('avatar.gif'), ProfileMediaKind.gif);
    expect(ProfileMediaStorage.kindForFileName('avatar.webm'), ProfileMediaKind.video);
    expect(ProfileMediaStorage.kindForFileName('avatar.pdf'), isNull);
  });
}
