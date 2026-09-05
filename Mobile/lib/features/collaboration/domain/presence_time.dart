/// Epoch-zero and pre-epoch defaults are not IM activity observations. Keep
/// this local to presence: unrelated business dates must not be rewritten.
/// Normalize at display/projection boundaries too for existing SQLite caches.
DateTime? validPresenceTime(DateTime? value) =>
    value != null && value.microsecondsSinceEpoch > 0 ? value : null;
