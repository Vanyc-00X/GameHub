import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

final SupabaseClient _sb = Supabase.instance.client;

class UploadedMedia {
  final String url;
  final String storagePath;
  final String bucket;
  final String name;
  final int sizeBytes;
  final String? mime;

  const UploadedMedia({
    required this.url,
    required this.storagePath,
    required this.bucket,
    required this.name,
    required this.sizeBytes,
    this.mime,
  });
}

/// Загрузка файлов в бакеты [chat-media] и [post-media].
/// Путь: [uid]/[uuid][ext]. Первый сегмент — uid (под RLS).
class MediaService {
  MediaService._();
  static final MediaService instance = MediaService._();

  static const String chatBucket = 'chat-media';
  static const String postBucket = 'post-media';
  static const String fallbackBucket = 'avatars';
  static const String sharedBucket = 'media';

  final _uuid = const Uuid();

  Future<UploadedMedia?> uploadChatMedia({
    required dynamic chatId,
    required File file,
    String? contentType,
  }) => _upload(bucket: chatBucket, file: file, contentType: contentType);

  Future<UploadedMedia?> uploadPostMedia({
    required File file,
    String? contentType,
  }) => _upload(bucket: postBucket, file: file, contentType: contentType);

  Future<UploadedMedia?> _upload({
    required String bucket,
    required File file,
    String? contentType,
  }) async {
    final user = _sb.auth.currentUser;
    if (user == null) return null;

    try {
      final ext = p.extension(file.path).isEmpty ? '' : p.extension(file.path);
      final fileName = '${_uuid.v4()}$ext';
      final objectPath = '${user.id}/$fileName';
      final bytes = await file.readAsBytes();

      final preferred = [bucket, sharedBucket, fallbackBucket];
      final tried = <String>{};
      for (final b in preferred) {
        if (!tried.add(b)) continue;
        try {
          await _sb.storage
              .from(b)
              .uploadBinary(
                objectPath,
                bytes,
                fileOptions: FileOptions(
                  contentType: contentType,
                  upsert: false,
                ),
              );
          final publicUrl = _sb.storage.from(b).getPublicUrl(objectPath);
          return UploadedMedia(
            url: publicUrl,
            storagePath: objectPath,
            bucket: b,
            name: p.basename(file.path),
            sizeBytes: bytes.length,
            mime: contentType,
          );
        } catch (e) {
          debugPrint('MediaService.upload fail for bucket "$b": $e');
        }
      }
      throw Exception(
        'Не удалось загрузить файл. Проверьте Storage bucket: '
        '"$bucket" (или "$sharedBucket"/"$fallbackBucket") и RLS policy на INSERT/SELECT.',
      );
    } catch (e, st) {
      debugPrint('MediaService.upload ошибка: $e\n$st');
      return null;
    }
  }
}
