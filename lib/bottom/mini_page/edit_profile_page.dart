import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key, required this.userData});
  final Map<String, dynamic> userData;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late TextEditingController _usernameController;
  late TextEditingController _loginController;
  late TextEditingController _emailController;
  String? _avatarUrl;
  bool _isLoading = false;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.userData['username']);
    _loginController = TextEditingController(text: widget.userData['login']);
    _emailController = TextEditingController(text: widget.userData['email']);
    _avatarUrl = widget.userData['avatar'];
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _loginController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// Выбор изображения из галереи
  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      
      if (picked != null) {
        setState(() {
          _selectedImage = File(picked.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка выбора фото: $e')),
        );
      }
    }
  }

  /// Загрузка аватара в Supabase Storage
  Future<String?> _uploadAvatar() async {
    if (_selectedImage == null) return _avatarUrl;
    
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return null;

      final fileName = 'avatars/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      final fileBytes = await _selectedImage!.readAsBytes();
      
      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(fileName, fileBytes, fileOptions: const FileOptions(upsert: true));

      final publicUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      print('❌ Ошибка загрузки аватара: $e');
      return null;
    }
  }

  /// Сохранение изменений
  Future<void> _saveProfile() async {
    if (_usernameController.text.trim().isEmpty || 
        _loginController.text.trim().isEmpty) {
      _showSnackBar('Заполните все поля', Colors.redAccent);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Пользователь не авторизован');

      // 1️⃣ Загружаем аватар если выбран новый
      String? newAvatarUrl = _avatarUrl;
      if (_selectedImage != null) {
        newAvatarUrl = await _uploadAvatar();
        if (newAvatarUrl == null) {
          throw Exception('Не удалось загрузить аватар');
        }
      }

      // 2️⃣ Обновляем данные в public."User"
      final updateData = {
        'username': _usernameController.text.trim(),
        'login': _loginController.text.trim(),
        if (newAvatarUrl != null) 'avatar': newAvatarUrl,
      };

      final response = await Supabase.instance.client
          .from('User')
          .update(updateData)
          .eq('id', userId)
          .select()
          .single();

      // 3️⃣ Опционально: обновляем метаданные в auth.users
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {
          'username': _usernameController.text.trim(),
          'avatar': newAvatarUrl ?? _avatarUrl,
        }),
      );

      if (mounted) {
        _showSnackBar('✅ Профиль обновлён', Colors.green);
        Navigator.pop(context, response); // Возвращаем обновлённые данные
      }
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        _showSnackBar('❌ Такой логин или email уже занят', Colors.redAccent);
      } else {
        _showSnackBar('❌ Ошибка: ${e.message}', Colors.redAccent);
      }
    } catch (e) {
      _showSnackBar('❌ Ошибка: $e', Colors.redAccent);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Редактировать профиль',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveProfile,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Сохранить',
                    style: TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // 👤 Аватар
            GestureDetector(
              onTap: _pickImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: const Color(0xFF7C3AED),
                    child: _selectedImage != null
                        ? ClipOval(
                            child: Image.file(
                              _selectedImage!,
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                          )
                        : _avatarUrl != null && _avatarUrl!.isNotEmpty
                            ? ClipOval(
                                child: Image.network(
                                  _avatarUrl!,
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => 
                                      const Text("😎", style: TextStyle(fontSize: 40)),
                                ),
                              )
                            : const Text("😎", style: TextStyle(fontSize: 40)),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF0F0F1A), width: 3),
                    ),
                    child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Нажмите чтобы изменить',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 40),

            // 📝 Поля ввода
            _buildTextField(_usernameController, 'Имя пользователя', Icons.person),
            const SizedBox(height: 16),
            _buildTextField(_loginController, 'Логин', Icons.alternate_email),
            const SizedBox(height: 16),
            
            // Email (только просмотр)
            _buildReadOnlyField(_emailController.text, 'Email', Icons.email),
            
            const SizedBox(height: 32),

            // ℹ️ Подсказка
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Логин и email должны быть уникальными. Для смены пароля используйте "Забыли пароль" на странице входа.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFF7C3AED),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[600]),
        prefixIcon: Icon(icon, color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF1A1A2E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 2),
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(String value, String label, IconData icon) {
    return AbsorbPointer(
      child: TextField(
        controller: TextEditingController(text: value),
        style: TextStyle(color: Colors.grey[600]),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey[700]),
          prefixIcon: Icon(icon, color: Colors.grey[700]),
          filled: true,
          fillColor: const Color(0xFF151525),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}