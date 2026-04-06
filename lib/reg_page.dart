import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database/service.dart';
import 'auth_page.dart';
import 'home.dart';

class RegPage extends StatefulWidget {
  const RegPage({super.key});

  @override
  State<RegPage> createState() => _RegPageState();
}

class _RegPageState extends State<RegPage> {
  final emailController = TextEditingController();
  final passController = TextEditingController();
  final repeatPassController = TextEditingController();
  final usernameController = TextEditingController();
  final loginController = TextEditingController(); // ✅ Добавлен контроллер для login
  
  final AuthServices authService = AuthServices();
  bool _isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passController.dispose();
    repeatPassController.dispose();
    usernameController.dispose();
    loginController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '🚀 Регистрация',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 40),

              _buildTextField(loginController, 'Логин', Icons.person_outline),
              const SizedBox(height: 16),
              _buildTextField(usernameController, 'Имя пользователя', Icons.person),
              const SizedBox(height: 16),
              _buildTextField(emailController, 'Email', Icons.email),
              const SizedBox(height: 16),
              _buildTextField(passController, 'Пароль', Icons.lock, obscureText: true),
              const SizedBox(height: 16),
              _buildTextField(repeatPassController, 'Повторите пароль', Icons.lock, obscureText: true),
              const SizedBox(height: 32),

              SizedBox(
                height: 52,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Зарегистрироваться',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Уже есть аккаунт? ", style: TextStyle(color: Colors.grey)),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Войти", style: TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool obscureText = false}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFF7C3AED),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
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

  Future<void> _register() async {
    // Валидация
    if (loginController.text.isEmpty || usernameController.text.isEmpty || 
        emailController.text.isEmpty || passController.text.isEmpty || 
        repeatPassController.text.isEmpty) {
      _showSnackBar("Заполните все поля!", Colors.redAccent);
      return;
    }

    if (passController.text != repeatPassController.text) {
      _showSnackBar("Пароли не совпадают!", Colors.redAccent);
      return;
    }

    if (passController.text.length < 6) {
      _showSnackBar("Пароль должен быть не менее 6 символов", Colors.redAccent);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ✅ ИСПРАВЛЕНО: signUp вместо singUp + добавлен параметр login
      final user = await authService.signUp(
        email: emailController.text.trim(),
        password: passController.text,
        login: loginController.text.trim(), // ✅ Передаём login
        username: usernameController.text.trim(),
      );

      if (user != null && mounted) {
        debugPrint('✅ Регистрация успешна: ${user.email}');
        
        // 🔔 Если включено подтверждение email — отключите в Supabase Dashboard:
        // Authentication → Providers → Email → Disable "Confirm email"
        
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      } else if (mounted) {
        _showSnackBar("Ошибка регистрации", Colors.redAccent);
      }
    } on AuthException catch (e) {
      if (mounted) {
        String message = e.message;
        if (message.contains('User already registered')) {
          message = 'Пользователь с таким email уже существует';
        } else if (message.contains('Weak password')) {
          message = 'Слишком слабый пароль';
        }
        _showSnackBar(message, Colors.redAccent);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar("Ошибка: $e", Colors.redAccent);
      }
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
}