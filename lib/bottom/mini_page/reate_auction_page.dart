import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateAuctionPage extends StatefulWidget {
  const CreateAuctionPage({super.key});

  @override
  State<CreateAuctionPage> createState() => _CreateAuctionPageState();
}

class _CreateAuctionPageState extends State<CreateAuctionPage> {
  final _formKey = GlobalKey<FormState>();
  final _steamUrlController = TextEditingController();
  final _minPriceController = TextEditingController();
  final _steamKeyController = TextEditingController();
  
  int _hours = 24; // По умолчанию 24 часа
  bool _isLoading = false;

  @override
  void dispose() {
    _steamUrlController.dispose();
    _minPriceController.dispose();
    _steamKeyController.dispose();
    super.dispose();
  }

  Future<void> _createAuction() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Пользователь не авторизован');

      final endDate = DateTime.now().add(Duration(hours: _hours));
      final steamUrl = _steamUrlController.text.trim();
      if (steamUrl.isEmpty) {
        throw Exception('Укажите URL игры в Steam');
      }
      final steam = _steamKeyController.text.trim();
      if (steam.isEmpty) {
        throw Exception('Укажите Steam-ключ (steam_key) — обязательное поле');
      }
      final uri = Uri.tryParse(steamUrl);
      if (uri == null || (!steamUrl.startsWith('http://') && !steamUrl.startsWith('https://'))) {
        throw Exception('URL Steam должен начинаться с http:// или https://');
      }
      final titleFromUrl = _extractSteamTitle(steamUrl);

      // Только поля из схемы: Auction_items
      await Supabase.instance.client.from('Auction_items').insert({
        'title': titleFromUrl,
        'start_price': int.parse(_minPriceController.text),
        'url_item': steamUrl,
        'steam_key': steam,
        'ended_at': endDate.toIso8601String(),
        'is_active': true,
        'owner_id': user.id,
        'bid_count': 0,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Аукцион успешно создан!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _extractSteamTitle(String steamUrl) {
    try {
      final u = Uri.parse(steamUrl);
      final seg = u.pathSegments;
      final appIdx = seg.indexOf('app');
      if (appIdx != -1 && appIdx + 2 < seg.length) {
        return seg[appIdx + 2].replaceAll('_', ' ');
      }
    } catch (_) {}
    return steamUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Создать аукцион',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🎮 Информация об игре
              const Text(
                '🎮 Информация об игре',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),

              // URL игры в Steam
              TextFormField(
                controller: _steamUrlController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'URL игры в Steam *',
                  labelStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.link, color: Color(0xFF7C3AED)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Введите URL Steam' : null,
              ),
              
              const SizedBox(height: 24),

              // 💰 Цена и длительность
              const Text(
                '💰 Условия аукциона',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),

              // Минимальная цена
              TextFormField(
                controller: _minPriceController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Минимальная цена (очки) *',
                  labelStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.star, color: Color(0xFFF59E0B)),
                  suffixText: '⭐',
                  suffixStyle: const TextStyle(color: Color(0xFFF59E0B)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите цену';
                  }
                  if (int.tryParse(value) == null) {
                    return 'Введите число';
                  }
                  if (int.parse(value) < 10) {
                    return 'Минимум 10 очков';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Часы (длительность)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _hours,
                    isExpanded: true,
                    icon: const Icon(Icons.access_time, color: Color(0xFF7C3AED)),
                    dropdownColor: const Color(0xFF1A1A2E),
                    items: [
                      6, 12, 24, 48, 72, 168 // 6ч, 12ч, 1 день, 2 дня, 3 дня, 7 дней
                    ].map((hours) {
                      String label;
                      if (hours < 24) {
                        label = '$hours ч.';
                      } else if (hours == 24) {
                        label = '1 день';
                      } else {
                        label = '${hours ~/ 24} дн.';
                      }
                      return DropdownMenuItem(
                        value: hours,
                        child: Row(
                          children: [
                            const Icon(Icons.timer, size: 18, color: Color(0xFF7C3AED)),
                            const SizedBox(width: 8),
                            Text(
                              label,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _hours = value;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 🔑 Steam данные
              const Text(
                '🔑 Steam ключ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),

              // Steam ключ
              TextFormField(
                controller: _steamKeyController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Steam ключ (steam_key) *',
                  labelStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.vpn_key, color: Color(0xFF10B981)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  helperText: 'Скрыт до окончания; один или несколько, с новой строки',
                  helperStyle: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                maxLines: 3,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Нужен Steam-ключ' : null,
              ),
              
              const SizedBox(height: 32),

              // 🔨 Кнопка создания
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createAuction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 8,
                    shadowColor: const Color(0xFF7C3AED).withOpacity(0.4),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.gavel, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              '🔨 Создать аукцион',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                ),
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}