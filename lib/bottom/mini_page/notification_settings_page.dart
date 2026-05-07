import 'package:flutter/material.dart';

import '../../database/services/notification_preferences_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  NotificationPreferences _prefs = const NotificationPreferences();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await NotificationPreferencesService.instance.loadPreferences(
      refresh: true,
    );
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _loading = false;
    });
  }

  Future<void> _save(NotificationPreferences prefs) async {
    setState(() {
      _prefs = prefs;
      _saving = true;
    });
    await NotificationPreferencesService.instance.savePreferences(prefs);
    if (!mounted) return;
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        title: const Text(
          'Настроить уведомления',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _SwitchCard(
                  icon: Icons.chat_bubble_outline,
                  title: 'Чаты',
                  subtitle:
                      'Новые сообщения в личных чатах, каналах и группах.',
                  value: _prefs.chats,
                  onChanged: (value) => _save(_prefs.copyWith(chats: value)),
                ),
                _SwitchCard(
                  icon: Icons.gavel,
                  title: 'Аукционы',
                  subtitle:
                      'Новые ставки, завершение аукциона и выигранные лоты.',
                  value: _prefs.auctions,
                  onChanged: (value) => _save(_prefs.copyWith(auctions: value)),
                ),
                _SwitchCard(
                  icon: Icons.rss_feed,
                  title: 'Лента',
                  subtitle: 'Лайки, комментарии и цитаты ваших постов.',
                  value: _prefs.feed,
                  onChanged: (value) => _save(_prefs.copyWith(feed: value)),
                ),
                const SizedBox(height: 16),
                Text(
                  _saving ? 'Сохраняю...' : 'Настройки применяются сразу',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }
}

class _SwitchCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF7C3AED)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: const Color(0xFF7C3AED),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
