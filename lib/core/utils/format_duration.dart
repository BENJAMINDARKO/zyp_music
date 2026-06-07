/// Renders a [Duration] as `m:ss` / `h:mm:ss`. Returns the
/// placeholder `'—:—'` (em-dash) when [d] is `null`, per the
/// C1 honest-nulls invariant: unknown duration should never
/// display as `0:00`. The em-dash form is conventional in
/// music apps for "unknown" and is used uniformly across
/// album / artist / playlist / search list rows.
String formatDuration(Duration? d) {
  if (d == null) return '—:—';
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  return '${d.inHours > 0 ? '${d.inHours}:' : ''}${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
