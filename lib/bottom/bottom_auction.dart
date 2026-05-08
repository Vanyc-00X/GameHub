import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/auction_service.dart';
import '../database/services/rating_service.dart';
import 'mini_page/reate_auction_page.dart';
import 'mini_page/rate_user_sheet.dart';

/// Аукционы: активные лоты со ставкой (+2 мин) и завершённые с оценкой контрагента.
class BottomAuction extends StatefulWidget {
  const BottomAuction({super.key});

  @override
  State<BottomAuction> createState() => _BottomAuctionState();
}

class _BottomAuctionState extends State<BottomAuction>
    with SingleTickerProviderStateMixin {
  static const List<String> _userTables = ['User', 'users', 'user', '"User"'];
  late final TabController _tab;

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _auctions = [];
  List<Map<String, dynamic>> _finished = [];
  final Map<int, int> _maxBidByAuction = {};
  final Set<String> _ratedKeys = {};
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadAuctions();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final hasExpired = _auctions.any((a) {
        final end = DateTime.tryParse('${a['ended_at']}');
        return end != null && DateTime.now().isAfter(end);
      });
      if (hasExpired) {
        _loadAuctions();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadAuctions() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final client = Supabase.instance.client;
      await AuctionService.instance.finalizeExpiredAuctions();

      final now = DateTime.now().toIso8601String();

      final res = await client
          .from('Auction_items')
          .select(
            'id, title, url_item, start_price, bid_count, ended_at, is_active, owner_id',
          )
          .eq('is_active', true)
          .gt('ended_at', now)
          .order('ended_at', ascending: true);

      final list = List<Map<String, dynamic>>.from(res);
      final activeUsers = await _loadUsersByIds(
        list
            .map((e) => e['owner_id']?.toString())
            .whereType<String>()
            .where((e) => e.isNotEmpty)
            .toSet(),
      );
      for (final row in list) {
        final ownerId = row['owner_id']?.toString();
        row['User'] = activeUsers[ownerId] ?? const <String, dynamic>{};
      }
      final ids = list.map((e) => (e['id'] as num).toInt()).toList();

      final Map<int, int> maxBids = {};
      if (ids.isNotEmpty) {
        final bids = await client
            .from('Bid_auction')
            .select('auction_id, new_price');
        final idSet = ids.toSet();
        for (final b in List<Map<String, dynamic>>.from(bids)) {
          final aid = (b['auction_id'] as num).toInt();
          if (!idSet.contains(aid)) continue;
          final p = (b['new_price'] as num).toInt();
          if ((maxBids[aid] ?? 0) < p) maxBids[aid] = p;
        }
      }

      final me = client.auth.currentUser?.id;
      List<Map<String, dynamic>> finished = [];
      if (me != null) {
        final finRes = await client
            .from('Auction_items')
            .select(
              'id, title, url_item, start_price, ended_at, is_active, owner_id, winner_id',
            )
            .eq('is_active', false)
            .not('winner_id', 'is', null)
            .or('owner_id.eq.$me,winner_id.eq.$me')
            .order('ended_at', ascending: false)
            .limit(30);
        finished = List<Map<String, dynamic>>.from(finRes);
        final finishedUsers = await _loadUsersByIds(
          finished
              .expand(
                (e) => [e['owner_id']?.toString(), e['winner_id']?.toString()],
              )
              .whereType<String>()
              .where((e) => e.isNotEmpty)
              .toSet(),
        );
        for (final row in finished) {
          final ownerId = row['owner_id']?.toString();
          final winnerId = row['winner_id']?.toString();
          row['User'] = finishedUsers[ownerId] ?? const <String, dynamic>{};
          row['Winner'] = finishedUsers[winnerId] ?? const <String, dynamic>{};
        }

        List<Map<String, dynamic>> existingRows = const [];
        try {
          final existing = await client
              .from('User_rating')
              .select('auction_id, role')
              .eq('rater_id', me);
          existingRows = List<Map<String, dynamic>>.from(existing as List);
        } catch (e) {
          // Если рейтинг-таблица не накатана в окружении, аукционы всё равно
          // должны загружаться без кнопки повторной оценки.
          debugPrint('User_rating is unavailable, skip rated state: $e');
          existingRows = const [];
        }
        _ratedKeys
          ..clear()
          ..addAll(existingRows.map((r) => '${r['auction_id']}:${r['role']}'));
      }

      if (mounted) {
        setState(() {
          _auctions = list;
          _finished = finished;
          _maxBidByAuction
            ..clear()
            ..addAll(maxBids);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Ошибка загрузки: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<Map<String, Map<String, dynamic>>> _loadUsersByIds(
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final client = Supabase.instance.client;
    Object? lastError;
    for (final table in _userTables) {
      try {
        final rows = await client
            .from(table)
            .select('id, username, login')
            .inFilter('id', ids.toList());
        final list = List<Map<String, dynamic>>.from(rows as List);
        return {
          for (final row in list)
            row['id'].toString(): {
              'id': row['id'],
              'username': row['username'],
              'login': row['login'],
            },
        };
      } catch (e) {
        lastError = e;
      }
    }
    debugPrint('Failed to load users for auctions: $lastError');
    return const {};
  }

  int _currentPrice(int auctionId, int startPrice) {
    return _maxBidByAuction[auctionId] ?? startPrice;
  }

  String _formatPoints(int points) {
    return points.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]} ',
    );
  }

  String _formatTimeRemaining(String endedAt) {
    try {
      final end = DateTime.parse(endedAt);
      final diff = end.difference(DateTime.now());

      if (diff.isNegative) return 'Завершён';

      final hours = diff.inHours;
      final minutes = diff.inMinutes.remainder(60);
      final seconds = diff.inSeconds.remainder(60);

      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    } catch (_) {
      return '—';
    }
  }

  Future<void> _onBid(
    int auctionId,
    int startPrice, {
    required String title,
  }) async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    final price = _currentPrice(auctionId, startPrice);
    final next = price + 50;

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(
          'Ставка: $title',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          'Следующая цена: ${_formatPoints(next)} ⭐\n'
          'К аукциону прибавится 2 минуты.',
          style: const TextStyle(color: Colors.white70, height: 1.3),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
            ),
            child: const Text('Поставить'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (me == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Войдите в аккаунт')));
      }
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
        ),
      );
    }

    final err = await AuctionService.instance.placeBid(auctionId: auctionId);
    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    if (err != null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(err)));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Ставка принята, +2 мин к аукциону'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadAuctions();
    }
  }

  Future<void> _openRate(Map<String, dynamic> a) async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return;
    final id = (a['id'] as num).toInt();
    final ownerId = a['owner_id']?.toString();
    final winnerId = a['winner_id']?.toString();
    if (ownerId == null || winnerId == null) return;

    final isOwner = me == ownerId;
    final isWinner = me == winnerId;
    if (!isOwner && !isWinner) return;

    final role = isOwner ? RatingRole.buyer : RatingRole.seller;
    final target = isOwner ? winnerId : ownerId;

    final u = (isOwner ? a['Winner'] : a['User']) as Map<String, dynamic>?;
    final label = u != null
        ? '${u['username'] ?? ''} · @${u['login'] ?? ''}'
        : 'Пользователь';

    final done = await RateUserSheet.show(
      context,
      targetId: target,
      auctionId: id,
      role: role,
      targetLabel: label,
    );
    if (done == true) {
      await _loadAuctions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadAuctions,
        color: const Color(0xFF7C3AED),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header(context)),
            SliverToBoxAdapter(
              child: Container(
                color: const Color(0xFF0F0F1A),
                child: TabBar(
                  controller: _tab,
                  onTap: (_) => setState(() {}),
                  indicatorColor: const Color(0xFF7C3AED),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey,
                  tabs: const [
                    Tab(text: 'Активные'),
                    Tab(text: 'Завершённые'),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: const SizedBox(height: 12)),
            if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(child: _errorBlock())
            else if (_tab.index == 0)
              _activeSliver()
            else
              _finishedSliver(),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateAuctionPage()),
          ).then((_) => _loadAuctions());
        },
        backgroundColor: const Color(0xFF7C3AED),
        icon: const Icon(Icons.gavel),
        label: const Text('Аукцион'),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔨 Аукцион игр',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Создай лот или сделай ставку (+2 мин к таймеру)',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBlock() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '⚠️ $_error',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadAuctions,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
            ),
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }

  Widget _activeSliver() {
    if (_auctions.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              const Icon(Icons.gavel, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Сейчас нет активных аукционов',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Создай аукцион — его увидят все',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, i) {
        final a = _auctions[i];
        final id = (a['id'] as num).toInt();
        final start = (a['start_price'] as num).toInt();
        final cur = _currentPrice(id, start);
        final title = a['title'] as String? ?? 'Лот';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: _AuctionCardDb(
            title: title,
            seller:
                '@${(a['User'] as Map<String, dynamic>?)?['login'] ?? 'unknown'}',
            imageUrl: a['url_item'] as String? ?? '',
            bidCount: (a['bid_count'] as num?)?.toInt() ?? 0,
            timeLeft: _formatTimeRemaining('${a['ended_at']}'),
            currentPoints: _formatPoints(cur),
            onBid: () => _onBid(id, start, title: title),
          ),
        );
      }, childCount: _auctions.length),
    );
  }

  Widget _finishedSliver() {
    if (_finished.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(
            child: Text(
              'Завершённых сделок пока нет',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    final me = Supabase.instance.client.auth.currentUser?.id;

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, i) {
        final a = _finished[i];
        final id = (a['id'] as num).toInt();
        final ownerId = a['owner_id']?.toString();
        final winnerId = a['winner_id']?.toString();
        final isOwner = ownerId == me;
        final role = isOwner ? RatingRole.buyer : RatingRole.seller;
        final ratedKey = '$id:${role.dbValue}';
        final alreadyRated = _ratedKeys.contains(ratedKey);

        final u = (isOwner ? a['Winner'] : a['User']) as Map<String, dynamic>?;
        final target = u != null ? '@${u['login'] ?? 'unknown'}' : '@unknown';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: _FinishedCard(
            title: a['title'] as String? ?? 'Лот',
            imageUrl: a['url_item'] as String? ?? '',
            roleLabel: isOwner ? 'Вы продавец' : 'Вы покупатель',
            counterparty: target,
            onRate: (ownerId == null || winnerId == null || alreadyRated)
                ? null
                : () => _openRate(a),
            rateDone: alreadyRated,
          ),
        );
      }, childCount: _finished.length),
    );
  }
}

class _AuctionCardDb extends StatelessWidget {
  final String title;
  final String seller;
  final String imageUrl;
  final int bidCount;
  final String timeLeft;
  final String currentPoints;
  final VoidCallback onBid;

  const _AuctionCardDb({
    required this.title,
    required this.seller,
    required this.imageUrl,
    required this.bidCount,
    required this.timeLeft,
    required this.currentPoints,
    required this.onBid,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1212), Color(0xFF1E0A1E)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: SizedBox(
              height: 140,
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text('🎮', style: TextStyle(fontSize: 64)),
                      ),
                    )
                  : const Center(
                      child: Text('🎮', style: TextStyle(fontSize: 64)),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Продавец: $seller',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _MiniStat(
                      label: 'Текущая',
                      value: '$currentPoints ⭐',
                      color: const Color(0xFF34D399),
                      icon: Icons.star,
                    ),
                    _MiniStat(
                      label: 'Ставок',
                      value: '$bidCount',
                      icon: Icons.trending_up,
                    ),
                    _MiniStat(
                      label: 'До конца',
                      value: timeLeft,
                      color: Colors.red,
                      icon: Icons.timer,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onBid,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Сделать ставку',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FinishedCard extends StatelessWidget {
  final String title;
  final String imageUrl;
  final String roleLabel;
  final String counterparty;
  final VoidCallback? onRate;
  final bool rateDone;

  const _FinishedCard({
    required this.title,
    required this.imageUrl,
    required this.roleLabel,
    required this.counterparty,
    required this.onRate,
    required this.rateDone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SizedBox(
              height: 120,
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text('🎮', style: TextStyle(fontSize: 48)),
                      ),
                    )
                  : const Center(
                      child: Text('🎮', style: TextStyle(fontSize: 48)),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$roleLabel · контрагент $counterparty',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onRate,
                    icon: Icon(
                      rateDone ? Icons.check_circle : Icons.star_border_rounded,
                    ),
                    label: Text(
                      rateDone ? 'Оценка отправлена' : 'Оценить контрагента',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: rateDone
                          ? Colors.white12
                          : const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final IconData icon;

  const _MiniStat({
    required this.label,
    required this.value,
    this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color ?? Colors.grey),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.white,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
