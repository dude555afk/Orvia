import 'package:Kelivo/core/services/backup/backup_activity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(BackupActivity.debugReset);
  tearDown(BackupActivity.debugReset);

  group('BackupActivity', () {
    test('\u95F2\u7F6E\u65F6\u4E0D\u963B\u585E\u540E\u53F0\u5DE5\u4F5C', () {
      expect(BackupActivity.isActive, isFalse);
    });

    test('begin/end \u6210\u5BF9\u540E\u56DE\u5230\u95F2\u7F6E', () {
      BackupActivity.begin();
      expect(BackupActivity.isActive, isTrue);
      BackupActivity.end();
      expect(BackupActivity.isActive, isFalse);
    });

    test('\u5D4C\u5957\u4EFB\u52A1\u5168\u90E8\u7ED3\u675F\u524D\u4E00\u76F4\u7B97\u5FD9', () {
      BackupActivity.begin();
      BackupActivity.begin();
      BackupActivity.end();
      // \u8F6C\u5230\u540E\u53F0\u7684\u4EFB\u52A1\u6BD4\u542F\u52A8\u5B83\u7684\u5F39\u7A97\u6D3B\u5F97\u4E45，\u6240\u4EE5\u53EA\u6570\u5230\u96F6\u624D\u7B97\u95F2。
      expect(BackupActivity.isActive, isTrue);
      BackupActivity.end();
      expect(BackupActivity.isActive, isFalse);
    });

    test('\u591A\u4F59\u7684 end \u4E0D\u4F1A\u628A\u8BA1\u6570\u538B\u5230\u8D1F\u6570', () {
      BackupActivity.end();
      BackupActivity.end();
      expect(BackupActivity.isActive, isFalse);
      BackupActivity.begin();
      expect(BackupActivity.isActive, isTrue);
    });
  });
}
