import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_squoosher/services/window_settings_save_queue.dart';

void main() {
  test('連続したサイズ変更を1回の保存へまとめる', () async {
    var saveCount = 0;
    final queue = WindowSettingsSaveQueue(
      save: () async {
        saveCount += 1;
      },
      debounceDuration: const Duration(milliseconds: 10),
    );
    addTearDown(queue.dispose);

    queue.schedule();
    queue.schedule();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(saveCount, 1);
  });

  test('サイズ保存を前の書き込みの完了後へ直列化する', () async {
    final firstSaveStarted = Completer<void>();
    final releaseFirstSave = Completer<void>();
    var activeSaveCount = 0;
    var maximumActiveSaveCount = 0;
    var saveCount = 0;

    final queue = WindowSettingsSaveQueue(
      save: () async {
        activeSaveCount += 1;
        maximumActiveSaveCount = maximumActiveSaveCount < activeSaveCount ? activeSaveCount : maximumActiveSaveCount;
        saveCount += 1;
        if (saveCount == 1) {
          firstSaveStarted.complete();
          await releaseFirstSave.future;
        }
        activeSaveCount -= 1;
      },
    );
    addTearDown(queue.dispose);

    final firstFlush = queue.flush();
    await firstSaveStarted.future;
    final secondFlush = queue.flush();
    releaseFirstSave.complete();
    await Future.wait([firstFlush, secondFlush]);

    expect(saveCount, 2);
    expect(maximumActiveSaveCount, 1);
  });
}
