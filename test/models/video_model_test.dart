import 'package:flutter_test/flutter_test.dart';
import 'package:ytmusix/data/models/video_model.dart';
import 'package:ytmusix/domain/entities/video.dart';

void main() {
  group('TrackModel', () {
    test('fromMap creates model correctly', () {
      final map = {
        'id': 'abc123def45',
        'title': 'Test Video',
        'thumbnailUrl': 'https://example.com/thumb.jpg',
        'durationSeconds': 300,
        'author': 'Test Author',
        'idx': 1,
      };

      final model = TrackModel.fromMap(map);

      expect(model.id, 'abc123def45');
      expect(model.title, 'Test Video');
      expect(model.thumbnailUrl, 'https://example.com/thumb.jpg');
      expect(model.durationSeconds, 300);
      expect(model.author, 'Test Author');
      expect(model.index, 1);
    });

    test('fromMap handles missing optional fields', () {
      final map = {
        'id': 'abc123def45',
        'title': 'Test Video',
      };

      final model = TrackModel.fromMap(map);

      expect(model.id, 'abc123def45');
      expect(model.title, 'Test Video');
      expect(model.thumbnailUrl, isNull);
      expect(model.durationSeconds, 0);
      expect(model.author, isNull);
      expect(model.index, 0);
    });

    test('toMap returns correct map', () {
      final model = TrackModel(
        id: 'abc123def45',
        title: 'Test Video',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        durationSeconds: 180,
        author: 'Author',
        index: 2,
      );

      final map = model.toMap();

      expect(map['id'], 'abc123def45');
      expect(map['title'], 'Test Video');
      expect(map['thumbnailUrl'], 'https://example.com/thumb.jpg');
      expect(map['durationSeconds'], 180);
      expect(map['author'], 'Author');
      expect(map['idx'], 2);
    });

    test('toEntity converts correctly', () {
      final model = TrackModel(
        id: 'abc123def45',
        title: 'Test Video',
        durationSeconds: 120,
        author: 'Author',
        index: 0,
      );

      final entity = model.toEntity();

      expect(entity.id, 'abc123def45');
      expect(entity.title, 'Test Video');
      expect(entity.duration.inSeconds, 120);
      expect(entity.author, 'Author');
      expect(entity.index, 0);
    });

    test('toEntity handles zero duration', () {
      final model = TrackModel(id: 'v1', title: 'V1');
      final entity = model.toEntity();
      expect(entity.duration, Duration.zero);
    });

    test('Track entity has correct type', () {
      final model = TrackModel(id: 'v1', title: 'V1');
      final entity = model.toEntity();
      expect(entity, isA<Track>());
    });
  });
}
