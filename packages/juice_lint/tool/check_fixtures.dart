// Verifies the juice_lint fixtures: runs `dart analyze` on example/ (which
// enables the plugin) and requires EXACTLY the diagnostics the
// `// expect_lint: <rule>` markers declare — each marker's rule on the line
// below it, and nothing else (no missing lint, no over-firing lint, no other
// analyzer issue).
//
//   dart run tool/check_fixtures.dart     # from packages/juice_lint
//
// The analyze step is the proof that matters: the rules are reported by the
// stock `dart analyze` CLI, not by a side runner.
import 'dart:io';

final _marker = RegExp(r'//\s*expect_lint:\s*([a-z_]+)');

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final example = Directory('${root.path}/example');

  final expected = <String>{};
  final libDir = Directory('${example.path}/lib');
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final match = _marker.firstMatch(lines[i]);
      if (match == null) continue;
      expected.add(_key(entity.absolute.path, i + 2, match.group(1)!));
    }
  }

  final result = await Process.run(Platform.resolvedExecutable, [
    'analyze',
    '--format=machine',
    '.',
  ], workingDirectory: example.path);

  final actual = <String>{};
  final other = <String>[];
  for (final line in '${result.stdout}\n${result.stderr}'.split('\n')) {
    final parts = line.split('|');
    if (parts.length < 8) continue;
    final code = parts[2].toLowerCase();
    if (!code.startsWith('juice_')) {
      other.add(line);
      continue;
    }
    actual.add(_key(parts[3], int.parse(parts[4]), code));
  }

  final missing = expected.difference(actual).toList()..sort();
  final extra = actual.difference(expected).toList()..sort();
  for (final m in missing) {
    stderr.writeln('MISSING   $m');
  }
  for (final e in extra) {
    stderr.writeln('UNEXPECTED $e');
  }
  for (final o in other) {
    stderr.writeln('OTHER     $o');
  }
  if (missing.isNotEmpty || extra.isNotEmpty || other.isNotEmpty) {
    stderr.writeln('juice_lint fixtures: FAILED');
    exit(1);
  }
  final rules = {for (final k in actual) k.split(' ').last};
  stdout.writeln(
    'juice_lint fixtures: OK — ${actual.length} expected diagnostics '
    'across ${rules.length} rules, no over-firing.',
  );
}

String _key(String path, int line, String code) {
  final rel = path.substring(path.indexOf('example/lib/') + 8);
  return '$rel:$line $code';
}
