import 'dart:io';
import 'dart:convert';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

// Would prefer a pure-dart solution which does not
// rely on the existance of a Flutter SDK.
class Paths {
  final String flutterSdk;
  final Directory tmpDir;
  String get tmpRoot => tmpDir.path;
  String tmp(String path) => p.join(tmpRoot, path);
  String get flutterCache => p.join(flutterSdk, 'bin/cache');
  String get engineArtifacts => p.join(flutterCache, 'artifacts/engine/');
  String get dart => p.join(flutterCache, "dart-sdk/bin/dart");
  String get genSnapshot =>
      p.join(engineArtifacts, "android-arm-profile/darwin-x64/gen_snapshot");
  String get frontendServer =>
      p.join(engineArtifacts, "darwin-x64/frontend_server.dart.snapshot");
  String get patchedSdk => p.join(
        engineArtifacts,
        "common/flutter_patched_sdk/",
      );

  Paths(this.flutterSdk) : tmpDir = Directory.systemTemp.createTempSync();
}

Future run(List<String> command) async {
  print(command.join(' '));
  return Process.run(command[0], command.sublist(1)).then((result) {
    stdout.write(result.stdout);
    stderr.write(result.stderr);
  });
}

class AssemblyParserResult {
  final String stderr;
  final String assembly;
  AssemblyParserResult(this.stderr, this.assembly);
}

AssemblyParserResult parseAssemblyFromStderr(String inputText) {
  List<String> errorLines = [];
  List<String> assemblyLines = [];

  bool inBlock = false;
  bool inAssembly = false;
  RegExp blockStart = new RegExp(r"^(.+)\{$");
  // Code for optimized function 'file:///src/dart2asm/default.dart_::_square' {
  RegExp assemblyStart = new RegExp(
      r"^Code for (?:optimized )?function '(.+)' \{$",
      multiLine: true);
  RegExp blockEnd = new RegExp(r"^\}$");

  for (String line in LineSplitter.split(inputText)) {
    if (inBlock) {
      if (blockEnd.hasMatch(line)) {
        inBlock = false;
        inAssembly = false;
      } else if (inAssembly) {
        assemblyLines.add(line);
      }
    } else {
      if (blockStart.hasMatch(line)) {
        inBlock = true;
        Match match = assemblyStart.matchAsPrefix(line);
        if (match != null) {
          inAssembly = true;
          // Add fake label:
          String functionPath = match.group(1);
          String functionName = functionPath.split('::').last;
          assemblyLines.add(functionName + ':');
        }
      } else {
        errorLines.add(line);
      }
    }
  }
  return AssemblyParserResult(errorLines.join('\n'), assemblyLines.join('\n'));
}

class Disassembler {
  final Paths paths;

  Disassembler(this.paths);

  Future<String> disassemble(ArgResults argResults) async {
    String sourcePath = argResults.rest.first;

    switch (argResults['type']) {
      case 'jit':
        return handleJIT(sourcePath);
      case 'aot':
        return handleAOT(sourcePath);
    }
    assert(false);
    return null;
  }

  Future<String> handleAOT(String sourcePath) async {
    String dillPath = paths.tmp('app.dill');

    // This seems like an awkward way to get a .dill file, presumably
    // dart --snapshot=dillPath sourcePath might also work?
    await run([
      paths.dart,
      paths.frontendServer,
      "--sdk-root",
      paths.patchedSdk,
      "--target=flutter",
      "--aot",
      "--output-dill=" + dillPath,
      sourcePath,
    ]);

    // await run([
    //   paths.genSnapshot,
    //   "--causal_async_stacks",
    //   "--deterministic",
    //   "--snapshot_kind=app-aot-assembly",
    //   "--assembly=" + results['output'],
    //   dillPath,
    // ]);

    String filename = p.basename(sourcePath);
    ProcessResult result = await Process.run(paths.genSnapshot, [
      "--causal_async_stacks",
      "--deterministic",
      "--disassemble-optimized",
      "--snapshot_kind=app-aot-blobs",
      "--blobs_container_filename=" + paths.tmpRoot,
      "--print-flow-graph-filter=" + filename,
      dillPath,
    ]);
    stdout.write(result.stdout);
    AssemblyParserResult parseResult = parseAssemblyFromStderr(result.stderr);
    stderr.write(parseResult.stderr);
    return parseResult.assembly;
  }

  Future<String> handleJIT(String sourcePath) async {
    String filename = p.basename(sourcePath);
    ProcessResult result = await Process.run(paths.dart, [
      "--disassemble-optimized",
      "--print-flow-graph-filter=" + filename,
      sourcePath,
    ]);
    stdout.write(result.stdout);
    AssemblyParserResult parseResult = parseAssemblyFromStderr(result.stderr);
    stderr.write(parseResult.stderr);
    return parseResult.assembly;
  }
}

dynamic main(List<String> args) async {
  var parser = new ArgParser();
  parser.addOption('output', abbr: 'o', defaultsTo: 'out.S');
  parser.addOption('type', defaultsTo: 'aot', allowed: ['jit', 'aot']);
  parser.addFlag('version',
      negatable: false, help: 'display dart version info and exit');
  parser.addFlag('help', negatable: false, help: 'display usage and exit');
  var argResults = parser.parse(args);
  if (argResults['version']) {
    print(Platform.version);
    return;
  }
  if (argResults['help']) {
    print("Usage: dart2asm [options] <input>\n");
    print("converts .dart files to .s assembly syntax\n");
    print("Options:");
    print(parser.usage);
    return;
  }

  // FIXME: This should not require a flutter install.
  Paths paths = new Paths('/src/flutter');
  Disassembler disassembler = new Disassembler(paths);
  String assembly = await disassembler.disassemble(argResults);
  new File(argResults['output']).writeAsStringSync(assembly);
}
