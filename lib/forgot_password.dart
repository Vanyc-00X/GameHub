import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database/services/userservice.dart';

class RecoveryPage extends StatefulWidget {
  const RecoveryPage({super.key});

  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<RecoveryPage> {
  final _emailController = TextEditingController();
  final _userService = UserService();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _showMessage(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _showMessage('Введите email');
      return;
    }

    if (!email.contains('@') || !email.contains('.')) {
      _showMessage('Введите корректный email');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _userService.resetPassword(email);
      _showMessage('Письмо для восстановления отправлено на $email');
      _emailController.clear();
    } on AuthException catch (e) {
      String errorMsg = 'Ошибка: ${e.message}';
      if (e.message.contains('User not found')) {
        errorMsg = 'Пользователь с таким email не найден';
      } else if (e.message.contains('Email not confirmed')) {
        errorMsg = 'Email не подтверждён';
      }
      _showMessage(errorMsg);
    } catch (e) {
      _showMessage('Произошла ошибка. Попробуйте позже.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.1),
            Image.asset(
              'assets/images/logo.png',
              height: MediaQuery.of(context).size.height * 0.3,
              width: MediaQuery.of(context).size.width * 0.45,
            ),
            const SizedBox(height: 40),

            const Text(
              'Восстановление пароля',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Введите ваш email, и мы отправим инструкцию по восстановлению пароля',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 40),

            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              cursorColor: Colors.black,
              style: const TextStyle(color: Colors.orange),
              decoration: InputDecoration(
                labelText: 'Email',
                hintText: 'Введите email',
                prefixIcon: const Icon(Icons.email),
                labelStyle: const TextStyle(color: Colors.black),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: const BorderSide(color: Colors.blue),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: const BorderSide(color: Colors.black26),
                ),
              ),
            ),
            const SizedBox(height: 40),

            SizedBox(
              height: MediaQuery.of(context).size.height * 0.055,
              width: MediaQuery.of(context).size.width * 0.8,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: _isLoading ? null : _resetPassword,
                child: Text(
                  _isLoading ? 'Отправка...' : 'Восстановить пароль',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Назад', style: TextStyle(color: Colors.blue, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}