import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/auction_service.dart';
import '../database/digiseller_api.dart';
import '../database/post_content_codec.dart';
import '../widgets/notification_bell.dart';
import 'mini_page/user_profile_page.dart';
import 'package:url_launcher/url_launcher.dart';

class BottomHome extends StatefulWidget {
  const BottomHome({super.key});

  @override
  State<BottomHome> createState() => _BottomHomeState();
}

class _BottomHomeState extends State<BottomHome> {
  final SupabaseClient supabase = Supabase.instance.client;
  final DigisellerApiService _api = DigisellerApiService();
  static const List<String> _userTables = ['User', 'users', 'user', '"User"'];
  
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<dynamic> _searchResults = [];
  bool _isLoadingResults = false;

  List<Map<String, dynamic>> _liveAuctions = [];
  List<DigisellerProduct> _discountedProducts = [];
  Map<String, dynamic>? _bestPost;
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  // Загрузка данных для главной страницы
  Future<void> _loadInitialData() async {
    setState(() => _isLoadingData = true);
    try {
      await AuctionService.instance.finalizeExpiredAuctions();

      // 1. Загрузка активных аукционов
      final auctionData = await supabase
          .from('Auction_items')
          .select('id, title, start_price, ended_at, url_item, bid_count')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(5);

      // 2. Загрузка товаров из Digiseller
      final products = await _api.fetchProducts();

      // 3. Загрузка лучшего поста дня (по количеству лайков)
      final postData = await supabase
          .from('Post')
          .select('id, content, like, user:User!user_id(username, avatar)')
          .order('like', ascending: false)
          .limit(1)
          .maybeSingle();

      setState(() {
        _liveAuctions = List<Map<String, dynamic>>.from(auctionData);
        _discountedProducts = products.take(5).toList();
        _bestPost = postData;
        _isLoadingData = false;
      });
    } catch (e) {
      debugPrint('Ошибка при загрузке данных: $e');
      setState(() => _isLoadingData = false);
    }
  }

  // Метод для перехода к покупке товара
  Future<void> _handlePurchase(String productId, [String? directUrl]) async {
    final String urlString = directUrl ?? 
        'https://www.digiseller.market/asp/curr_select.asp?id_goods=$productId';
    final Uri url = Uri.parse(urlString);
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // Глобальный поиск
  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoadingResults = true;
    });

    try {
      // Поиск по пользователям (логин и имя)
      List<dynamic> userResults = const [];
      for (final table in _userTables) {
        try {
          final rows = await supabase
              .from(table)
              .select('id, username, avatar, login')
              .or('username.ilike.%$query%,login.ilike.%$query%')
              .limit(8);
          userResults = rows;
          break;
        } catch (_) {}
      }

      // Поиск по постам
      final postResults = await supabase
          .from('Post')
          .select('content, user:User!user_id(username)')
          .ilike('content', '%$query%')
          .limit(3);

      // Поиск по каналам
      final channelResults = await supabase
          .from('Chat')
          .select('namechat')
          .ilike('namechat', '%$query%')
          .limit(3);

      // Поиск по товарам в API
      final allProducts = await _api.fetchProducts();
      final productResults = allProducts
          .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
          .take(5)
          .toList();

      setState(() {
        _searchResults = [
          ...userResults.map((e) => {...e, 'type': 'user'}),
          ...postResults.map((e) => {...e, 'type': 'post'}),
          ...channelResults.map((e) => {...e, 'type': 'channel'}),
          ...productResults.map((e) => {
            'name': e.name, 
            'id': e.id, 
            'type': 'product', 
            'price': e.price,
            'buy_url': e.buyUrl
          }),
        ];
        _isLoadingResults = false;
      });
    } catch (e) {
      debugPrint('Ошибка поиска: $e');
      setState(() => _isLoadingResults = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _loadInitialData,
        color: const Color(0xFF7C3AED),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              _buildSearchBar(),
              if (_isSearching) _buildSearchResults() else _buildMainContent(),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        if (_bestPost != null) ...[
          _buildSectionTitle('🔥 Лучший пост дня'),
          _buildBestPostCard(),
        ],
        const SizedBox(height: 28),
        _buildSectionHeader('⚡ Активные аукционы', () {}),
        _buildAuctionsList(),
        const SizedBox(height: 32),
        _buildSectionHeader('🏷️ Рекомендуемые товары', () {}),
        _buildProductsList(),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 60, 12, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Добро пожаловать 👋',
                    style: TextStyle(color: Color(0xFF8888AA), fontSize: 15)),
                Text('GameHub',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'logo.png',
              width: 32,
              height: 32,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          const NotificationBell(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _performSearch,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Поиск товаров, постов, юзеров...',
            hintStyle: const TextStyle(color: Colors.grey, fontSize: 15),
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
            suffixIcon: _isSearching 
              ? IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey), 
                  onPressed: () {
                    _searchController.clear();
                    _performSearch('');
                  }) 
              : null,
          ),
        ),
      ),
    );
  }

  Widget _buildBestPostCard() {
    final user = _bestPost!['user'];
    final likes = _bestPost!['like'] ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: user['avatar'] != null ? NetworkImage(user['avatar']) : null,
                backgroundColor: Colors.white10,
                child: user['avatar'] == null ? const Icon(Icons.person, size: 18, color: Colors.white) : null,
              ),
              const SizedBox(width: 12),
              Text(user['username'] ?? 'User', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const Spacer(),
              const Icon(Icons.star, color: Colors.amber, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            decodePostContent(_bestPost!['content'] as String? ?? '').text,
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.favorite, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      likes.toString(),
                      style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAuctionsList() {
    if (_isLoadingData) return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
    if (_liveAuctions.isEmpty) return const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Нет активных аукционов', style: TextStyle(color: Colors.grey)));

    return SizedBox(
      height: 210,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _liveAuctions.length,
        itemBuilder: (context, index) {
          final a = _liveAuctions[index];
          return _AuctionCard(
            title: a['title'] ?? 'Лот',
            price: a['start_price'].toString(),
            bids: a['bid_count'].toString(),
            time: 'LIVE',
            emoji: '🎮',
          );
        },
      ),
    );
  }

  Widget _buildProductsList() {
    if (_isLoadingData) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: _discountedProducts.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => _handlePurchase(p.id, p.buyUrl), // Переход к покупке
            borderRadius: BorderRadius.circular(20),
            child: _DiscountCard(
              emoji: '🎁',
              title: p.name,
              desc: 'Моментальная доставка',
              oldPrice: (double.parse(p.price) * 1.2).toInt().toString(),
              newPrice: p.price,
              discount: '-20%',
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isLoadingResults) return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
    if (_searchResults.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Ничего не найдено', style: TextStyle(color: Colors.white))));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        IconData iconData = Icons.search;
        String title = '';
        String sub = item['type'];

        if (item['type'] == 'user') {
          iconData = Icons.person;
          final u = item['username'] as String? ?? '';
          final l = item['login'] as String? ?? '';
          title = l.isNotEmpty ? '@$l' : u;
        } else if (item['type'] == 'product') {
          iconData = Icons.shopping_cart;
          title = item['name'];
          sub = '${item['price']} ₽';
        } else if (item['type'] == 'post') {
          iconData = Icons.article;
          title = item['content'];
        } else {
          iconData = Icons.chat_bubble;
          title = item['namechat'];
        }

        return ListTile(
          leading: Icon(iconData, color: Colors.white54),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
          subtitle: Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          onTap: () {
            if (item['type'] == 'product') {
              _handlePurchase(item['id'], item['buy_url']);
            } else if (item['type'] == 'user') {
              final uid = item['id'] as String?;
              if (uid != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfilePage(userId: uid),
                  ),
                );
              }
            }
          },
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback onSeeAll) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          TextButton(onPressed: onSeeAll, child: const Text('Все', style: TextStyle(color: Color(0xFF7C3AED)))),
        ],
      ),
    );
  }
}

// Вспомогательные компоненты (Аукционы и Товары)

class _AuctionCard extends StatelessWidget {
  final String title, price, bids, time, emoji;
  const _AuctionCard({required this.title, required this.price, required this.bids, required this.time, required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 32)),
          const Spacer(),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('$bids ставок', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$price ₽', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
              Text(time, style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          )
        ],
      ),
    );
  }
}

class _DiscountCard extends StatelessWidget {
  final String emoji, title, desc, oldPrice, newPrice, discount;
  const _DiscountCard({required this.emoji, required this.title, required this.desc, required this.oldPrice, required this.newPrice, required this.discount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
   
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('$newPrice ₽', style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Text('$oldPrice ₽', style: const TextStyle(color: Colors.white24, fontSize: 11, decoration: TextDecoration.lineThrough)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(discount, style: const TextStyle(color: Color(0xFF34D399), fontSize: 12, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}