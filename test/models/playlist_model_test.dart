import 'package:flutter_test/flutter_test.dart';
import 'package:ytmusix/data/models/playlist_model.dart';
import 'package:ytmusix/data/models/video_model.dart';
import 'package:ytmusix/domain/entities/playlist.dart';

void main() {
  group('PlaylistModel', () {
    test('fromMap creates model correctly', () {
      final map = {
        'id': 'PL123',
        'title': 'Test Playlist',
        'description': 'A test playlist',
        'thumbnailUrl': 'https://example.com/thumb.jpg',
        'author': 'Test Channel',
        'videoCount': 3,
      };

      final model = PlaylistModel.fromMap(map);

      expect(model.id, 'PL123');
      expect(model.title, 'Test Playlist');
      expect(model.description, 'A test playlist');
      expect(model.thumbnailUrl, 'https://example.com/thumb.jpg');
      expect(model.author, 'Test Channel');
      expect(model.videoCount, 3);
      expect(model.tracks, isEmpty);
    });

    test('fromMap handles missing optional fields', () {
      final map = {
        'id': 'PL123',
        'title': 'Test Playlist',
      };

      final model = PlaylistModel.fromMap(map);

      expect(model.id, 'PL123');
      expect(model.title, 'Test Playlist');
      expect(model.description, isNull);
      expect(model.thumbnailUrl, isNull);
      expect(model.author, isNull);
      expect(model.videoCount, 0);
    });

    test('toMap returns correct map', () {
      final model = PlaylistModel(
        id: 'PL123',
        title: 'Test Playlist',
        description: 'Desc',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        author: 'Channel',
        videoCount: 5,
      );

      final map = model.toMap();

      expect(map['id'], 'PL123');
      expect(map['title'], 'Test Playlist');
      expect(map['description'], 'Desc');
      expect(map['thumbnailUrl'], 'https://example.com/thumb.jpg');
      expect(map['author'], 'Channel');
      expect(map['videoCount'], 5);
      expect(map.containsKey('tracks'), false);
    });

    test('toEntity converts correctly', () {
      final track = TrackModel(id: 'v1', title: 'Video 1');
      final model = PlaylistModel(
        id: 'PL123',
        title: 'Test',
        tracks: [track],
      );

      final entity = model.toEntity();

      expect(entity.id, 'PL123');
      expect(entity.title, 'Test');
      expect(entity.tracks.length, 1);
      expect(entity.tracks.first.id, 'v1');
      expect(entity.tracks.first.title, 'Video 1');
    });

    test('toEntity -> Playlist has correct types', () {
      final model = PlaylistModel(id: 'P1', title: 'T1');
      final entity = model.toEntity();
      expect(entity, isA<Playlist>());
    });
  });
}
