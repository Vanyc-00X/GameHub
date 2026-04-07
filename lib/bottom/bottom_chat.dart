import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'mini_page/chat_screen.dart';


final supabase = Supabase.instance.client;

class BottomChat extends StatefulWidget {
  const BottomChat({super.key});

  @override
  State<BottomChat> createState() => _BottomChatState();
}

class _BottomChatState extends State<BottomChat> {
  List<Map<String, dynamic>> _chats = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _createController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchUserChats();
    _searchController.addListener(_filterChats);
  }

  Future<void> _fetchUserChats() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await supabase
          .from('ChatMember')
          .select('''
            chat:Chat (
              id,
              namechat,
              type_chat,
              created_at
            )
          ''')
          .eq('user_id', user.id)
          .order('created_at', ascending: false, referencedTable: 'chat');

      // Загружаем последнее сообщение для каждого чата
      final chatsWithLastMsg = await Future.wait(
        response.map((row) async {
          final chatId = row['chat']['id'];

          final lastMessage = await supabase
              .from('Message')
              .select('content, created_at')
              .eq('chat_id', chatId)
              .order('created_at', ascending: false)
              .limit(1);

          return {...row, 'last_message': lastMessage};
        }),
      );

      setState(() {
        _chats = List<Map<String, dynamic>>.from(chatsWithLastMsg);
      });
    } catch (e) {
      debugPrint('Ошибка загрузки чатов: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterChats() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {}); // просто перерисовать
      return;
    }
    // Можно добавить фильтрацию по namechat при необходимости
  }

  Future<void> _createPrivateChat() async {
    final login = _createController.text.trim();
    if (login.isEmpty) return;

    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    try {
      final target = await supabase
          .from('User')
          .select('id, username')
          .eq('login', login)
          .maybeSingle();

      if (target == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Пользователь не найден')));
        return;
      }

      // Простая проверка на существующий чат (упрощённая)
      final existing = await supabase
          .from('ChatMember')
          .select('chat_id')
          .eq('user_id', currentUser.id)
          .limit(10); // можно улучшить позже

      // Создаём новый чат
      final newChat = await supabase
          .from('Chat')
          .insert({'namechat': target['username'], 'type_chat': 'private'})
          .select()
          .single();

      await supabase.from('ChatMember').insert([
        {'user_id': currentUser.id, 'chat_id': newChat['id']},
        {'user_id': target['id'], 'chat_id': newChat['id']},
      ]);

      _createController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Чат создан')));
      _fetchUserChats();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _fetchUserChats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 60, 20, 16),
              child: Text(
                "💬 Чаты",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),

            // Поиск + кнопка создания
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: Colors.grey),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: "Поиск чатов...",
                                hintStyle: TextStyle(color: Colors.grey),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF1A1430),
                          title: const Text(
                            "Новый чат",
                            style: TextStyle(color: Colors.white),
                          ),
                          content: TextField(
                            controller: _createController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: "Логин пользователя",
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text("Отмена"),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _createPrivateChat();
                              },
                              child: const Text(
                                "Создать",
                                style: TextStyle(color: Color(0xFF7C3AED)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.add_circle,
                      color: Color(0xFF7C3AED),
                      size: 36,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(80),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_chats.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 120),
                  child: Column(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 80,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 20),
                      Text(
                        "Пока нет чатов",
                        style: TextStyle(fontSize: 20, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        "Создайте новый чат с помощью кнопки +",
                        style: TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _chats.length,
                itemBuilder: (context, index) {
                  final item = _chats[index];
                  final chat = item['chat'] as Map<String, dynamic>;
                  final name = chat['namechat'] as String? ?? 'Чат';
                  final avatar = name.isNotEmpty ? name[0].toUpperCase() : '💬';

                  final lastMsgList =
                      item['last_message'] as List<dynamic>? ?? [];
                  final lastMsg = lastMsgList.isNotEmpty
                      ? lastMsgList.first['content'] as String? ??
                            'Нет сообщений'
                      : 'Нет сообщений';

                  final time = lastMsgList.isNotEmpty
                      ? timeago.format(
                          DateTime.parse(lastMsgList.first['created_at']),
                          locale: 'ru',
                        )
                      : 'Недавно';

                  return _ChatItem(
                    name: name,
                    lastMsg: lastMsg,
                    time: time,
                    avatar: avatar,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            chatId: item['chat']['id'],
                            chatName: name,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _createController.dispose();
    super.dispose();
  }
}

// ====================== Виджет чата ======================
class _ChatItem extends StatelessWidget {
  final String name, lastMsg, time, avatar;
  final VoidCallback? onTap;

  const _ChatItem({
    super.key,
    required this.name,
    required this.lastMsg,
    required this.time,
    required this.avatar,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: const Color(0xFF7C3AED),
        child: Text(avatar, style: const TextStyle(fontSize: 26)),
      ),
      title: Text(
        name,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      subtitle: Text(
        lastMsg,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.grey),
      ),
      trailing: Text(
        time,
        style: const TextStyle(color: Colors.grey, fontSize: 13),
      ),
    );
  }
}
