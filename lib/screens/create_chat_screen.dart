import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreateChatScreen extends StatefulWidget {
  const CreateChatScreen({super.key});

  @override
  State<CreateChatScreen> createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends State<CreateChatScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _chatNameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _createChat() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final searchEmail = _emailController.text.trim().toLowerCase();
      print('Aranan e-posta: $searchEmail');

      // Kullanıcıyı e-posta ile ara - doğrudan dökümanları kontrol edelim
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();
      
      // Dökümanları manuel olarak kontrol edelim
      QueryDocumentSnapshot? foundUser;
      for (var doc in usersSnapshot.docs) {
        final userData = doc.data() as Map<String, dynamic>;
        if (userData['email']?.toString().toLowerCase() == searchEmail) {
          foundUser = doc;
          break;
        }
      }

      if (foundUser == null) {
        setState(() {
          _errorMessage = 'Kullanıcı bulunamadı. Lütfen e-posta adresini kontrol edin.';
          _isLoading = false;
        });
        return;
      }

      final currentUser = FirebaseAuth.instance.currentUser!;

      // Kendi kendine sohbet oluşturmayı engelle
      if (foundUser.id == currentUser.uid) {
        setState(() {
          _errorMessage = 'Kendinizle sohbet oluşturamazsınız';
          _isLoading = false;
        });
        return;
      }

      // Sohbet adını al
      String chatName = _chatNameController.text.trim();

      // Mevcut sohbet var mı kontrol et
      final existingChatQuery = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: currentUser.uid)
          .get();

      for (var doc in existingChatQuery.docs) {
        List<dynamic> participants = doc.data()['participants'] ?? [];
        if (participants.contains(foundUser.id)) {
          setState(() {
            _errorMessage = 'Bu kullanıcı ile zaten bir sohbetiniz var';
            _isLoading = false;
          });
          return;
        }
      }

      // Yeni sohbet oluştur
      final chatRef = await FirebaseFirestore.instance.collection('chats').add({
        'name': chatName,
        'participants': [currentUser.uid, foundUser.id],
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'lastMessageTime': null,
        'participantDetails': {
          currentUser.uid: {
            'email': currentUser.email,
            'displayName': currentUser.displayName ?? 'İsimsiz Kullanıcı',
          },
          foundUser.id: {
            'email': foundUser.data()['email'],
            'displayName': foundUser.data()['displayName'] ?? 'İsimsiz Kullanıcı',
          },
        },
      });

      if (mounted) {
        Navigator.pop(context, chatRef.id);
      }
    } catch (e) {
      print('Hata oluştu: $e');
      setState(() {
        _errorMessage = 'Bir hata oluştu: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Sohbet Oluştur'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _chatNameController,
                decoration: const InputDecoration(
                  labelText: 'Sohbet Adı',
                  hintText: 'Sohbet için bir isim girin',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Lütfen sohbet için bir isim girin';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Kullanıcı E-postası',
                  hintText: 'Örnek: kullanici@email.com',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Lütfen bir e-posta adresi girin';
                  }
                  if (!value.contains('@')) {
                    return 'Geçerli bir e-posta adresi girin';
                  }
                  return null;
                },
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _createChat,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Sohbet Oluştur'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _chatNameController.dispose();
    super.dispose();
  }
} 