import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:toml/toml.dart';

const target = 'aarch64-unknown-linux-gnu';
const entry = 'flutter-pi';

class AppSpec {
  AppSpec(this.manifest, this.icon);

  final Map<String, Object> manifest;
  final String? icon;

  String get filename =>
      '${manifest['id']}-${manifest['version']}-$target-${manifest['tier']}.gzl';

  factory AppSpec.parse(String source) {
    final spec = TomlDocument.parse(source).toMap();
    final id = spec['id'];
    final name = spec['name'];
    final version = spec['version'];
    final packages = spec['packages'];
    if (id is! String ||
        !RegExp(r'^[a-z0-9]+(?:[.][a-z0-9][a-z0-9-]*){2,}$').hasMatch(id)) {
      throw const FormatException('gizlet.toml requires a reverse-DNS id.');
    }
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('gizlet.toml requires a name.');
    }
    if (version is! String ||
        !RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$').hasMatch(version)) {
      throw const FormatException('gizlet.toml requires a semantic version.');
    }
    if ((spec['kind'] ?? 'app') != 'app' || (spec['runtime'] ?? 1) != 1) {
      throw const FormatException('Builds require kind="app" and runtime=1.');
    }
    if (packages is! List) {
      throw const FormatException('gizlet.toml requires [[packages]].');
    }
    final matches = packages.whereType<Map>().where(
      (package) => package['target'] == target,
    );
    if (matches.length != 1 ||
        matches.single['entry'] != entry ||
        !{'lite', 'full'}.contains(matches.single['tier'])) {
      throw const FormatException(
        'Declare one ARM64 package with entry="flutter-pi" and tier="lite" or "full".',
      );
    }
    final manifest = <String, Object>{
      'schema': 1,
      'id': id,
      'name': name,
      'version': version,
      'runtime': 1,
      'target': target,
      'tier': matches.single['tier'] as String,
      'entry': entry,
    };
    for (final field in ['description', 'color']) {
      final value = spec[field];
      if (value == null) continue;
      if (value is! String) {
        throw FormatException('$field must be a string.');
      }
      manifest[field] = value;
    }
    for (final field in ['names', 'descriptions']) {
      final value = spec[field];
      if (value == null) continue;
      if (value is! Map || !value.values.every((item) => item is String)) {
        throw FormatException('$field must be a table of strings.');
      }
      manifest[field] = Map<String, String>.from(value);
    }
    final icon = spec['icon'];
    if (icon != null && (icon is! String || !canonicalPath(icon))) {
      throw const FormatException('icon must be a relative repository path.');
    }
    if (icon is String) manifest['icon'] = 'icon${path.extension(icon)}';
    return AppSpec(manifest, icon as String?);
  }
}

bool canonicalPath(String name) =>
    !RegExp(r'[\\:\x00-\x1f\x7f]').hasMatch(name) &&
    name
        .split('/')
        .every((part) => part.isNotEmpty && part != '.' && part != '..');

void checkArm64Elf(List<int> bytes, String name) {
  if (bytes.length < 20 ||
      bytes[0] != 0x7f ||
      String.fromCharCodes(bytes.skip(1).take(3)) != 'ELF' ||
      bytes[4] != 2 ||
      bytes[5] != 1 ||
      ![2, 3].contains(bytes[16]) ||
      bytes[17] != 0 ||
      bytes[18] != 183 ||
      bytes[19] != 0) {
    throw FormatException('$name must be an ARM64 ELF binary.');
  }
}

File writeGzl({
  required Directory project,
  required Directory bundle,
  required Archive runtime,
  required AppSpec spec,
  required Directory output,
}) {
  final files = <String, List<int>>{};
  void add(String name, List<int> bytes) {
    if (!canonicalPath(name) ||
        name == 'CHECKSUMS' ||
        files.containsKey(name)) {
      throw FormatException('Invalid or duplicate package path: $name');
    }
    files[name] = bytes;
  }

  for (final file in runtime.files) {
    if (file.isDirectory) continue;
    if (!file.isFile ||
        file.isSymbolicLink ||
        !(file.name == entry ||
            file.name.startsWith('runtime-libs/') ||
            file.name.startsWith('runtime-notices/'))) {
      throw FormatException('Unexpected file in runtime: ${file.name}');
    }
    add(file.name, file.content);
  }
  for (final file in bundle.listSync(recursive: true, followLinks: false)) {
    if (file is Directory) continue;
    if (file is! File) throw FormatException('Unsupported bundle file: $file');
    final name = path
        .split(path.relative(file.path, from: bundle.path))
        .join('/');
    if (name != entry) add(name, file.readAsBytesSync());
  }
  for (final binary in [entry, 'app.so', 'libflutter_engine.so']) {
    checkArm64Elf(files[binary] ?? const [], binary);
  }
  if (files['icudtl.dat']?.isNotEmpty != true) {
    throw const FormatException('Flutter bundle is missing icudtl.dat.');
  }
  if (spec.icon case final icon?) {
    add(
      spec.manifest['icon'] as String,
      File(path.join(project.path, icon)).readAsBytesSync(),
    );
  }
  add('manifest.json', utf8.encode('${jsonEncode(spec.manifest)}\n'));
  final names = files.keys.toList()..sort();
  final checksums = StringBuffer();
  final archive = Archive();
  for (final name in names) {
    final bytes = files[name]!;
    checksums.writeln('${sha256.convert(bytes)}  $name');
    archive.addFile(
      ArchiveFile.bytes(name, bytes)
        ..lastModTime = 315532800
        ..mode = name == entry ? 0x81ed : 0x81a4,
    );
  }
  archive.addFile(
    ArchiveFile.bytes('CHECKSUMS', utf8.encode(checksums.toString()))
      ..lastModTime = 315532800
      ..mode = 0x81a4,
  );
  if (archive.length >= 65535 ||
      archive.files.fold<int>(
            0,
            (sum, file) => sum + file.size + 256 + file.name.length * 4,
          ) >=
          0xffffffff) {
    throw const FormatException('Package exceeds the non-ZIP64 limits.');
  }
  output.createSync(recursive: true);
  final result = File(path.join(output.path, spec.filename));
  final staging = output.createTempSync('.flutter-gizlet-');
  try {
    final temporary = File(path.join(staging.path, spec.filename));
    temporary.writeAsBytesSync(_encodeUnixZip(archive));
    return temporary.renameSync(result.path);
  } finally {
    staging.deleteSync(recursive: true);
  }
}

Uint8List _encodeUnixZip(Archive archive) {
  final bytes = ZipEncoder().encodeBytes(archive);
  final central = ByteData.sublistView(bytes);
  final end = bytes.length - 22;
  if (central.getUint32(end, Endian.little) != 0x06054b50) {
    throw const FormatException('Unexpected ZIP end record.');
  }
  var offset = central.getUint32(end + 16, Endian.little);
  for (final file in archive.files) {
    if (offset + 46 > end ||
        central.getUint32(offset, Endian.little) != 0x02014b50) {
      throw FormatException('Unexpected ZIP directory entry for ${file.name}.');
    }
    central.setUint8(offset + 5, 3);
    offset +=
        46 +
        central.getUint16(offset + 28, Endian.little) +
        central.getUint16(offset + 30, Endian.little) +
        central.getUint16(offset + 32, Endian.little);
  }
  if (offset != end)
    throw const FormatException('Unexpected ZIP directory end.');
  return bytes;
}
