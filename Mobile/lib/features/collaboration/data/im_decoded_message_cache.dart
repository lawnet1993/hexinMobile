import '../domain/collaboration_models.dart';

/// Reuses decoding only after a fresh SQLite query returns the exact same row,
/// including ciphertext, local send state and the computed receipt projection.
/// It never replaces the database query or bypasses authentication of new data.
final class ImDecodedMessageCache {
  ImDecodedMessageCache({
    this.maxEntries = 4096,
    this.maxSourceCharacters = 2 * 1024 * 1024,
  }) : assert(maxEntries > 0),
       assert(maxSourceCharacters > 0);

  final int maxEntries;
  // Exact retained source-string characters, not a claim about VM heap bytes.
  final int maxSourceCharacters;
  final _entries = <(String, String, String), _DecodedRow>{};
  int _characters = 0;
  int _generation = 0;
  int get generation => _generation;
  int get entryCount => _entries.length;
  int get sourceCharacters => _characters;

  Future<ImMessage> read(
    String accountId,
    Map<String, Object?> row, {
    required int generation,
    required Future<ImMessage> Function() decode,
    void Function()? onReuse,
  }) {
    // A query/decode already in flight at logout may finish for its caller,
    // but must never repopulate the cleared cache.
    if (generation != _generation) return Future.sync(decode);
    final key = (
      accountId,
      row['conversation_id'] as String,
      row['id'] as String,
    );
    final existing = _entries.remove(key);
    if (existing != null) {
      if (existing.matches(row)) {
        _entries[key] = existing;
        onReuse?.call();
        return existing.value;
      }
      _characters -= existing.characters;
    }
    final characters = row.values.fold<int>(
      0,
      (sum, value) => sum + (value is String ? value.length : 0),
    );
    if (characters > maxSourceCharacters) return Future.sync(decode);
    final entry = _DecodedRow(Map.unmodifiable(row), characters);
    entry.value = Future<ImMessage>.sync(decode).then(
      (message) => message,
      onError: (Object error, StackTrace stack) {
        if (identical(_entries[key], entry)) {
          _entries.remove(key);
          _characters -= entry.characters;
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    _entries[key] = entry;
    _characters += characters;
    while (_entries.length > maxEntries || _characters > maxSourceCharacters) {
      _characters -= _entries.remove(_entries.keys.first)!.characters;
    }
    return entry.value;
  }

  void clear() {
    _generation++;
    _entries.clear();
    _characters = 0;
  }
}

final class _DecodedRow {
  _DecodedRow(this.row, this.characters);
  final Map<String, Object?> row;
  final int characters;
  late final Future<ImMessage> value;
  bool matches(Map<String, Object?> other) =>
      row.length == other.length &&
      row.entries.every(
        (item) => other.containsKey(item.key) && other[item.key] == item.value,
      );
}
