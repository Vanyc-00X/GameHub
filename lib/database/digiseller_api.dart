import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

class DigisellerProduct {
  final String id;
  final String name;
  final String fullName;
  final String price;
  final String img;
  final String? seller;
  final String? currency;
  final String? sales;
  final String? buyUrl;
  final String? productUrl;

  DigisellerProduct({
    required this.id,
    required this.name,
    required this.fullName,
    required this.price,
    required this.img,
    this.seller,
    this.currency,
    this.sales,
    this.buyUrl,
    this.productUrl,
  });

  factory DigisellerProduct.fromJson(Map<String, dynamic> json) {
    return DigisellerProduct(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      fullName: json['full_name'] ?? json['fullName'] ?? '',
      price: json['price']?.toString() ?? '0',
      img: json['img'] ?? '',
      seller: json['seller'],
      currency: json['currency'],
      sales: json['sales'],
      buyUrl: json['buy_url'],
      productUrl: json['product_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'full_name': fullName,
      'price': price,
      'img': img,
      'seller': seller,
      'currency': currency,
      'sales': sales,
      'buy_url': buyUrl,
      'product_url': productUrl,
    };
  }
}

class DigisellerApiService {
  static const String _apiBaseUrl = 'https://api.digiseller.com/api';

  /// Эти значения попадут в клиентское приложение. Для production лучше вернуть
  /// серверный proxy, если Digiseller-идентификаторы нельзя раскрывать.
  static const String _sellerId = String.fromEnvironment(
    'DIGISELLER_SELLER_ID',
    defaultValue: '415667',
  );
  static const String _agentId = String.fromEnvironment(
    'DIGISELLER_AGENT_ID',
    defaultValue: '1150998',
  );
  static const String _referralId = String.fromEnvironment(
    'DIGISELLER_REFERRAL_ID',
    defaultValue: '1150998',
  );

  static const int _rowsPerPage = 100;
  static const Duration _cacheDuration = Duration(minutes: 5);
  static const String _cacheKey = 'digiseller_products_cache_v1';
  static const String _cacheLoadedAtKey = 'digiseller_products_loaded_at_v1';

  static final Map<String, DigisellerProduct> _productById = {};
  static List<DigisellerProduct> _products = [];
  static DateTime? _loadedAt;
  static Future<List<DigisellerProduct>>? _loadingFuture;

  Future<List<DigisellerProduct>> fetchProducts({
    bool refresh = false,
    int maxRetries = 2,
  }) async {
    if (!refresh && _isMemoryCacheFresh) return _products;

    if (!refresh) {
      final cached = await _loadFromPersistentCache();
      if (cached.isNotEmpty && _isMemoryCacheFresh) return cached;
    }

    if (_loadingFuture != null && !refresh) return _loadingFuture!;

    _loadingFuture = _fetchAllProductsWithRetry(maxRetries: maxRetries);
    try {
      return await _loadingFuture!;
    } finally {
      _loadingFuture = null;
    }
  }

  Future<List<DigisellerProduct>> _fetchAllProductsWithRetry({
    required int maxRetries,
  }) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final products = await _fetchAllProducts();
        _saveInMemory(products);
        await _saveToPersistentCache(products);

        debugPrint(
          '✅ Digiseller: загружено ${products.length} товаров напрямую',
        );
        return products;
      } on SocketException catch (e) {
        debugPrint('🔌 Digiseller сеть #${attempt + 1}: $e');
        if (attempt == maxRetries) {
          return _fallbackOrThrow(
            'Нет соединения с Digiseller. Проверьте интернет на устройстве.',
          );
        }
      } on http.ClientException catch (e) {
        debugPrint('🔗 Digiseller client #${attempt + 1}: $e');
        if (attempt == maxRetries) {
          return _fallbackOrThrow('Соединение с Digiseller было разорвано.');
        }
      } on FormatException catch (e) {
        debugPrint('❌ Digiseller XML #${attempt + 1}: $e');
        if (attempt == maxRetries) {
          return _fallbackOrThrow(
            'Digiseller вернул неожиданный формат ответа.',
          );
        }
      } on Exception catch (e) {
        debugPrint('❌ Digiseller #${attempt + 1}: $e');
        if (attempt == maxRetries) {
          return _fallbackOrThrow('Ошибка загрузки товаров Digiseller: $e');
        }
      }

      await Future.delayed(Duration(seconds: attempt + 1));
    }

    return _fallbackOrThrow('Не удалось загрузить товары Digiseller.');
  }

  Future<List<DigisellerProduct>> _fetchAllProducts() async {
    final client = http.Client();
    final products = <DigisellerProduct>[];

    try {
      var page = 1;

      while (true) {
        final document = await _fetchProductsPage(client, page);
        _ensureSuccessfulDigisellerResponse(document);

        final pageProducts = document
            .findAllElements('product')
            .map(_productFromXml)
            .where((product) => product.id.isNotEmpty)
            .toList();

        products.addAll(pageProducts);
        debugPrint('📦 Digiseller страница $page: +${pageProducts.length}');

        if (pageProducts.length < _rowsPerPage) break;
        page++;
      }

      return products;
    } finally {
      client.close();
    }
  }

  Future<XmlDocument> _fetchProductsPage(http.Client client, int page) async {
    final uri = Uri.parse('$_apiBaseUrl/shop/products').replace(
      queryParameters: {
        'seller_id': _sellerId,
        'category_id': '0',
        'page': page.toString(),
        'rows': _rowsPerPage.toString(),
        'currency': 'RUB',
        'lang': 'ru-RU',
        'order': 'name',
      },
    );

    debugPrint('🔍 Digiseller GET $uri');

    final response = await client
        .get(uri, headers: {'Accept': 'application/xml, text/xml, */*'})
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
    }

    return XmlDocument.parse(utf8.decode(response.bodyBytes));
  }

  /// Получает один товар по ID
  Future<DigisellerProduct?> fetchProduct(String id) async {
    try {
      if (_productById.containsKey(id)) return _productById[id];

      final products = await fetchProducts();
      return products.where((product) => product.id == id).firstOrNull;
    } on Exception catch (e) {
      debugPrint('❌ Ошибка загрузки товара $id: $e');
      return null;
    } catch (e) {
      debugPrint('❌ Ошибка загрузки товара $id: $e');
      return null;
    }
  }

  /// Поиск товаров по запросу
  Future<List<DigisellerProduct>> searchProducts(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final normalizedQuery = query.toLowerCase().trim();
      final products = await fetchProducts();

      return products
          .where(
            (product) =>
                product.name.toLowerCase().contains(normalizedQuery) ||
                product.fullName.toLowerCase().contains(normalizedQuery),
          )
          .toList();
    } on Exception catch (e) {
      debugPrint('❌ Ошибка поиска "$query": $e');
      return [];
    } catch (e) {
      debugPrint('❌ Ошибка поиска "$query": $e');
      return [];
    }
  }

  /// Проверка доступности Digiseller API.
  Future<bool> isServerAlive({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = Uri.parse('$_apiBaseUrl/shop/products').replace(
      queryParameters: {
        'seller_id': _sellerId,
        'category_id': '0',
        'page': '1',
        'rows': '1',
        'currency': 'RUB',
        'lang': 'ru-RU',
        'order': 'name',
      },
    );

    try {
      final response = await http.get(uri).timeout(timeout);
      if (response.statusCode != 200) return false;

      final document = XmlDocument.parse(utf8.decode(response.bodyBytes));
      return _text(document.rootElement, 'retval') == '0';
    } catch (_) {
      return false;
    }
  }

  /// Принудительное обновление локального кэша приложения.
  Future<bool> refreshCache() async {
    try {
      await fetchProducts(refresh: true, maxRetries: 1);
      return true;
    } catch (e) {
      debugPrint('❌ Ошибка обновления кэша: $e');
      return false;
    }
  }

  /// Получение базового URL Digiseller (для отладки).
  String get baseUrl => _apiBaseUrl;

  bool get _isMemoryCacheFresh {
    final loadedAt = _loadedAt;
    if (_products.isEmpty || loadedAt == null) return false;
    return DateTime.now().difference(loadedAt) < _cacheDuration;
  }

  void _saveInMemory(List<DigisellerProduct> products, {DateTime? loadedAt}) {
    _products = products;
    _productById
      ..clear()
      ..addEntries(products.map((product) => MapEntry(product.id, product)));
    _loadedAt = loadedAt ?? DateTime.now();
  }

  Future<List<DigisellerProduct>> _loadFromPersistentCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawLoadedAt = prefs.getInt(_cacheLoadedAtKey);
      final rawProducts = prefs.getString(_cacheKey);

      if (rawLoadedAt == null || rawProducts == null) return [];

      final loadedAt = DateTime.fromMillisecondsSinceEpoch(rawLoadedAt);
      if (DateTime.now().difference(loadedAt) >= _cacheDuration) return [];

      final decoded = json.decode(rawProducts) as List<dynamic>;
      final products = decoded
          .map(
            (item) => DigisellerProduct.fromJson(item as Map<String, dynamic>),
          )
          .toList();

      _saveInMemory(products, loadedAt: loadedAt);
      debugPrint(
        '✅ Digiseller: загружено ${products.length} товаров из локального кэша',
      );
      return products;
    } catch (e) {
      debugPrint('❌ Digiseller cache read: $e');
      return [];
    }
  }

  Future<void> _saveToPersistentCache(List<DigisellerProduct> products) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _cacheLoadedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.setString(
        _cacheKey,
        json.encode(products.map((product) => product.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('❌ Digiseller cache write: $e');
    }
  }

  Future<List<DigisellerProduct>> _fallbackOrThrow(String message) async {
    if (_products.isNotEmpty) return _products;

    final cached = await _loadFromPersistentCache();
    if (cached.isNotEmpty) return cached;

    throw Exception(message);
  }

  DigisellerProduct _productFromXml(XmlElement item) {
    final id = _text(item, 'id');
    final fullName = _text(item, 'name', fallback: 'Без названия');
    final price = _text(item, 'price', fallback: '0');

    return DigisellerProduct(
      id: id,
      name: _cleanName(fullName),
      fullName: fullName,
      price: price,
      img: 'https://graph.digiseller.ru/img.ashx?id_d=$id&maxlength=400',
      buyUrl: _buildBuyUrl(id),
      productUrl: 'https://www.digiseller.market/product/$id',
      currency: _text(item, 'currency', fallback: 'RUB'),
      sales: _text(item, 'sales', fallback: '0'),
    );
  }

  void _ensureSuccessfulDigisellerResponse(XmlDocument document) {
    final root = document.rootElement;
    final retval = _text(root, 'retval');

    if (retval == '0') return;

    final description = _text(root, 'retdesc', fallback: 'неизвестная ошибка');
    throw Exception('Digiseller API: $description');
  }

  String _text(XmlElement element, String name, {String fallback = ''}) {
    final found = element.findElements(name).firstOrNull;
    final value = found?.innerText.trim();
    return value == null || value.isEmpty ? fallback : value;
  }

  String _buildBuyUrl(String productId) {
    final params = <String, String>{'id_d': productId};
    final affiliateId = _referralId.isNotEmpty ? _referralId : _agentId;

    if (affiliateId.isNotEmpty) params['aff_id'] = affiliateId;

    return Uri.https(
      'www.digiseller.market',
      '/asp2/pay_wm.asp',
      params,
    ).toString();
  }

  String _cleanName(String rawName) {
    if (rawName.trim().isEmpty) return 'Без названия';

    var name = rawName
        .replaceFirst(
          RegExp(
            r'\s*\(?(Steam|STEAM|Region|GLOBAL|RU|РФ|СНГ|Key|ключ).*$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[★☆✅✔♦️⚡]+'), '')
        .trim()
        .replaceAll(RegExp(r'^[-|\s]+|[-|\s]+$'), '');

    for (final separator in ['(', '[', ':', ' – ', ' - ']) {
      if (name.contains(separator)) {
        name = name.split(separator).first.trim();
      }
    }

    final words = name
        .split(RegExp(r'\s+'))
        .where((word) {
          final lower = word.toLowerCase();
          return !_trashWords.contains(lower) && word.length > 1;
        })
        .join(' ')
        .trim();

    return words.isNotEmpty ? words : rawName.trim();
  }

  static const Set<String> _trashWords = {
    'steam',
    'ключ',
    'key',
    'steamkey',
    'region',
    'free',
    'global',
    'ru',
    'рф',
    'снг',
    'mir',
    'весь',
    'мир',
    'подарок',
    'бонус',
    'карточки',
    'картинки',
    'набор',
    'для',
    'на',
    'от',
    'и',
    'с',
    'в',
    'по',
    'из',
    'оператор',
    'доставка',
    'мгновенная',
  };
}
