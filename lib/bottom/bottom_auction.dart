import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

      // 🔴 LIVE аукционы (активные, ещё не завершённые)
      final liveResponse = await client
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
          .limit(1);

      // ⏳ Ближайшие аукционы (следующие 4)
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

  String _formatPrice(int price) {
    return price.toString().replaceAllMapped(
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('⚠️ $_error', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadAuctions,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAuctions,
      color: const Color(0xFF7C3AED),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 60, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "🔨 Аукцион",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  Text(
                    "Торгуйся и побеждай!",
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),

            // 🔴 LIVE Аукцион
            if (_liveAuction != null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  "🔴 LIVE сейчас",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
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
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      // Верхняя часть с эмодзи/изображением
                      Container(
                        height: 140,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            _liveAuction!['url_item'] != null && _liveAuction!['url_item'].toString().isNotEmpty
                                ? ClipRRect(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                                    child: Image.network(
                                      _liveAuction!['url_item'],
                                      width: double.infinity,
                                      height: 140,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Text("🎮", style: TextStyle(fontSize: 70)),
                                    ),
                                  )
                                : const Text("🎮", style: TextStyle(fontSize: 70)),
                            Positioned(
                              top: 12,
                              left: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.circle, size: 8, color: Colors.white),
                                    SizedBox(width: 6),
                                    Text(
                                      "LIVE",
                                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Нижняя информация
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _liveAuction!['title'] ?? 'Без названия',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            Text(
                              "Продавец: @${_liveAuction!['User']?['login'] ?? 'Unknown'} • ⭐ 4.9",
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                            const SizedBox(height: 16),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _StatItem(
                                  label: "Текущая",
                                  value: "₽ ${_formatPrice(_liveAuction!['start_price'] ?? 0)}",
                                  color: const Color(0xFF34D399),
                                ),
                                _StatItem(
                                  label: "Ставок",
                                  value: "${_liveAuction!['bid_count'] ?? 0}",
                                ),
                                _StatItem(
                                  label: "До конца",
                                  value: _formatTimeRemaining(_liveAuction!['ended_at'] ?? ''),
                                  color: Colors.red,
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  // TODO: Открыть страницу ставок
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Функция ставок в разработке')),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Text(
                                  "⚡ Сделать ставку — ₽ ${_formatPrice((_liveAuction!['start_price'] ?? 0) + 50)}",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.gavel, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        "Сейчас нет активных аукционов",
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // ⏳ Ближайшие аукционы
            if (_upcomingAuctions.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  "⏳ Ближайшие аукционы",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              ..._upcomingAuctions.map((auction) => _AuctionListItem(
                title: auction['title'] ?? 'Без названия',
                meta: "Steam • ${auction['bid_count'] ?? 0} ставок • @${auction['User']?['login'] ?? 'Unknown'}",
                price: "${auction['start_price'] ?? 0}",
                time: _formatTimeRemaining(auction['ended_at'] ?? ''),
                imageUrl: auction['url_item'],
              )),
            ] else ...[
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: Text(
                    "Нет ближайших аукционов",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ====================== Вспомогательные виджеты ======================

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatItem({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.white,
          ),
        ),
      ],
    );
  }
}

class _AuctionListItem extends StatelessWidget {
  final String title;
  final String meta;
  final String price;
  final String time;
  final String? imageUrl;

  const _AuctionListItem({
    super.key,
    required this.title,
    required this.meta,
    required this.price,
    required this.time,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1430),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
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
                      errorBuilder: (_, __, ___) => const Center(child: Text("🎮", style: TextStyle(fontSize: 24))),
                    ),
                  )
                : const Center(child: Text("🎮", style: TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                Text(meta, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("₽ $price", style: const TextStyle(color: Color(0xFFA78BFA), fontWeight: FontWeight.bold)),
              Text("⏰ $time", style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}