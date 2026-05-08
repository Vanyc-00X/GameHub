import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../database/services/chat_service.dart';
import '../widgets/notification_bell.dart';
import 'mini_page/chat_screen.dart';
import 'mini_page/user_profile_page.dart';

// ? Чаты: личные, каналы, группы (как в Telegram) + обзор для вступления
class BottomChat extends StatefulWidget {
  const BottomChat({super.key});

  @override
  State<BottomChat> createState() => _BottomChatState();
}

class _BottomChatState extends State<BottomChat> with TickerProviderStateMixin {
  final _chatService = ChatService();
  final _searchController = TextEditingController();
  final _createController = TextEditingController();
  late final TabController _tabController;
  int _createTab = 0; // 0 private, 1 channel, 2 group

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _createController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filterBySearch(List<Map<String, dynamic>> items) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((item) {
      final chat = item['chat'] as Map<String, dynamic>?;
      final name = chat?['namechat']?.toString().toLowerCase() ?? '';
      final last = (item['last_message'] as List<dynamic>?)?.isNotEmpty == true
          ? (item['last_message'] as List).first['content']?.toString().toLowerCase() ?? ''
          : '';
      return name.contains(q) || last.contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> _byType(
    List<Map<String, dynamic>> all,
    String? type, {
    bool privateOnly = false,
  }) {
    return all.where((item) {
      final t = (item['chat'] as Map<String, dynamic>?)?['type_chat'] as String? ?? '';
      if (privateOnly) return t == 'private';
      if (type != null) return t == type;
      return true;
    }).toList();
  }

  Future<void> _refreshChats() => _chatService.refreshChats();

  Future<void> _createPrivateChat() async {
    final login = _createController.text.trim();
    if (login.isEmpty) return;
    try {
      final newChat = await _chatService.createPrivateChat(login);
      if (newChat == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Пользователь не найден')),
          );
        }
        return;
      }
      _createController.clear();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Личный чат создан')),
        );
        final name = newChat['namechat'] as String? ?? 'Чат';
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              chatId: (newChat['id'] as num).toInt(),
              chatName: name,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Future<void> _showCreateSheet() async {
    _createTab = 0;
    final nameC = TextEditingController();
    final descC = TextEditingController();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1430),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setM) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Новая комната',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Личка')),
                      ButtonSegment(value: 1, label: Text('Канал')),
                      ButtonSegment(value: 2, label: Text('Группа')),
                    ],
                    selected: {_createTab},
                    onSelectionChanged: (s) {
                      setM(() {
                        _createTab = s.first;
                      });
                    },
                  ),
                  if (_createTab == 0) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _createController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Логин пользователя',
                        labelStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _createPrivateChat();
                      },
                      child: const Text('Создать'),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameC,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Название',
                        labelStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descC,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Описание (необязательно)',
                        labelStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        if (nameC.text.trim().isEmpty) return;
                        final t = _createTab == 1 ? 'channel' : 'group';
                        final c = await _chatService.createRoom(
                          name: nameC.text,
                          description: descC.text,
                          typeChat: t,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (c == null || !context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              t == 'channel' ? 'Канал создан' : 'Группа создана',
                            ),
                          ),
                        );
                        final name = c['namechat'] as String? ?? 'Чат';
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              chatId: (c['id'] as num).toInt(),
                              chatName: name,
                            ),
                          ),
                        );
                      },
                      child: const Text('Создать'),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 60, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Сообщения',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              NotificationBell(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Поиск...',
                    hintStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: _showCreateSheet,
                icon: const Icon(Icons.edit_square, color: Color(0xFF7C3AED), size: 32),
                tooltip: 'Создать',
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF7C3AED),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF7C3AED),
          tabs: const [
            Tab(text: 'Чаты'),
            Tab(text: 'Каналы'),
            Tab(text: 'Группы'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPrivateChats(),
              _buildChannelTab(),
              _buildGroupTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPrivateChats() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _chatService.chatsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Ошибка: ${snapshot.error}', style: const TextStyle(color: Colors.grey)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = _byType(snapshot.data!, null, privateOnly: true);
        final list = _filterBySearch(all);
        if (list.isEmpty) {
          return const Center(
            child: Text(
              'Нет личных чатов\nСоздайте чат кнопкой «Создать»',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refreshChats,
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: list.length,
            itemBuilder: (context, index) {
              return _buildChatRow(list[index], Icons.person_rounded, const Color(0xFF5B8CFF));
            },
          ),
        );
      },
    );
  }

  Widget _buildChannelTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _chatService.chatsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}', style: const TextStyle(color: Colors.grey)));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final my = _filterBySearch(_byType(snapshot.data!, 'channel'));
        return RefreshIndicator(
          onRefresh: _refreshChats,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _DiscoverBlock(
                  typeChat: 'channel',
                  icon: Icons.campaign,
                  onJoined: () => setState(() {}),
                ),
              ),
              if (my.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Вы ещё не в каналах (вступите ниже)',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _buildChatRow(
                      my[i],
                      Icons.campaign,
                      const Color(0xFF2AABEE),
                    ),
                    childCount: my.length,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGroupTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _chatService.chatsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}', style: const TextStyle(color: Colors.grey)));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final my = _filterBySearch(_byType(snapshot.data!, 'group'));
        return RefreshIndicator(
          onRefresh: _refreshChats,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _DiscoverBlock(
                  typeChat: 'group',
                  icon: Icons.group,
                  onJoined: () => setState(() {}),
                ),
              ),
              if (my.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Нет групп — вступите в доступные ниже',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _buildChatRow(
                      my[i],
                      Icons.group,
                      const Color(0xFF6BCB4F),
                    ),
                    childCount: my.length,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChatRow(
    Map<String, dynamic> item,
    IconData typeIcon,
    Color accent,
  ) {
    final chat = item['chat'] as Map<String, dynamic>?;
    if (chat == null) return const SizedBox.shrink();
    final name = chat['namechat'] as String? ?? 'Чат';
    final peer = chat['peer'] as Map<String, dynamic>?;
    final peerAvatar = peer?['avatar'] as String?;
    final peerId = peer?['id']?.toString();
    final lastMsgList = item['last_message'] as List<dynamic>? ?? [];
    final lastMsg = lastMsgList.isNotEmpty
        ? (lastMsgList.first['content'] as String? ?? '…')
        : 'Нет сообщений';
    final time = lastMsgList.isNotEmpty
        ? timeago.format(
            DateTime.parse(lastMsgList.first['created_at'] as String),
            locale: 'ru',
          )
        : '';
    return ListTile(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              chatId: (chat['id'] as num).toInt(),
              chatName: name,
            ),
          ),
        );
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: GestureDetector(
        onTap: peerId == null
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfilePage(userId: peerId),
                  ),
                );
              },
        child: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.3),
          backgroundImage:
              (peerAvatar != null && peerAvatar.isNotEmpty)
                  ? NetworkImage(peerAvatar)
                  : null,
          child: (peerAvatar == null || peerAvatar.isEmpty)
              ? Icon(typeIcon, color: accent, size: 24)
              : null,
        ),
      ),
      title: GestureDetector(
        onTap: peerId == null
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfilePage(userId: peerId),
                  ),
                );
              },
        child: Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      subtitle: Text(
        lastMsg,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.grey, fontSize: 13),
      ),
      trailing: Text(time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    );
  }
}

class _DiscoverBlock extends StatefulWidget {
  final String typeChat;
  final IconData icon;
  final VoidCallback onJoined;

  const _DiscoverBlock({
    required this.typeChat,
    required this.icon,
    required this.onJoined,
  });

  @override
  State<_DiscoverBlock> createState() => _DiscoverBlockState();
}

class _DiscoverBlockState extends State<_DiscoverBlock> {
  final _svc = ChatService();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _svc.listDiscoverChats(widget.typeChat);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Text(
              snap.connectionState == ConnectionState.waiting
                  ? 'Загрузка каталога…'
                  : (widget.typeChat == 'channel'
                        ? 'Нет публичных каналов. Создайте канал (кнопка «Создать»).'
                        : 'Нет публичных групп. Создайте группу (кнопка «Создать»).'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          );
        }
        final list = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'Вступить',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            ...list.map((c) {
              final name = c['namechat'] as String? ?? 'Чат';
              final desc = c['descriptions'] as String? ?? '';
              return ListTile(
                leading: Icon(widget.icon, color: const Color(0xFF7C3AED)),
                title: Text(name, style: const TextStyle(color: Colors.white)),
                subtitle: desc.isNotEmpty
                    ? Text(
                        desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      )
                    : null,
                trailing: FilledButton.tonal(
                  onPressed: () async {
                    final err = await _svc.joinChat((c['id'] as num).toInt());
                    if (context.mounted) {
                      if (err != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(err)),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Вы вступили')),
                        );
                        setState(() {
                          _future = _svc.listDiscoverChats(widget.typeChat);
                        });
                        widget.onJoined();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              chatId: (c['id'] as num).toInt(),
                              chatName: name,
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Войти'),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
