import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'mini_page/reate_auction_page.dart';

class BottomAuction extends StatefulWidget {
  const BottomAuction({super.key});

  @override
  State<BottomAuction> createState() => _BottomAuctionState();
}

class _BottomAuctionState extends State<BottomAuction> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _liveAuction;
  List<Map<String, dynamic>> _upcomingAuctions = [];

  @override
  void initState() {
    super.initState();
    _loadAuctions();
  }

  Future<void> _loadAuctions() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final client = Supabase.instance.client;
      final now = DateTime.now().toIso8601String();

      // 🔴 LIVE аукционы
      final liveResponse = await client
          .from('Auction_items') // ← Здесь было 'auction_items' (маленькая 'a')
          .select('''
      id,
      title,
      url_item,
      start_price,
      bid_count,
      ended_at,
      is_active,
      owner_id,
      User!auction_items_owner_id_fkey (
        username,
        login
      )
    ''')
          .eq('is_active', true)
          .gt('ended_at', now)
          .order('ended_at', ascending: true)
          .limit(1);

      // ⏳ Ближайшие аукционы
      final upcomingResponse = await client
          .from('Auction_items')
          .select('''
            id,
            title,
            url_item,
            start_price,
            bid_count,
            ended_at,
            is_active,
            owner_id,
            User!auction_items_owner_id_fkey (
              username,
              login
            )
          ''')
          .eq('is_active', true)
          .gt('ended_at', now)
          .order('ended_at', ascending: true)
          .limit(4);

      if (mounted) {
        setState(() {
          _liveAuction = liveResponse.isNotEmpty ? liveResponse.first : null;
          _upcomingAuctions = upcomingResponse;
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

      if (diff.isNegative) {
        return 'Завершён';
      }

      final hours = diff.inHours;
      final minutes = diff.inMinutes.remainder(60);
      final seconds = diff.inSeconds.remainder(60);

      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadAuctions,
        color: const Color(0xFF7C3AED),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🎨 Заголовок с градиентом и кнопкой
              Container(
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "🔨 Аукцион игр",
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Покупай и продавай игры за очки",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 🔨 Кнопка создания аукциона
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.add_circle,
                          color: Colors.white,
                          size: 32,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CreateAuctionPage(),
                            ),
                          ).then((_) => _loadAuctions());
                        },
                        tooltip: 'Создать аукцион',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '⚠️ $_error',
                        style: const TextStyle(color: Colors.red),
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
                )
              else
                Column(
                  children: [
                    // 🔴 LIVE Аукцион
                    if (_liveAuction != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    size: 8,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    "LIVE",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              "Идёт прямо сейчас",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2A1212), Color(0xFF1E0A1E)],
                            ),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.3),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Container(
                                height: 160,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.4),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(22),
                                  ),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    _liveAuction!['url_item'] != null &&
                                            _liveAuction!['url_item']
                                                .toString()
                                                .isNotEmpty
                                        ? ClipRRect(
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(22),
                                                ),
                                            child: Image.network(
                                              _liveAuction!['url_item'],
                                              width: double.infinity,
                                              height: 160,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  const Text(
                                                    "🎮",
                                                    style: TextStyle(
                                                      fontSize: 80,
                                                    ),
                                                  ),
                                            ),
                                          )
                                        : const Text(
                                            "🎮",
                                            style: TextStyle(fontSize: 80),
                                          ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _liveAuction!['title'] ?? 'Без названия',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      "Продавец: @${_liveAuction!['User']?['login'] ?? 'Unknown'}",
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (_liveAuction!['steam_url'] != null) ...[
                                      const SizedBox(height: 8),
                                      InkWell(
                                        onTap: () {
                                          // TODO: Открыть Steam URL
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Открытие Steam...',
                                              ),
                                            ),
                                          );
                                        },
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.link,
                                              size: 16,
                                              color: Color(0xFF3B82F6),
                                            ),
                                            const SizedBox(width: 4),
                                            const Text(
                                              'Страница в Steam',
                                              style: TextStyle(
                                                color: Color(0xFF3B82F6),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceAround,
                                        children: [
                                          _StatItem(
                                            label: "Текущая ставка",
                                            value:
                                                "${_formatPoints(_liveAuction!['start_price'] ?? 0)} ⭐",
                                            color: const Color(0xFF34D399),
                                            icon: Icons.star,
                                          ),
                                          _StatItem(
                                            label: "Ставок",
                                            value:
                                                "${_liveAuction!['bid_count'] ?? 0}",
                                            icon: Icons.trending_up,
                                          ),
                                          _StatItem(
                                            label: "До конца",
                                            value: _formatTimeRemaining(
                                              _liveAuction!['ended_at'] ?? '',
                                            ),
                                            color: Colors.red,
                                            icon: Icons.timer,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: () {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Функция ставок в разработке',
                                              ),
                                            ),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          "⚡ Сделать ставку — ${_formatPoints((_liveAuction!['start_price'] ?? 0) + 50)} ⭐",
                                          style: const TextStyle(
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
                        ),
                      ),
                    ] else ...[
                      Container(
                        margin: const EdgeInsets.all(20),
                        padding: const EdgeInsets.all(40),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.gavel,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              "Сейчас нет активных аукционов",
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Будь первым — создай аукцион!",
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const CreateAuctionPage(),
                                  ),
                                ).then((_) => _loadAuctions());
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Создать аукцион'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7C3AED),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ⏳ Ближайшие аукционы
                    if (_upcomingAuctions.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          "⏳ Ближайшие аукционы",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ..._upcomingAuctions.map(
                        (auction) => _AuctionListItem(
                          title: auction['title'] ?? 'Без названия',
                          meta:
                              "${auction['bid_count'] ?? 0} ставок • @${auction['User']?['login'] ?? 'Unknown'}",
                          points:
                              "${_formatPoints(auction['start_price'] ?? 0)} ⭐",
                          time: _formatTimeRemaining(auction['ended_at'] ?? ''),
                          imageUrl: auction['url_item'],
                          steamUrl: auction['steam_url'],
                        ),
                      ),
                    ],

                    const SizedBox(height: 100),
                  ],
                ),
            ],
          ),
        ),
      ),
      // 🔨 FAB кнопка создания аукциона
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
}

// ====================== Вспомогательные виджеты ======================

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final IconData icon;

  const _StatItem({
    super.key,
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
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.white,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}

class _AuctionListItem extends StatelessWidget {
  final String title;
  final String meta;
  final String points;
  final String time;
  final String? imageUrl;
  final String? steamUrl;

  const _AuctionListItem({
    super.key,
    required this.title,
    required this.meta,
    required this.points,
    required this.time,
    this.imageUrl,
    this.steamUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1430), Color(0xFF2D1B69)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: const Color(0xFF2D1B69),
            ),
            child: imageUrl != null && imageUrl!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text("🎮", style: TextStyle(fontSize: 24)),
                      ),
                    ),
                  )
                : const Center(
                    child: Text("🎮", style: TextStyle(fontSize: 24)),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  meta,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                if (steamUrl != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.link,
                        size: 12,
                        color: Color(0xFF3B82F6),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Steam',
                        style: TextStyle(
                          color: Color(0xFF3B82F6),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                points,
                style: const TextStyle(
                  color: Color(0xFFF59E0B),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                "⏰ $time",
                style: const TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
