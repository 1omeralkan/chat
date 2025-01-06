import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreateChatScreen extends StatefulWidget {
  const CreateChatScreen({Key? key}) : super(key: key);

  @override
  _CreateChatScreenState createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends State<CreateChatScreen> {
  final TextEditingController chatNameController = TextEditingController();
  final List<TextEditingController> emailControllers = [TextEditingController()];
  bool isGroup = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Yeni Sohbet'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: chatNameController,
              decoration: const InputDecoration(
                labelText: 'Sohbet Adı',
              ),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              title: const Text('Grup Sohbeti'),
              value: isGroup,
              onChanged: (value) {
                setState(() {
                  isGroup = value ?? false;
                });
              },
            ),
            const SizedBox(height: 10),
            ...List.generate(emailControllers.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: emailControllers[index],
                        decoration: InputDecoration(
                          labelText: 'Kullanıcı ${index + 1} E-posta',
                        ),
                        onChanged: (value) {
                          if (isGroup && 
                              index == emailControllers.length - 1 && 
                              value.isNotEmpty) {
                            setState(() {
                              emailControllers.add(TextEditingController());
                            });
                          }
                        },
                      ),
                    ),
                    if (isGroup && index > 0)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          setState(() {
                            emailControllers.removeAt(index);
                          });
                        },
                        color: Colors.red,
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        TextButton(
          onPressed: () => _createChat(context),
          child: const Text('Oluştur'),
        ),
      ],
    );
  }

  Future<void> _createChat(BuildContext context) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // Boş email controller'ları kaldır
    final validEmailControllers = emailControllers
        .where((controller) => controller.text.trim().isNotEmpty)
        .toList();

    if (validEmailControllers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az bir kullanıcı ekleyin')),
      );
      return;
    }

    // Grup sohbeti için isim kontrolü
    if (isGroup && chatNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grup adı gerekli')),
      );
      return;
    }

    try {
      // Kullanıcıları bul
      List<String> memberIds = [];
      for (var controller in validEmailControllers) {
        final email = controller.text.trim();
        final userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: email)
            .get();

        if (userQuery.docs.isEmpty) {
          throw 'Kullanıcı bulunamadı: $email';
        }
        memberIds.add(userQuery.docs.first.id);
      }

      // Sohbet oluştur
      final chatRef = await FirebaseFirestore.instance
          .collection('chat')
          .add({
        'name': isGroup ? chatNameController.text.trim() : '',
        'isGroup': isGroup,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': currentUser.uid,
      });

      // Üyeleri ekle
      memberIds.add(currentUser.uid); // Kendini de ekle
      for (String userId in memberIds) {
        await chatRef.collection('groupMember').add({
          'userID': userId,
          'addedAt': FieldValue.serverTimestamp(),
          'addedBy': currentUser.uid,
        });
      }

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  void dispose() {
    chatNameController.dispose();
    for (var controller in emailControllers) {
      controller.dispose();
    }
    super.dispose();
  }
} 