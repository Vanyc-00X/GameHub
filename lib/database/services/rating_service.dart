import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final SupabaseClient _sb = Supabase.instance.client;
const List<String> _ratingTables = ['User_rating', 'user_rating'];
const List<String> _ratingStatsViews = [
  'User_rating_stats',
  'user_rating_stats',
];

/// Роли в сделке: оценивают по завершённому аукциону.
enum RatingRole { seller, buyer }

extension RatingRoleX on RatingRole {
  String get dbValue => this == RatingRole.seller ? 'seller' : 'buyer';
  String get label => this == RatingRole.seller ? 'продавца' : 'покупателя';
}

/// Статистика рейтинга пользователя.
class RatingStats {
  final double avgStars;
  final int count;
  const RatingStats({required this.avgStars, required this.count});
  const RatingStats.empty() : avgStars = 0, count = 0;

  String get formatted =>
      count == 0 ? '—' : '${avgStars.toStringAsFixed(1)} ($count)';
}

class RatingService {
  RatingService._();
  static final RatingService instance = RatingService._();

  /// Возвращает null при успехе или текст ошибки.
  Future<String?> submitRating({
    required String targetId,
    required int auctionId,
    required RatingRole role,
    required int stars,
    String? comment,
  }) async {
    final me = _sb.auth.currentUser;
    if (me == null) return 'Войдите в аккаунт';
    if (me.id == targetId) return 'Нельзя оценить самого себя';
    if (stars < 1 || stars > 5) return 'Оценка должна быть от 1 до 5';

    try {
      final table = await _resolveFirstExisting(_ratingTables);
      if (table == null) return 'Рейтинг пока недоступен в этой версии БД';
      await _sb.from(table).upsert({
        'rater_id': me.id,
        'target_id': targetId,
        'auction_id': auctionId,
        'role': role.dbValue,
        'stars': stars,
        'comment': (comment ?? '').trim().isEmpty ? null : comment!.trim(),
      }, onConflict: 'rater_id,auction_id,role');
      return null;
    } catch (e) {
      debugPrint('RatingService.submit ошибка: $e');
      return 'Не удалось сохранить оценку';
    }
  }

  Future<RatingStats> getStats(String userId) async {
    try {
      final view = await _resolveFirstExisting(_ratingStatsViews);
      if (view == null) return const RatingStats.empty();
      final row = await _sb
          .from(view)
          .select('avg_stars, ratings_count')
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return const RatingStats.empty();
      final avg = (row['avg_stars'] as num?)?.toDouble() ?? 0;
      final cnt = (row['ratings_count'] as num?)?.toInt() ?? 0;
      return RatingStats(avgStars: avg, count: cnt);
    } catch (e) {
      debugPrint('RatingService.getStats ошибка: $e');
      return const RatingStats.empty();
    }
  }

  Future<Map<String, RatingStats>> getStatsBatch(Iterable<String> userIds) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};

    try {
      final view = await _resolveFirstExisting(_ratingStatsViews);
      if (view == null) return const {};

      final rows = await _sb
          .from(view)
          .select('user_id, avg_stars, ratings_count')
          .inFilter('user_id', ids);

      final result = <String, RatingStats>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final userId = row['user_id']?.toString();
        if (userId == null) continue;
        result[userId] = RatingStats(
          avgStars: (row['avg_stars'] as num?)?.toDouble() ?? 0,
          count: (row['ratings_count'] as num?)?.toInt() ?? 0,
        );
      }
      return result;
    } catch (e) {
      debugPrint('RatingService.getStatsBatch ошибка: $e');
      return const {};
    }
  }

  Future<List<Map<String, dynamic>>> latestReviews(
    String userId, {
    int limit = 10,
  }) async {
    try {
      final table = await _resolveFirstExisting(_ratingTables);
      if (table == null) return [];
      final rows = await _sb
          .from(table)
          .select('id, stars, comment, role, created_at, rater_id, auction_id')
          .eq('target_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('RatingService.latest ошибка: $e');
      return [];
    }
  }

  Future<String?> deleteOwnRating(int ratingId) async {
    final me = _sb.auth.currentUser;
    if (me == null) return 'Войдите в аккаунт';
    try {
      final table = await _resolveFirstExisting(_ratingTables);
      if (table == null) return 'Рейтинг недоступен';
      await _sb.from(table).delete().eq('id', ratingId).eq('rater_id', me.id);
      return null;
    } catch (e) {
      debugPrint('RatingService.deleteOwnRating ошибка: $e');
      return 'Не удалось удалить оценку';
    }
  }

  /// Можно ли мне сейчас оценить контрагента по этому аукциону в указанной роли.
  /// Правила: аукцион завершён, у него есть winner_id, я — владелец или победитель,
  /// и я ещё не оценивал в этой роли.
  Future<({bool allowed, String? targetId, String? reason})> canRate({
    required int auctionId,
    required RatingRole role,
  }) async {
    final me = _sb.auth.currentUser;
    if (me == null) {
      return (allowed: false, targetId: null, reason: 'Войдите в аккаунт');
    }
    try {
      final a = await _sb
          .from('Auction_items')
          .select('id, owner_id, winner_id, is_active')
          .eq('id', auctionId)
          .maybeSingle();
      if (a == null) {
        return (allowed: false, targetId: null, reason: 'Аукцион не найден');
      }
      if (a['is_active'] == true) {
        return (allowed: false, targetId: null, reason: 'Аукцион ещё идёт');
      }
      final owner = a['owner_id']?.toString();
      final winner = a['winner_id']?.toString();
      if (owner == null || winner == null) {
        return (allowed: false, targetId: null, reason: 'Нет победителя');
      }

      String? target;
      if (role == RatingRole.seller && me.id == winner) {
        target = owner;
      } else if (role == RatingRole.buyer && me.id == owner) {
        target = winner;
      } else {
        return (allowed: false, targetId: null, reason: 'Нет прав на оценку');
      }

      final table = await _resolveFirstExisting(_ratingTables);
      if (table == null) {
        return (allowed: false, targetId: target, reason: 'Рейтинг недоступен');
      }
      final existing = await _sb
          .from(table)
          .select('id')
          .eq('rater_id', me.id)
          .eq('auction_id', auctionId)
          .eq('role', role.dbValue)
          .maybeSingle();
      if (existing != null) {
        return (allowed: false, targetId: target, reason: 'Уже оценено');
      }
      return (allowed: true, targetId: target, reason: null);
    } catch (e) {
      debugPrint('RatingService.canRate ошибка: $e');
      return (allowed: false, targetId: null, reason: '$e');
    }
  }

  Future<String?> _resolveFirstExisting(List<String> candidates) async {
    for (final t in candidates) {
      try {
        await _sb.from(t).select('id').limit(1);
        return t;
      } catch (_) {}
    }
    return null;
  }
}
