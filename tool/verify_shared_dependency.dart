import 'dart:io';

const _expectedUrl = 'https://github.com/gammula/pureflutter.git';
const _disallowedRefs = <String>{'main', 'master', 'head', 'HEAD'};

Never fail(String message) {
  stderr.writeln('Shared dependency check failed: $message');
  exit(1);
}

String _normalizeYamlValue(String raw) {
  final hashIndex = raw.indexOf('#');
  final withoutComment = hashIndex >= 0 ? raw.substring(0, hashIndex) : raw;
  return withoutComment.trim().replaceAll('"', '').replaceAll("'", '');
}

void main() {
  final lines = File('pubspec.yaml').readAsLinesSync();
  final startIndex = lines.indexWhere(
    (line) => line.trim() == 'bullethole_shared:',
  );
  if (startIndex == -1) {
    fail('Missing bullethole_shared dependency in pubspec.yaml.');
  }

  final dependencyLine = lines[startIndex];
  final baseIndent = dependencyLine.length - dependencyLine.trimLeft().length;
  final block = <String>[];

  for (var i = startIndex + 1; i < lines.length; i += 1) {
    final line = lines[i];
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    final indent = line.length - line.trimLeft().length;
    if (indent <= baseIndent) {
      break;
    }
    block.add(line);
  }

  final blockText = block.join('\n');
  if (RegExp(r'^\s+path\s*:', multiLine: true).hasMatch(blockText)) {
    fail('Tracked pubspec.yaml must not use a local path dependency.');
  }
  if (!RegExp(r'^\s+git\s*:', multiLine: true).hasMatch(blockText)) {
    fail(
      'Tracked pubspec.yaml must use a git dependency for bullethole_shared.',
    );
  }

  final urlMatch = RegExp(
    r'^\s+url\s*:\s*(.+)$',
    multiLine: true,
  ).firstMatch(blockText);
  final refMatch = RegExp(
    r'^\s+ref\s*:\s*(.+)$',
    multiLine: true,
  ).firstMatch(blockText);

  final url = urlMatch == null ? null : _normalizeYamlValue(urlMatch.group(1)!);
  final ref = refMatch == null ? null : _normalizeYamlValue(refMatch.group(1)!);

  if (url != _expectedUrl) {
    fail(
      'Expected bullethole_shared git url to be $_expectedUrl, got ${url ?? '<missing>'}.',
    );
  }
  if (ref == null || ref.isEmpty) {
    fail(
      'Missing git ref for bullethole_shared. Use a release tag or commit SHA.',
    );
  }
  if (_disallowedRefs.contains(ref)) {
    fail('Ref "$ref" is too loose. Use a release tag or commit SHA.');
  }

  stdout.writeln('Verified bullethole_shared git dependency: $url @ $ref');
}
