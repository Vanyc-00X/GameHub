import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/services/profile_service.dart';
import 'mini_page/auctions_list_page.dart';
import 'mini_page/edit_profile_page.dart';
import 'mini_page/reate_auction_page.dart';

class BottomProfile extends StatefulWidget {
  const BottomProfile({super.key});

  @override
  State<BottomProfile> createState() => _BottomProfileState();
}

class _BottomProfileState extends State<BottomProfile> {
  final _profileService = ProfileService();
  Map<String, dynamic>? _profileData;
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;
  bool _notificationsLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final userAuth = Supabase.instance.client.auth.currentUser;
      if (userAuth == null) {
        setState(() {
          _error = 'Пользователь не авторизован';
          _loading = false;
        });
        return;
      }

      debugPrint('🔄 Загрузка профиля: ${userAuth.id}');

      final data = await _profileService.getProfileData(userAuth.id).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Сервер не отвечает'),
      );

      if (mounted) {
        debugPrint('✅ Профиль загружен: ${data['user']['username']}');
        setState(() {
          _profileData = data;
          _loading = false;
        });
      }
    } on TimeoutException {
      _handleError('Таймаут: проверьте интернет-соединение');
    } on PostgrestException catch (e) {
      _handleError('Ошибка БД: ${e.message}');
      debugPrint('📍 Postgrest: ${e.details}');
    } catch (e, stack) {
      _handleError('Ошибка: $e');
      debugPrint('📍 Stack: $stack');
    }
  }

  void _handleError(String message) {
    if (mounted) {
      setState(() {
        _error = message;
        _loading = false;
      });
    }
  }

  Future<void> _loadNotifications() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      setState(() => _notificationsLoading = true);
      _notifications = await _profileService.getNotifications(user.id);
      
      if (mounted) {
        setState(() => _notificationsLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _notificationsLoading = false);
      }
    }
  }

  void _showNotificationsBottomSheet() {
    setState(() => _notifications = []);
    _loadNotifications();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '🔔 Уведомления',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  TextButton(
                    onPressed: _notifications.isNotEmpty
                        ? () async {
                            final user = Supabase.instance.client.auth.currentUser;
                            if (user != null) {
                              await _profileService.markAllNotificationsAsRead(user.id);
                              setModalState(() {
                                for (var n in _notifications) {
                                  n['is_watched'] = true;
                                }
                              });
                            }
                          }
                        : null,
                    child: const Text('Все проч.', style: TextStyle(color: Color(0xFF7C3AED))),
                  ),
                ],
              ),
              const Divider(color: Colors.white24),
              _notificationsLoading
                  ? const Expanded(child: Center(child: CircularProgressIndicator()))
                  : _notifications.isEmpty
                      ? const Expanded(
                          child: Center(
                            child: Text('Нет новых уведомлений', style: TextStyle(color: Colors.grey)),
                          ),
                        )
                      : Expanded(
                          child: ListView.separated(
                            itemCount: _notifications.length,
                            separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                            itemBuilder: (context, index) {
                              final notif = _notifications[index];
                              final isRead = notif['is_watched'] == true;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: isRead ? Colors.grey.withOpacity(0.3) : const Color(0xFF7C3AED),
                                  child: Text(!isRead ? '•' : '✓', style: const TextStyle(color: Colors.white)),
                                ),
                                title: Text(
                                  notif['title'] ?? 'Без заголовка',
                                  style: TextStyle(
                                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  notif['content'] ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                                trailing: Text(
                                  _formatDate(notif['created_at']),
                                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                                ),
                                onTap: () async {
                                  await _profileService.markNotificationAsRead(notif['id']);
                                  setModalState(() {
                                    _notifications[index]['is_watched'] = true;
                                  });
                                },
                              );
                            },
                          ),
                        ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 1) return 'только что';
      if (diff.inHours < 1) return '${diff.inMinutes} мин.';
      if (diff.inDays < 1) return '${diff.inHours} ч.';
      return '${date.day}.${date.month}';
    } catch (_) {
      return dateStr;
    }
  }

  String _pluralize(int num, String one, String two, String five) {
    final mod = num % 10;
    if (num % 100 >= 11 && num % 100 <= 14) return five;
    if (mod == 1) return one;
    if (mod >= 2 && mod <= 4) return two;
    return five;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
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
              onPressed: _loadProfile,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    final user = _profileData!['user'];
    final postsCount = _profileData!['postsCount'] as int;
    final activeAuctions = _profileData!['activeAuctions'] as int;
    final completedAuctions = _profileData!['completedAuctions'] as int;
    final rating = _profileData!['rating'] as double;
    final points = _profileData!['points'] as int? ?? 0; // 👈 Очки пользователя
    final joinedAt = DateTime.parse(_profileData!['joinedAt']);
    final yearsOnPlatform = DateTime.now().difference(joinedAt).inDays ~/ 365;

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 60),

          // 👤 Avatar + Points Badge
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 45,
                backgroundColor: const Color(0xFF7C3AED),
                child: user['avatar'] != null && user['avatar'].toString().isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          user['avatar'],
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Text("😎", style: TextStyle(fontSize: 50)),
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return const CircularProgressIndicator();
                          },
                        ),
                      )
                    : const Text("😎", style: TextStyle(fontSize: 50)),
              ),
              // 🏆 Badge с очками
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      '$points',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Text(
            user['username'] ?? 'Пользователь',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          Text(
            '@${user['login'] ?? 'no_login'} • $yearsOnPlatform ${_pluralize(yearsOnPlatform, 'год', 'года', 'лет')}',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 24),

          // 📊 Stats (обновлённые)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ProfileStat(
                value: "$points", 
                label: "Очков",
                icon: Icons.star,
                color: Colors.orange,
              ),
              const SizedBox(width: 30),
              _ProfileStat(
                value: "$activeAuctions", 
                label: "Аукционов",
                icon: Icons.gavel,
                color: const Color(0xFF7C3AED),
              ),
              const SizedBox(width: 30),
              _ProfileStat(
                value: rating.toString(), 
                label: "Рейтинг",
                icon: Icons.star_border,
                color: Colors.yellow,
              ),
            ],
          ),

          const SizedBox(height: 30),

          // 🔘 Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditProfilePage(
                            userData: {
                              'username': user['username'],
                              'login': user['login'],
                              'email': user['email'],
                              'avatar': user['avatar'],
                            },
                          ),
                        ),
                      );
                      
                      if (result != null && mounted) {
                        setState(() {
                          _profileData = {
                            ..._profileData!,
                            'user': result,
                          };
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("✏️ Редактировать", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('📤 Скопировано: @${user['login']}')),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("📤 Поделиться", style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // 🧭 Menu
          _ProfileMenuItem(
            icon: "➕",
            title: "Создать аукцион",
            subtitle: "Выставь игру на продажу",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateAuctionPage(),
                ),
              );
            },
          ),
          _ProfileMenuItem(
            icon: "🔨",
            title: "Мои аукционы",
            subtitle: "$activeAuctions активных, $completedAuctions завершённых",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AuctionsListPage(),
                ),
              );
            },
          ),
          _ProfileMenuItem(
            icon: "🔔",
            title: "Уведомления",
            subtitle: "История оповещений",
            onTap: _showNotificationsBottomSheet,
          ),
          _ProfileMenuItem(
            icon: "🚪",
            title: "Выйти",
            subtitle: "Выход из аккаунта",
            isLogout: true,
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A2E),
                  title: const Text('Выход', style: TextStyle(color: Colors.white)),
                  content: const Text('Вы уверены?', style: TextStyle(color: Colors.grey)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Выйти'),
                    ),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                await _profileService.signOut();
                if (mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false);
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

// ===== Вспомогательные виджеты =====

class _ProfileStat extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  
  const _ProfileStat({
    required this.value, 
    required this.label,
    required this.icon,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  final String icon, title, subtitle;
  final bool isLogout;
  final VoidCallback? onTap;
  
  const _ProfileMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isLogout = false,
    this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isLogout ? Colors.red.withOpacity(0.15) : const Color(0xFF7C3AED).withOpacity(0.15),
        ),
        child: Center(child: Text(icon, style: const TextStyle(fontSize: 22))),
      ),
      title: Text(
        title, 
        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle, 
        style: const TextStyle(color: Colors.grey, fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
    );
  }
}