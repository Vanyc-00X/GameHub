import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuctionsListPage extends StatefulWidget {
  const AuctionsListPage({super.key});

  @override
  State<AuctionsListPage> createState() => _AuctionsListPageState();
}

class _AuctionsListPageState extends State<AuctionsListPage> 
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _myAuctionsActive = [];
  List<Map<String, dynamic>> _myAuctionsCompleted = [];
  List<Map<String, dynamic>> _myBids = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    // 🔧 ИСПРАВЛЕНО: длина 3, потому что 3 вкладки
    _tabController = TabController(length: 3, vsync: this);
    _loadAuctions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAuctions() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _error = 'Пользователь не авторизован';
          _isLoading = false;
        });
        return;
      }

      // 1️⃣ МОИ аукционы (активные)
      final myActive = await Supabase.instance.client
          .from('Auction_items')
          .select('id, title, url_item, start_price, ended_at, bid_count')
          .eq('owner_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      // 2️⃣ МОИ аукционы (завершённые)
      final myCompleted = await Supabase.instance.client
          .from('Auction_items')
          .select('id, title, url_item, start_price, ended_at, bid_count, winner_id')
          .eq('owner_id', userId)
          .eq('is_active', false)
          .order('ended_at', ascending: false);

      // 3️⃣ Аукционы, где я делал СТАВКИ
      final bidsResponse = await Supabase.instance.client
          .from('Bid_auction')
          .select('''
            id,
            new_price,
            created_at,
            Auction_items!bid_auction_auction_id_fkey (
              id,
              title,
              url_item,
              start_price,
              ended_at,
              bid_count,
              is_active,
              owner_id,
              User!auction_items_owner_id_fkey (
                login,
                username
              )
            )
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);

      // Извлекаем уникальные аукционы из ставок
      final Set<int> seenAuctionIds = {};
      final List<Map<String, dynamic>> myBidsList = [];
      
      for (var bid in bidsResponse) {
        final auction = bid['Auction_items'] as Map<String, dynamic>?;
        if (auction != null && !seenAuctionIds.contains(auction['id'])) {
          seenAuctionIds.add(auction['id']);
          myBidsList.add({
            ...auction,
            'my_bid_price': bid['new_price'],
            'bid_time': bid['created_at'],
          });
        }
      }

      if (mounted) {
        setState(() {
          _myAuctionsActive = myActive;
          _myAuctionsCompleted = myCompleted;
          _myBids = myBidsList;
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

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}.${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  String _getTimeRemaining(String endedAt) {
    try {
      final end = DateTime.parse(endedAt);
      final diff = end.difference(DateTime.now());
      
      if (diff.isNegative) return 'Завершён';
      
      final hours = diff.inHours;
      final minutes = diff.inMinutes.remainder(60);
      
      if (hours > 0) {
        return '$hours ч ${minutes}м';
      }
      return '$minutes мин';
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Мои аукционы',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF7C3AED),
          labelColor: const Color(0xFF7C3AED),
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          // 🔧 3 вкладки
          tabs: const [
            Tab(text: '📤 Мои'),
            Tab(text: '✅ Завершённые'),
            Tab(text: '💰 Мои ставки'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
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
                )
              : TabBarView(
                  controller: _tabController,
                  // 🔧 3 детей, соответствует 3 вкладкам
                  children: [
                    _buildAuctionList(_myAuctionsActive, 'Нет активных аукционов', showOwner: false),
                    _buildAuctionList(_myAuctionsCompleted, 'Нет завершённых аукционов', showOwner: false, showWinner: true),
                    _buildBidsList(_myBids, 'Вы пока не делали ставок'),
                  ],
                ),
    );
  }

  Widget _buildAuctionList(List<Map<String, dynamic>> auctions, String emptyMessage, {bool showOwner = false, bool showWinner = false}) {
    if (auctions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gavel, size: 80, color: Colors.grey.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(emptyMessage, style: const TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAuctions,
      color: const Color(0xFF7C3AED),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: auctions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final auction = auctions[index];
          return _buildAuctionCard(auction, showWinner: showWinner);
        },
      ),
    );
  }

  Widget _buildBidsList(List<Map<String, dynamic>> auctions, String emptyMessage) {
    if (auctions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.money, size: 80, color: Colors.grey.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(emptyMessage, style: const TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Найдите аукционы и делайте ставки!', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAuctions,
      color: const Color(0xFF7C3AED),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: auctions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final auction = auctions[index];
          return _buildBidCard(auction);
        },
      ),
    );
  }

  Widget _buildAuctionCard(Map<String, dynamic> auction, {bool showWinner = false}) {
    final title = auction['title'] ?? 'Без названия';
    final imageUrl = auction['url_item'] as String?;
    final startPrice = auction['start_price'] as int? ?? 0;
    final bidCount = auction['bid_count'] as int? ?? 0;
    final endedAt = auction['ended_at'] as String?;
    final winnerId = auction['winner_id'];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: imageUrl != null && imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    height: 120,
                    width: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 120,
                      width: 120,
                      color: const Color(0xFF2A2A3E),
                      child: const Icon(Icons.image, size: 40, color: Colors.grey),
                    ),
                  )
                : Container(
                    height: 120,
                    width: 120,
                    color: const Color(0xFF2A2A3E),
                    child: const Icon(Icons.image, size: 40, color: Colors.grey),
                  ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildInfoChip('💰 ${_formatPrice(startPrice)} ₽'),
                      _buildInfoChip('🔨 $bidCount ${_pluralize(bidCount, "ставка", "ставки", "ставок")}'),
                    ],
                  ),
                  if (endedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '⏰ ${_getTimeRemaining(endedAt)}',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ],
                  if (showWinner && winnerId != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '✅ Продано',
                        style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBidCard(Map<String, dynamic> auction) {
    final title = auction['title'] ?? 'Без названия';
    final imageUrl = auction['url_item'] as String?;
    final startPrice = auction['start_price'] as int? ?? 0;
    final myBidPrice = auction['my_bid_price'] as int? ?? 0;
    final bidTime = auction['bid_time'] as String?;
    final isActive = auction['is_active'] as bool? ?? false;
    final ownerLogin = (auction['User'] as Map<String, dynamic>?)?['login'] ?? 'Unknown';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? const Color(0xFF7C3AED).withOpacity(0.5) : Colors.grey.withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: imageUrl != null && imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    height: 120,
                    width: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 120,
                      width: 120,
                      color: const Color(0xFF2A2A3E),
                      child: const Icon(Icons.image, size: 40, color: Colors.grey),
                    ),
                  )
                : Container(
                    height: 120,
                    width: 120,
                    color: const Color(0xFF2A2A3E),
                    child: const Icon(Icons.image, size: 40, color: Colors.grey),
                  ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Завершён',
                            style: TextStyle(color: Colors.grey, fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Продавец: @$ownerLogin',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildInfoChip('💰 ${_formatPrice(startPrice)} ₽', color: Colors.grey),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFF34D399).withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Ваша: ${_formatPrice(myBidPrice)} ₽',
                          style: TextStyle(
                            color: isActive ? const Color(0xFF34D399) : Colors.grey,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (bidTime != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Ставка: ${_formatDate(bidTime)}',
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String text, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? const Color(0xFF7C3AED)).withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color ?? const Color(0xFF7C3AED),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _pluralize(int num, String one, String two, String five) {
    final mod = num % 10;
    if (num % 100 >= 11 && num % 100 <= 14) return five;
    if (mod == 1) return one;
    if (mod >= 2 && mod <= 4) return two;
    return five;
  }
}