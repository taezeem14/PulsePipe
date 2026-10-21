import 'package:flutter/foundation.dart';
import 'song.dart';

@immutable
class Playlist {
  final String id;
  final String title;
  final String description;
  final List<Song> songs;
  final DateTime createdAt;
  final String? coverUrl;
  final String? continuationToken;

  const Playlist({
    required this.id,
    required this.title,
    this.description = '',
    required this.songs,
    required this.createdAt,
    this.coverUrl,
    this.continuationToken,
  });

  Playlist copyWith({
    String? id,
    String? title,
    String? description,
    List<Song>? songs,
    DateTime? createdAt,
    String? coverUrl,
    String? continuationToken,
  }) {
    return Playlist(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      songs: songs ?? this.songs,
      createdAt: createdAt ?? this.createdAt,
      coverUrl: coverUrl ?? this.coverUrl,
      continuationToken: continuationToken ?? this.continuationToken,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'songs': songs.map((s) => s.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'coverUrl': coverUrl,
      'continuationToken': continuationToken,
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map) {
    final rawSongs = map['songs'];
    final List<Song> songList = rawSongs is List
        ? rawSongs
            .whereType<Map>()
            .map((item) => Song.fromMap(Map<String, dynamic>.from(item)))
            .toList()
        : [];

    return Playlist(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Untitled Playlist',
      description: map['description']?.toString() ?? '',
      songs: songList,
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      coverUrl: (map['coverUrl']?.toString().isNotEmpty == true) ? map['coverUrl'].toString() : null,
      continuationToken: map['continuationToken']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Playlist &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          description == other.description &&
          coverUrl == other.coverUrl &&
          listEquals(songs, other.songs);

  @override
  int get hashCode => Object.hash(id, title, description, coverUrl);

  @override
  String toString() => 'Playlist(id: $id, title: $title, ${songs.length} tracks)';
}
