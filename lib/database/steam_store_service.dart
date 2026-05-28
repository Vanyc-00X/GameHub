import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SteamAppInfo {
  final String appId;
  final String name;
  final String headerImageUrl;
  final String storeUrl;

  const SteamAppInfo({
    required this.appId,
    required this.name,
    required this.headerImageUrl,
    required this.storeUrl,
  });
}

/// Метаданные игр из Steam Store (название, обложка) по URL или app id.
class SteamStoreService {
  SteamStoreService._();
  static final instance = SteamStoreService._();

  static const _storeApiBase =
      'https://store.steampowered.com/api/appdetails';

  /// Postgres text не принимает NUL и управляющие символы.
  static String sanitizeDbText(String value, {bool allowNewlines = false}) {
    final pattern = allowNewlines
        ? RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]')
        : RegExp(r'[\x00-\x1F]');
    return value.replaceAll(pattern, '');
  }

  String? extractAppId(String raw) {
    final input = sanitizeDbText(raw.trim());
    if (input.isEmpty) return null;

    final direct = RegExp(r'^\d+$').firstMatch(input);
    if (direct != null) return direct.group(0);

    try {
      final uri = input.contains('://') ? Uri.parse(input) : null;
      if (uri != null) {
        final seg = uri.pathSegments;
        final appIdx = seg.indexOf('app');
        if (appIdx != -1 && appIdx + 1 < seg.length) {
          return seg[appIdx + 1];
        }
      }
    } catch (_) {}

    final path = input
        .replaceFirst(RegExp(r'^/+'), '')
        .replaceFirst(RegExp(r'/+$'), '');
    final match = RegExp(r'^(?:app/)?(\d+)(?:/([^/]+))?/?$').firstMatch(path);
    return match?.group(1);
  }

  String normalizeSteamUrl(String raw) {
    final input = sanitizeDbText(raw.trim());
    if (input.isEmpty) {
      throw Exception('Укажите URL игры в Steam');
    }

    if (input.startsWith('http://') || input.startsWith('https://')) {
      return input;
    }

    if (RegExp(r'^\d+$').hasMatch(input)) {
      return 'https://store.steampowered.com/app/$input/';
    }

    var path = input;
    if (path.contains('steampowered.com')) {
      path = path.contains('://') ? Uri.parse(path).path : '/$path';
    }
    path = path.replaceFirst(RegExp(r'^/+'), '').replaceFirst(RegExp(r'/+$'), '');

    final match = RegExp(r'^(?:app/)?(\d+)(?:/([^/]+))?/?$').firstMatch(path);
    if (match != null) {
      final appId = match.group(1)!;
      final slug = match.group(2);
      if (slug == null || slug.isEmpty) {
        return 'https://store.steampowered.com/app/$appId/';
      }
      return 'https://store.steampowered.com/app/$appId/$slug/';
    }

    throw Exception(
      'Укажите полный URL Steam или путь вида 123456/Game_Name',
    );
  }

  String headerImageUrlForAppId(String appId) {
    return 'https://cdn.akamai.steamstatic.com/steam/apps/$appId/header.jpg';
  }

  /// Для списков аукционов: [url_item] может быть и картинкой, и ссылкой на Steam.
  String resolveAuctionImageUrl(String? urlItem) {
    if (urlItem == null || urlItem.isEmpty) return '';
    if (_looksLikeImageUrl(urlItem)) return urlItem;

    final appId = extractAppId(urlItem);
    if (appId != null) return headerImageUrlForAppId(appId);
    return urlItem;
  }

  Future<SteamAppInfo> fetchAppInfo(String rawInput) async {
    final storeUrl = normalizeSteamUrl(rawInput);
    final appId = extractAppId(storeUrl);
    if (appId == null) {
      throw Exception('Игра не найдена в Steam. Проверьте ссылку или App ID.');
    }

    try {
      final uri = Uri.parse('$_storeApiBase?appids=$appId&l=russian');
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception(
          'Не удалось проверить игру в Steam. Попробуйте позже.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception(
          'Не удалось проверить игру в Steam. Попробуйте позже.',
        );
      }

      final entry = decoded[appId];
      if (entry is! Map<String, dynamic> || entry['success'] != true) {
        throw Exception(
          'Игра не найдена в Steam. Проверьте ссылку или App ID.',
        );
      }

      final data = entry['data'];
      if (data is! Map<String, dynamic>) {
        throw Exception(
          'Игра не найдена в Steam. Проверьте ссылку или App ID.',
        );
      }

      final name = sanitizeDbText(data['name'] as String? ?? '');
      if (name.isEmpty) {
        throw Exception(
          'Игра не найдена в Steam. Проверьте ссылку или App ID.',
        );
      }

      final image = sanitizeDbText(
        (data['header_image'] as String?) ?? headerImageUrlForAppId(appId),
      );

      return SteamAppInfo(
        appId: appId,
        name: name,
        headerImageUrl: image,
        storeUrl: storeUrl,
      );
    } on Exception {
      rethrow;
    } catch (e, st) {
      debugPrint('SteamStoreService.fetchAppInfo: $e\n$st');
      throw Exception(
        'Не удалось проверить игру в Steam. Попробуйте позже.',
      );
    }
  }

  String titleFromStoreUrl(String steamUrl) {
    try {
      final u = Uri.parse(steamUrl);
      final seg = u.pathSegments;
      final appIdx = seg.indexOf('app');
      if (appIdx != -1 && appIdx + 2 < seg.length) {
        return seg[appIdx + 2].replaceAll('_', ' ');
      }
    } catch (_) {}
    return steamUrl;
  }

  bool _looksLikeImageUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('steampowered.com/app/')) return false;
    return lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.png') ||
        lower.contains('.webp') ||
        lower.contains('.avif') ||
        lower.contains('steamstatic.com/steam/apps/') ||
        lower.contains('steamstatic.com/store_item_assets/');
  }
}
