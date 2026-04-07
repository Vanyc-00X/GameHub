import 'package:flutter/material.dart';

class BottomHome extends StatelessWidget {
  const BottomHome({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 60, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Добро пожаловать 👋", style: TextStyle(color: Color(0xFF8888AA), fontSize: 15)),
                Text("GameVault", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search, color: Colors.grey),
                  SizedBox(width: 12),
                  Text("Поиск игр, ключей, каналов...", style: TextStyle(color: Colors.grey, fontSize: 15)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Stories
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text("Быстрый доступ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: const [
                _StoryItem(emoji: "🎮", label: "Новинки", isHot: true),
                _StoryItem(emoji: "🔑", label: "Ключи"),
                _StoryItem(emoji: "💰", label: "Скидки", isHot: true),
                _StoryItem(emoji: "🏆", label: "Топ"),
                _StoryItem(emoji: "🎯", label: "Подборки"),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Сгорающие аукционы
          _SectionHeader(title: "⚡ Сгорающие аукционы", onSeeAll: () {}),
          SizedBox(
            height: 210,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: const [
                _AuctionCard(title: "GTA V Premium", price: "890", bids: "24", time: "02:34:12", emoji: "🚗"),
                _AuctionCard(title: "Cyberpunk 2077", price: "1200", bids: "37", time: "00:45:30", emoji: "🤖"),
                _AuctionCard(title: "RDR 2 Ultimate", price: "1500", bids: "18", time: "05:12:44", emoji: "🤠"),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Скидки дня
          _SectionHeader(title: "🏷️ Скидки дня", onSeeAll: () {}),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _DiscountCard(
                  emoji: "🧙",
                  title: "Hogwarts Legacy",
                  desc: "Steam ключ • Глобальный",
                  oldPrice: "3499",
                  newPrice: "1799",
                  discount: "-49%",
                ),
                SizedBox(height: 12),
                _DiscountCard(
                  emoji: "🚀",
                  title: "Starfield",
                  desc: "Steam ключ • Глобальный",
                  oldPrice: "4999",
                  newPrice: "2499",
                  discount: "-50%",
                ),
              ],
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

// Вспомогательные виджеты
class _StoryItem extends StatelessWidget {
  final String emoji;
  final String label;
  final bool isHot;
  const _StoryItem({required this.emoji, required this.label, this.isHot = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF3B82F6)]),
              border: Border.all(color: const Color(0xFF8B5CF6), width: 2),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 28))),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onSeeAll;
  const _SectionHeader({required this.title, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          Text("Все →", style: TextStyle(fontSize: 14, color: const Color(0xFF8B5CF6), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AuctionCard extends StatelessWidget {
  final String title, price, bids, time, emoji;
  const _AuctionCard({required this.title, required this.price, required this.bids, required this.time, required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E1438), Color(0xFF0F0A24)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Container(
            height: 110,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 50)),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.red.withOpacity(0.9), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.timer, size: 12, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(time, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Текущая", style: TextStyle(color: Colors.grey, fontSize: 11)),
                    Text("₽ $price", style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                Text("$bids ставки", style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E1438), Color(0xFF0F0A24)]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: const Color(0xFF6D28D9)),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 32))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15)),
                Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text("₽ $oldPrice", style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey)),
                    const SizedBox(width: 8),
                    Text("₽ $newPrice", style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFF34D399).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(discount, style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}