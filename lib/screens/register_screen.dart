import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _register() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        print('Kayıt işlemi başlıyor...');

        // 1. Authentication'da kullanıcı oluştur
        final userCredential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        print('Auth kullanıcısı oluşturuldu: ${userCredential.user?.uid}');
        print('Email: ${userCredential.user?.email}');

        // 2. Firestore'da users koleksiyonunu oluştur
        try {
          print('Firestore kaydı başlıyor...');

          final userDoc = FirebaseFirestore.instance
              .collection('users')
              .doc(userCredential.user!.uid);

          await userDoc.set({
            'username': _nameController.text.trim(),
            'email': _emailController.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
            'lastLoginAt': FieldValue.serverTimestamp(),
            'isOnline': true,
            'photoURL': null,
            'bio': '',
          });

          print('Firestore kullanıcı dokümanı oluşturuldu');
          print('Koleksiyon: users/${userCredential.user!.uid}');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Kayıt başarılı! Giriş yapabilirsiniz.'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context);
          }
        } catch (firestoreError) {
          print('Firestore hatası: $firestoreError');
          // Firestore hatası durumunda Authentication'daki kullanıcıyı sil
          await userCredential.user?.delete();
          throw Exception('Kullanıcı bilgileri kaydedilemedi: $firestoreError');
        }
      } on FirebaseAuthException catch (e) {
        print('Firebase Auth hatası: ${e.code} - ${e.message}');
        String errorMessage;
        switch (e.code) {
          case 'weak-password':
            errorMessage = 'Şifre çok zayıf';
            break;
          case 'email-already-in-use':
            errorMessage = 'Bu e-posta adresi zaten kullanımda';
            break;
          case 'invalid-email':
            errorMessage = 'Geçersiz e-posta adresi';
            break;
          default:
            errorMessage = e.message ?? 'Bir hata oluştu';
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        print('Beklenmeyen hata: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Beklenmeyen hata: $e'),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kayıt Ol')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Kullanıcı Adı',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Lütfen kullanıcı adınızı girin';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Lütfen e-posta adresinizi girin';
                    }
                    if (!value.contains('@')) {
                      return 'Geçerli bir e-posta adresi girin';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Şifre',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Lütfen şifrenizi girin';
                    }
                    if (value.length < 6) {
                      return 'Şifre en az 6 karakter olmalıdır';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : const Text('Kayıt Ol'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
