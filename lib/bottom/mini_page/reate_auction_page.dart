import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../database/steam_store_service.dart';

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
  final _steam = SteamStoreService.instance;

  int _hours = 24;
  bool _isLoading = false;
  bool _previewLoading = false;
  SteamAppInfo? _preview;
  Timer? _previewDebounce;
  String? _previewError;

  @override
  void initState() {
    super.initState();
    _steamUrlController.addListener(_schedulePreview);
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _steamUrlController.removeListener(_schedulePreview);
    _steamUrlController.dispose();
    _minPriceController.dispose();
    _steamKeyController.dispose();
    super.dispose();
  }

  void _schedulePreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 650), _loadPreview);
  }

  Future<void> _loadPreview() async {
    final raw = _steamUrlController.text.trim();
    if (raw.isEmpty) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _previewError = null;
        _previewLoading = false;
      });
      return;
    }

    setState(() {
      _previewLoading = true;
      _previewError = null;
    });

    try {
      _steam.normalizeSteamUrl(raw);
      final info = await _steam.fetchAppInfo(raw);
      if (!mounted) return;
      setState(() {
        _preview = info;
        _previewLoading = false;
        _previewError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _previewLoading = false;
        _previewError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _createAuction() async {
    if (!_formKey.currentState!.validate()) return;

    if (_previewLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Подождите, идёт проверка игры в Steam…'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Пользователь не авторизован');

      final endDate = DateTime.now().add(Duration(hours: _hours));
      final steamUrlRaw = _steamUrlController.text;
      final appInfo = await _steam.fetchAppInfo(steamUrlRaw);

      final steam = SteamStoreService.sanitizeDbText(
        _steamKeyController.text.trim(),
        allowNewlines: true,
      );
      if (steam.isEmpty) {
        throw Exception('Укажите Steam-ключ (steam_key) — обязательное поле');
      }

      await Supabase.instance.client.from('Auction_items').insert({
        'title': appInfo.name,
        'start_price': int.parse(_minPriceController.text.trim()),
        'url_item': appInfo.headerImageUrl,
        'steam_key': steam,
        'ended_at': _formatDbTimestamp(endDate),
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
    } on PostgrestException catch (e) {
      if (mounted) {
        final message = e.code == '22P05'
            ? 'В Steam URL или ключе есть недопустимые скрытые символы. '
                'Вставьте текст заново или введите вручную.'
            : e.message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Ошибка: $message'),
            backgroundColor: Colors.red,
          ),
        );
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

  String _formatDbTimestamp(DateTime value) {
    final dt = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}'
        'T${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Widget _buildSteamPreview() {
    if (_previewLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              'Загружаем данные из Steam…',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_previewError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          _previewError!,
          style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
        ),
      );
    }

    final preview = _preview;
    if (preview == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 460 / 215,
            child: Image.network(
              preview.headerImageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF2A2A3E),
                alignment: Alignment.center,
                child: const Icon(Icons.videogame_asset, color: Colors.grey, size: 48),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'App ID: ${preview.appId}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
              const Text(
                '🎮 Информация об игре',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _steamUrlController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'URL игры в Steam *',
                  labelStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.link, color: Color(0xFF7C3AED)),
                  helperText:
                      'Название и обложка подтянутся автоматически из Steam',
                  helperStyle: const TextStyle(color: Colors.grey, fontSize: 11),
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Введите URL Steam';
                  }
                  try {
                    _steam.normalizeSteamUrl(v);
                    return null;
                  } catch (e) {
                    return e.toString().replaceFirst('Exception: ', '');
                  }
                },
              ),
              _buildSteamPreview(),
              const SizedBox(height: 24),
              const Text(
                '💰 Условия аукциона',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
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
                    items: [6, 12, 24, 48, 72, 168].map((hours) {
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
                        setState(() => _hours = value);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '🔑 Steam ключ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
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
                  helperText:
                      'Скрыт до окончания; один или несколько, с новой строки. '
                      'Вставляйте ключ вручную — из буфера могут попасть скрытые символы.',
                  helperStyle: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                maxLines: 3,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Нужен Steam-ключ' : null,
              ),
              const SizedBox(height: 32),
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
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
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
