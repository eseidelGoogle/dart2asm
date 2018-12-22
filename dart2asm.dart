import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

// Would prefer a pure-dart solution which does not
// rely on the existance of a Flutter SDK.
class Paths {
  final String flutterSdk;
  String get flutterCache => p.join(flutterSdk, 'bin/cache');
  String get engineArtifacts => p.join(flutterCache, 'artifacts/engine/');
  String get dart => p.join(flutterCache, "dart-sdk/bin/dart");
  String get genSnapshot =>
      p.join(engineArtifacts, "android-arm-release/darwin-x64/gen_snapshot");
  String get frontendServer =>
      p.join(engineArtifacts, "darwin-x64/frontend_server.dart.snapshot");
  String get patchedSdk => p.join(
        engineArtifacts,
        "common/flutter_patched_sdk/",
      );

  Paths(this.flutterSdk);
}

Future run(List<String> command) async {
  print(command.join(' '));
  return Process.run(command[0], command.sublist(1)).then((result) {
    stdout.write(result.stdout);
    stderr.write(result.stderr);
  });
}

void main(List<String> args) async {
  Paths paths = new Paths('/src/flutter');
  var parser = new ArgParser();
  parser.addOption('output', abbr: 'o', defaultsTo: 'out.S');
  parser.addFlag('version');
  var results = parser.parse(args);
  if (results['version']) {
    print(Platform.version);
    return;
  }

  String source = results.rest.first;

  Directory tempDir = Directory.systemTemp.createTempSync();
  String dillPath = p.join(tempDir.path, 'app.dill');

  await run([
    paths.dart,
    paths.frontendServer,
    "--sdk-root",
    paths.patchedSdk,
    "--target=flutter",
    "--aot",
    "--output-dill=" + dillPath,
    source,
  ]);

  await run([
    paths.genSnapshot,
    "--causal_async_stacks",
    "--deterministic",
    "--snapshot_kind=app-aot-assembly",
    "--assembly=" + results['output'],
    dillPath,
  ]);
}
