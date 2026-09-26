import 'package:flutter_test/flutter_test.dart';
import 'package:kurayomi/domain/models/track.dart';

void main() {
  group('TrackerId', () {
    test('parses known names and rejects junk', () {
      expect(TrackerId.parse('anilist'), TrackerId.anilist);
      expect(TrackerId.parse('myanimelist'), TrackerId.myanimelist);
      expect(TrackerId.parse('kitsu'), isNull);
      expect(TrackerId.parse(null), isNull);
    });
  });

  group('TrackStatus', () {
    test('falls back to reading for an unknown value', () {
      expect(TrackStatus.parse('completed'), TrackStatus.completed);
      expect(TrackStatus.parse('nonsense'), TrackStatus.reading);
      expect(TrackStatus.parse(null), TrackStatus.reading);
    });
  });

  group('TrackLink', () {
    const link = TrackLink(
      itemId: 3,
      tracker: TrackerId.anilist,
      remoteId: '30013',
      title: 'One Piece',
      status: TrackStatus.reading,
      lastProgress: 1090,
      totalUnits: 0,
      score: 9,
    );

    test('round-trips through the database row shape', () {
      final restored = TrackLink.fromRow({'id': 5, ...link.toRow()});
      expect(restored.id, 5);
      expect(restored.itemId, 3);
      expect(restored.tracker, TrackerId.anilist);
      expect(restored.remoteId, '30013');
      expect(restored.lastProgress, 1090);
      expect(restored.score, 9);
    });

    test('an unknown tracker in a row does not throw', () {
      final restored =
          TrackLink.fromRow({...link.toRow(), 'tracker': 'kitsu'});
      expect(restored.tracker, TrackerId.anilist);
    });

    test('copyWith only touches what it is given', () {
      final next = link.copyWith(lastProgress: 1091);
      expect(next.lastProgress, 1091);
      expect(next.status, TrackStatus.reading);
      expect(next.remoteId, '30013');
      expect(next.score, 9);
    });
  });
}
