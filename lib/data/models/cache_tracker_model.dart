import 'package:hive/hive.dart';

/// Hive-persisted metadata for a single track in the hybrid cache.
///
/// One record per [trackId] lives inside the `cache_tracker_box`. The model
/// is intentionally lean — it tracks cache recency for LRU eviction, the
/// favorite guard flag that protects the entry from eviction, the optional
/// persistent timed-lyrics payload, and a [lyricsVerified] boolean used by
/// the write-time validation hook to flag tracks whose lyrics payload
/// could not be confirmed against the on-disk LRC + the Hive blob.
class CacheTrackerModel {
  static const int kFieldTrackId = 0;
  static const int kFieldCachedAt = 1;
  static const int kFieldIsFavorite = 2;
  static const int kFieldTimedLyrics = 3;
  static const int kFieldLyricsFilePath = 4;
  static const int kFieldLyricsVerified = 5;
  static const int kFieldGenre = 6;
  static const int kFieldTitle = 7;
  static const int kFieldAuthor = 8;
  static const int kFieldThumbnailUrl = 9;

  final String trackId;
  final int cachedAt;
  final bool isFavorite;
  final String? timedLyrics;
  final String? lyricsFilePath;
  final bool lyricsVerified;

  /// Phase 5: per-track genre string captured at fetch time
  /// (mirrored from `track_metadata.genre` in SQLite). Used by
  /// the AI DJ routing layer so it can score candidates
  /// without a Hive round-trip per lookup. Nullable on
  /// records written before this field was added (handled by
  /// the adapter's null-safe read).
  final String? genre;

  /// Phase 6: display metadata captured at cache-commit time.
  /// Mirrors the source [Track]'s title / author / thumbnail
  /// so the synthesis paths in `QueueManager._buildTrackFromId`
  /// and `LocalCrateMiner._mineFromHive` can return a populated
  /// `Track` from the Hive tier alone, without a SQLite
  /// round-trip. Nullable on records written before this
  /// field was added (handled by the adapter's null-safe read
  /// and hydrated on first launch by `CacheMetadataBackfill`).
  final String? title;
  final String? author;
  final String? thumbnailUrl;

  CacheTrackerModel({
    required this.trackId,
    required this.cachedAt,
    this.isFavorite = false,
    this.timedLyrics,
    this.lyricsFilePath,
    this.lyricsVerified = true,
    this.genre,
    this.title,
    this.author,
    this.thumbnailUrl,
  });

  CacheTrackerModel copyWith({
    String? trackId,
    int? cachedAt,
    bool? isFavorite,
    String? timedLyrics,
    String? lyricsFilePath,
    bool? lyricsVerified,
    String? genre,
    String? title,
    String? author,
    String? thumbnailUrl,
    bool clearLyrics = false,
    bool clearLyricsFilePath = false,
    bool clearGenre = false,
    bool clearTitle = false,
    bool clearAuthor = false,
    bool clearThumbnailUrl = false,
  }) {
    return CacheTrackerModel(
      trackId: trackId ?? this.trackId,
      cachedAt: cachedAt ?? this.cachedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      timedLyrics: clearLyrics ? null : (timedLyrics ?? this.timedLyrics),
      lyricsFilePath: clearLyricsFilePath
          ? null
          : (lyricsFilePath ?? this.lyricsFilePath),
      lyricsVerified: lyricsVerified ?? this.lyricsVerified,
      genre: clearGenre ? null : (genre ?? this.genre),
      title: clearTitle ? null : (title ?? this.title),
      author: clearAuthor ? null : (author ?? this.author),
      thumbnailUrl:
          clearThumbnailUrl ? null : (thumbnailUrl ?? this.thumbnailUrl),
    );
  }
}

/// Hand-written Hive [TypeAdapter] for [CacheTrackerModel].
///
/// Fields are written/read in declaration order using fixed field IDs (0..5)
/// so the on-disk format is stable across releases. Older records that were
/// written before [CacheTrackerModel.kFieldLyricsFilePath] existed simply
/// surface with a `null` lyrics file path, which the eviction pipeline
/// tolerates by falling back to the deterministic trackId-keyed file name.
/// Records written before [CacheTrackerModel.kFieldLyricsVerified] existed
/// surface with `lyricsVerified = true` (optimistic) so legacy tracks do not
/// get treated as missing on the very first launch after the schema bump.
class CacheTrackerModelAdapter extends TypeAdapter<CacheTrackerModel> {
  @override
  final int typeId = 1;

  @override
  CacheTrackerModel read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return CacheTrackerModel(
      trackId: fields[CacheTrackerModel.kFieldTrackId] as String,
      cachedAt: fields[CacheTrackerModel.kFieldCachedAt] as int,
      isFavorite: (fields[CacheTrackerModel.kFieldIsFavorite] as bool?) ?? false,
      timedLyrics: fields[CacheTrackerModel.kFieldTimedLyrics] as String?,
      lyricsFilePath: fields[CacheTrackerModel.kFieldLyricsFilePath] as String?,
      lyricsVerified:
          (fields[CacheTrackerModel.kFieldLyricsVerified] as bool?) ?? true,
      // Phase 5: field 6 is optional; records written before
      // this migration surface with `genre = null`, which the
      // routing service treats as "no signal — fall back to
      // the listening-history ledger".
      genre: fields[CacheTrackerModel.kFieldGenre] as String?,
      // Phase 6: fields 7/8/9 are optional; records written
      // before this migration surface with `title = null`,
      // which the synthesis paths treat as "fall through to
      // the SQLite tier or the stub". Hydrated on first
      // launch by `CacheMetadataBackfill`.
      title: fields[CacheTrackerModel.kFieldTitle] as String?,
      author: fields[CacheTrackerModel.kFieldAuthor] as String?,
      thumbnailUrl: fields[CacheTrackerModel.kFieldThumbnailUrl] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, CacheTrackerModel obj) {
    writer
      ..writeByte(10)
      ..writeByte(CacheTrackerModel.kFieldTrackId)
      ..write(obj.trackId)
      ..writeByte(CacheTrackerModel.kFieldCachedAt)
      ..write(obj.cachedAt)
      ..writeByte(CacheTrackerModel.kFieldIsFavorite)
      ..write(obj.isFavorite)
      ..writeByte(CacheTrackerModel.kFieldTimedLyrics)
      ..write(obj.timedLyrics)
      ..writeByte(CacheTrackerModel.kFieldLyricsFilePath)
      ..write(obj.lyricsFilePath)
      ..writeByte(CacheTrackerModel.kFieldLyricsVerified)
      ..write(obj.lyricsVerified)
      ..writeByte(CacheTrackerModel.kFieldGenre)
      ..write(obj.genre)
      ..writeByte(CacheTrackerModel.kFieldTitle)
      ..write(obj.title)
      ..writeByte(CacheTrackerModel.kFieldAuthor)
      ..write(obj.author)
      ..writeByte(CacheTrackerModel.kFieldThumbnailUrl)
      ..write(obj.thumbnailUrl);
  }
}
