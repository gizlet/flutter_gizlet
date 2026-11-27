import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

import 'package.dart';

const compilerVersion = '0.13.0';
const flutterVersion = '3.47.0';

Future<File> buildGizlet(
  Directory project, {
  required String output,
  String? runtime,
}) async {
  final spec = AppSpec.parse(
    File(path.join(project.path, 'gizlet.toml')).readAsStringSync(),
  );
  final dart = File(Platform.resolvedExecutable).resolveSymbolicLinksSync();
  final flutterRoot = path.normalize(
    path.join(path.dirname(dart), '..', '..', '..', '..'),
  );
  final flutter = path.join(
    flutterRoot,
    'bin',
    Platform.isWindows ? 'flutter.bat' : 'flutter',
  );
  if (!File(flutter).existsSync()) {
    throw StateError('Use the Flutter SDK to run flutter_gizlet.');
  }
  final revision = jsonDecode(
    File(path.join(flutterRoot, 'bin', 'cache', 'flutter.version.json'))
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  if (revision['frameworkVersion'] != flutterVersion) {
    throw StateError(
      'This release builds with Flutter $flutterVersion. '
      'Found ${revision['frameworkVersion']}.',
    );
  }
  final root = Directory.systemTemp.createTempSync('flutter-gizlet-');
  try {
    final runtimeZip = runtime == null
        ? await downloadRuntime()
        : File(runtime).readAsBytesSync();
    final runtimeArchive = ZipDecoder().decodeBytes(runtimeZip, verify: true);
    final runner = runtimeArchive.findFile(entry);
    if (runner == null || runner.isSymbolicLink || !runner.isFile) {
      throw const FormatException('The runtime ZIP is missing flutter-pi.');
    }
    checkArm64Elf(runner.content, entry);
    final executable = File(path.join(root.path, entry))
      ..writeAsBytesSync(runner.content);

    final helper = Directory(path.join(root.path, 'compiler'))..createSync();
    File(path.join(helper.path, 'pubspec.yaml')).writeAsStringSync('''
name: gizlet_flutter_compiler
environment:
  sdk: ^3.13.0
dependencies:
  flutterpi_tool: $compilerVersion
''');
    await run(flutter, ['pub', 'get'], helper);
    final compilerMain = File(path.join(helper.path, 'compiler.dart'))
      ..writeAsStringSync('''
import 'package:flutterpi_tool/flutterpi_tool.dart' as compiler;

Future<void> main(List<String> args) => compiler.main(args);
''');
    await run(flutter, ['pub', 'get'], project);
    await run(
      dart,
      [
        compilerMain.path,
        'build',
        '--arch=arm64',
        '--cpu=generic',
        '--release',
        '--flutterpi-binary=${executable.path}',
      ],
      project,
      environment: {'FLUTTER_ROOT': flutterRoot},
    );
    final bundle = Directory(
      path.join(project.path, 'build', 'flutter-pi', 'aarch64-generic'),
    );
    if (!bundle.existsSync()) {
      throw StateError('Expected Flutter build output at ${bundle.path}.');
    }
    return writeGzl(
      project: project,
      bundle: bundle,
      runtime: runtimeArchive,
      spec: spec,
      output: Directory(path.join(project.path, output)),
    );
  } finally {
    root.deleteSync(recursive: true);
  }
}

Future<void> run(
  String executable,
  List<String> arguments,
  Directory cwd, {
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    environment: environment,
    workingDirectory: cwd.path,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(executable, arguments, 'Build failed', code);
  }
}

Future<List<int>> downloadRuntime() async {
  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_gizlet/src/build.dart'),
  );
  if (packageUri == null) throw StateError('Cannot locate flutter_gizlet.');
  final file = File.fromUri(packageUri.resolve('../../pubspec.yaml'));
  final version = (loadYaml(file.readAsStringSync()) as YamlMap)['version'];
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final url = Uri.parse(
      'https://github.com/gizlet/flutter_gizlet/releases/download/'
      'v$version/flutter-gizlet-runtime-arm64.zip',
    );
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Could not download the runtime (${response.statusCode}).',
        uri: url,
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 60))) {
      bytes.addAll(chunk);
      if (bytes.length > 32 * 1024 * 1024) {
        throw const FormatException('Runtime archive exceeds 32 MiB.');
      }
    }
    return bytes;
  } finally {
    client.close(force: true);
  }
}
