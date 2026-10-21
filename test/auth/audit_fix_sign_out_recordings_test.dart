import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/features/auth/application/user_data_wipe.dart';
import 'package:movera_rider/features/safety/application/safety_recorder_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// rider-u69 / rider-u71: the sign-out wipe removed the Safety recordings
/// index but left the rider's cabin audio in
/// `<documents>/safety_recordings` for whoever signs in next.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documents;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{
      'movera_safety_cache_v1':
          '{"recordings":[{"id":"rec-a","localPath":"x/rec-a.m4a"}]}',
    });
    documents = await Directory.systemTemp.createTemp('movera_docs_');
    NativeSafetyRecorder.documentsDirectory = () async => documents;
    NativeSafetyRecorder.savesFilesHere = true;
  });

  tearDown(() async {
    NativeSafetyRecorder.documentsDirectory = () async => documents;
    if (await documents.exists()) await documents.delete(recursive: true);
  });

  test('the wipe deletes the previous rider\'s recordings', () async {
    final recordings = await NativeSafetyRecorder.recordingsDirectory();
    await recordings.create(recursive: true);
    final audio = File('${recordings.path}/rec-a.m4a');
    await audio.writeAsBytes(const [1, 2, 3]);
    final other = File('${documents.path}/unrelated.txt');
    await other.writeAsBytes(const [4]);

    await UserDataWipe.run();

    expect(await audio.exists(), isFalse);
    expect(await recordings.exists(), isFalse);
    // Only the recordings go; nothing else in the documents folder.
    expect(await other.exists(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('movera_safety_cache_v1'), isNull);
  });

  test(
    'a wipe with no recordings, or no documents folder, still completes',
    () async {
      await UserDataWipe.run();
      NativeSafetyRecorder.documentsDirectory = () async =>
          throw const FileSystemException('no documents folder');
      await UserDataWipe.run();
    },
  );
}
