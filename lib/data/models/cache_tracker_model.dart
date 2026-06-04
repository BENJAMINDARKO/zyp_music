import 'package:hive/hive.dart';

/// Hive-persisted metadata for a single track in the hybrid cache.
///
/// One record per [trackId] lives inside the `cache_tracker_box`. The model
/// is intentionally lean — it tracks cache recency for LRU eviction, the
/// favorite guard flag that protects the entry from eviction, and the
/// optional persistent timed-lyrics payload.
class CacheTrackerModel {
  static const int kFieldTrackId = 0;
  static const int kFieldCachedAt = 1;
  static const int kFieldIsFavorite = 2;
  static const int kFieldTimedLyrics = 3;

  final String trackId;
  final int cachedAt;
  final bool isFavorite;
  final String? timedLyrics;

  CacheTrackerModel({
    required this.trackId,
    required this.cachedAt,
    this.isFavorite = false,
    this.timedLyrics,
  });

  CacheTrackerModel copyWith({
    String? trackId,
    int? cachedAt,
    bool? isFavorite,
    String? timedLyrics,
    bool clearLyrics = false,
  }) {
    return CacheTrackerModel(
      trackId: trackId ?? this.trackId,
      cachedAt: cachedAt ?? this.cachedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      timedLyrics: clearLyrics ? null : (timedLyrics ?? this.timedLyrics),
    );
  }
}

/// Hand-written Hive [TypeAdapter] for [CacheTrackerModel].
///
/// Fields are written/read in declaration order using fixed field IDs (0..3)
/// so the on-disk format is stable across releases.
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
    );
  }

  @override
  void write(BinaryWriter writer, CacheTrackerModel obj) {
    writer
      ..writeByte(4)
      ..writeByte(CacheTrackerModel.kFieldTrackId)
      ..write(obj.trackId)
      ..writeByte(CacheTrackerModel.kFieldCachedAt)
      ..write(obj.cachedAt)
      ..writeByte(CacheTrackerModel.kFieldIsFavorite)
      ..write(obj.isFavorite)
      ..writeByte(CacheTrackerModel.kFieldTimedLyrics)
      ..write(obj.timedLyrics);
  }
}
