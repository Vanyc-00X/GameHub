import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const Duration kAuctionSnipeExtension = Duration(minutes: 2);
const int kMinBidStep = 50;
const List<String> _userTableCandidates = ['User', 'users', 'user', '"User"'];

/// Логика аукционов по схеме [Auction_items] / [Bid_auction].
class AuctionService {
  AuctionService._();
  static final instance = AuctionService._();

  final SupabaseClient _c = Supabase.instance.client;

  /// Завершает аукционы, у которых [ended_at] в прошлом: [is_active]=false, [winner_id]=лучшая ставка.
  Future<void> finalizeExpiredAuctions() async {
    final now = DateTime.now().toUtc();
    final nowStr = _toDbTimestamp(now);

    final rows = await _c
        .from('Auction_items')
        .select('id')
        .eq('is_active', true)
        .lte('ended_at', nowStr);

    final list = List<Map<String, dynamic>>.from(rows);
    for (final r in list) {
      final id = r['id'];
      if (id == null) continue;

      final top = await _c
          .from('Bid_auction')
          .select('user_id, new_price')
          .eq('auction_id', id)
          .order('new_price', ascending: false)
          .limit(1)
          .maybeSingle();

      final winner = top?['user_id'] as String?;

      await _c.from('Auction_items').update({
        'is_active': false,
        'winner_id': winner,
      }).eq('id', id);
    }
  }

  /// Текущая цена: максимальная [new_price] по ставкам или [start_price] лота.
  Future<int> currentPriceForAuction(
    int auctionId,
    int startPrice,
  ) async {
    final m = await _c
        .from('Bid_auction')
        .select('new_price')
        .eq('auction_id', auctionId)
        .order('new_price', ascending: false)
        .limit(1)
        .maybeSingle();

    if (m == null) return startPrice;
    return (m['new_price'] as num).toInt();
  }

  /// Сделать ставку: вставка в [Bid_auction], +2 мин к [ended_at], [bid_count]+1.
  /// Нельзя ставить на свой лот. После [ended_at] — нельзя.
  Future<String?> placeBid({
    required int auctionId,
  }) async {
    await finalizeExpiredAuctions();

    final user = _c.auth.currentUser;
    if (user == null) return 'Войдите в аккаунт';

    final row = await _c
        .from('Auction_items')
        .select('id, owner_id, start_price, ended_at, is_active, bid_count')
        .eq('id', auctionId)
        .maybeSingle();

    if (row == null) return 'Аукцион не найден';
    if ((row['is_active'] as bool?) != true) return 'Аукцион завершён';
    if (row['owner_id'] == user.id) return 'Нельзя делать ставку на свой лот';

    final end = _parseEnd(row['ended_at']);
    if (end == null) return 'Неверная дата окончания';
    if (DateTime.now().isAfter(end)) return 'Время аукциона вышло';

    final startPrice = (row['start_price'] as num).toInt();
    final current = await currentPriceForAuction(auctionId, startPrice);
    final newPrice = current + kMinBidStep;
    final bidCount = (row['bid_count'] as num?)?.toInt() ?? 0;
    final userTable = await _resolveUserTable();
    if (userTable == null) {
      return 'Таблица пользователей не найдена';
    }
    final meRow = await _c
        .from(userTable)
        .select('scope')
        .eq('id', user.id)
        .maybeSingle();
    final myScope = (meRow?['scope'] as num?)?.toInt() ?? 0;
    if (myScope < newPrice) {
      return 'Недостаточно очков: нужно $newPrice ⭐, у вас $myScope ⭐';
    }

    try {
      await _c.from('Bid_auction').insert({
        'user_id': user.id,
        'auction_id': auctionId,
        'new_price': newPrice,
      });
    } catch (e) {
      debugPrint('placeBid insert error: $e');
      return 'Не удалось сохранить ставку. Проверьте ограничения БД: '
          'для [Bid_auction] нужен UNIQUE (auction_id, new_price), а не только по new_price. '
          'См. supabase/migrations/001_bid_unique.sql';
    }

    final after = await _c
        .from('Auction_items')
        .select('ended_at')
        .eq('id', auctionId)
        .single();
    final endAfter = _parseEnd(after['ended_at']) ?? end;
    final newEnded = endAfter.add(kAuctionSnipeExtension);

    await _c.from('Auction_items').update({
      'ended_at': _toDbTimestamp(newEnded),
      'bid_count': bidCount + 1,
    }).eq('id', auctionId);
    await _c.from(userTable).update({
      'scope': myScope - newPrice,
    }).eq('id', user.id);

    return null;
  }

  String _toDbTimestamp(DateTime t) {
    return t.toIso8601String();
  }

  DateTime? _parseEnd(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveUserTable() async {
    for (final table in _userTableCandidates) {
      try {
        await _c.from(table).select('id').limit(1);
        return table;
      } catch (_) {}
    }
    return null;
  }
}
