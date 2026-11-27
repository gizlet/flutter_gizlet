import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_gizlet/src/build.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()..addFlag('help', abbr: 'h', negatable: false);
  final build = parser.addCommand('build')
    ..addOption('arch', allowed: ['arm64'], defaultsTo: 'arm64')
    ..addOption('cpu', allowed: ['generic'], defaultsTo: 'generic')
    ..addFlag('release', negatable: false)
    ..addOption('output', defaultsTo: 'build/gizlet')
    ..addOption('runtime', help: 'Use a local Gizlet Flutter runtime ZIP.')
    ..addFlag('help', abbr: 'h', negatable: false);
  try {
    final parsed = parser.parse(arguments);
    final command = parsed.command;
    if (parsed['help'] as bool || arguments.isEmpty) {
      stdout.writeln('Usage: flutter_gizlet build [options]\n${build.usage}');
      return;
    }
    if (command == null || command.rest.isNotEmpty) {
      throw const FormatException('Usage: flutter_gizlet build [options]');
    }
    if (command['help'] as bool) {
      stdout.writeln('Usage: flutter_gizlet build [options]\n${build.usage}');
      return;
    }
    final package = await buildGizlet(
      Directory.current,
      output: command['output'] as String,
      runtime: command['runtime'] as String?,
    );
    stdout.writeln('Built ${package.path}');
  } on Exception catch (error) {
    stderr.writeln('flutter_gizlet: $error');
    exitCode = 1;
  }
}
