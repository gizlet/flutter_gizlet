import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_gizlet/src/package.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

const toml = '''
id = "io.gizlet.test"
name = "Test"
version = "0.1.0"
icon = "art.png"
[names]
zh-CN = "测试"
[[packages]]
target = "aarch64-unknown-linux-gnu"
tier = "lite"
entry = "flutter-pi"
''';

void main() {
  test(
    'makes a Store package with an executable entry and valid checksums',
    () {
      final project = Directory.systemTemp.createTempSync('gzl-test-');
      addTearDown(() => project.deleteSync(recursive: true));
      final bundle = Directory(path.join(project.path, 'bundle'))..createSync();
      final elf = <int>[
        127,
        69,
        76,
        70,
        2,
        1,
        ...List.filled(10, 0),
        3,
        0,
        183,
        0,
      ];
      for (final name in ['app.so', 'libflutter_engine.so', 'icudtl.dat']) {
        File(path.join(bundle.path, name)).writeAsBytesSync(elf);
      }
      File(path.join(project.path, 'art.png')).writeAsStringSync('icon');
      final result = writeGzl(
        project: project,
        bundle: bundle,
        runtime: Archive()..addFile(ArchiveFile.bytes(entry, elf)),
        spec: AppSpec.parse(toml),
        output: Directory(path.join(project.path, 'out')),
      );
      expect(
        path.basename(result.path),
        'io.gizlet.test-0.1.0-$target-lite.gzl',
      );
      final archive = ZipDecoder().decodeBytes(
        result.readAsBytesSync(),
        verify: true,
      );
      final checksums = archive.findFile('CHECKSUMS')!;
      final manifest = jsonDecode(
        utf8.decode(archive.findFile('manifest.json')!.content),
      );
      expect(manifest['names']['zh-CN'], '测试');
      expect(archive.findFile(entry)!.mode & 0x49, isNonZero);
      expect(
        utf8.decode(checksums.content).trim().split('\n'),
        unorderedEquals(
          archive.files
              .where((file) => file != checksums)
              .map((file) => '${sha256.convert(file.content)}  ${file.name}'),
        ),
      );
    },
  );

  test('rejects paths that cannot be stored in a Gizlet package', () {
    for (final invalid in ['../secret.png', 'a//b', 'a\\b', '/x', 'a\nx']) {
      expect(canonicalPath(invalid), isFalse);
    }
    expect(
      () => AppSpec.parse(toml.replaceFirst('art.png', '../secret.png')),
      throwsFormatException,
    );
  });
}
