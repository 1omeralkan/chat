import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Basit Firebase başlatma
  await Firebase.initializeApp();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sohbet Uygulaması',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const LoginScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/chat': (context) => const ChatListScreen(),
      },
    );
  }
}

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  Future<void> _createNewChat(BuildContext context) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final TextEditingController chatNameController = TextEditingController();
    final TextEditingController emailController = TextEditingController();
    bool isGroup = false;
    QueryDocumentSnapshot? otherUserDoc;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Yeni Sohbet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Grup Sohbeti'),
                subtitle: const Text('Birden fazla katılımcı eklenebilir'),
                value: isGroup,
                onChanged: (value) {
                  setState(() => isGroup = value);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: chatNameController,
                decoration: const InputDecoration(
                  labelText: 'Sohbet Adı',
                  border: OutlineInputBorder(),
                  hintText: 'Sohbet için bir isim girin',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Karşı Kullanıcının E-postası',
                  border: OutlineInputBorder(),
                  hintText: 'ornek@email.com',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final chatName = chatNameController.text.trim();
                if (chatName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sohbet adı boş olamaz')),
                  );
                  return;
                }

                if (!isGroup) {
                  final email = emailController.text.trim();
                  if (email.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('E-posta adresi boş olamaz')),
                    );
                    return;
                  }

                  print('Aranan e-posta: ${email.toLowerCase()}');
                  
                  // Tüm kullanıcıları listele
                  final allUsers = await FirebaseFirestore.instance
                      .collection('users')
                      .get();
                      
                  print('Veritabanındaki tüm kullanıcılar:');
                  for (var doc in allUsers.docs) {
                    print('Email: ${doc.data()['email']}, ID: ${doc.id}');
                  }

                  // Kullanıcıyı e-posta ile ara
                  final userQuery = await FirebaseFirestore.instance
                      .collection('users')
                      .where('email', isEqualTo: email.toLowerCase())
                      .get();

                  if (userQuery.docs.isEmpty) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Kullanıcı bulunamadı'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }

                  otherUserDoc = userQuery.docs.first;

                  if (otherUserDoc?.id == null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Kullanıcı bilgisi alınamadı'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }

                  // Mevcut sohbeti kontrol et
                  final existingChatQuery = await FirebaseFirestore.instance
                      .collection('chat')
                      .where('isGroup', isEqualTo: false)
                      .where('members', arrayContainsAny: [
                    currentUser.uid,
                    otherUserDoc?.id
                  ]).get();

                  for (var doc in existingChatQuery.docs) {
                    final members = List<String>.from(doc['members']);
                    if (members.contains(currentUser.uid) &&
                        members.contains(otherUserDoc?.id)) {
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Bu kullanıcı ile zaten bir sohbetiniz var'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                      return;
                    }
                  }
                }

                try {
                  if (!isGroup && otherUserDoc?.id == null) {
                    throw Exception('Kullanıcı bilgisi eksik');
                  }

                  // Yeni sohbet oluştur
                  final docRef =
                      await FirebaseFirestore.instance.collection('chat').add({
                    'chatName': chatNameController.text.trim(),
                    'createdAt': FieldValue.serverTimestamp(),
                    'isGroup': isGroup,
                    'createdBy': currentUser.uid,
                    'lastMessage': null,
                    'lastMessageTime': null,
                    if (!isGroup)
                      'members': [currentUser.uid, otherUserDoc!.id],
                  });

                  // Grup üyeleri koleksiyonunu oluştur
                  await docRef.collection('groupMember').add({
                    'userID': currentUser.uid,
                    'joinedAt': FieldValue.serverTimestamp(),
                    'isAdmin': true,
                  });

                  if (!isGroup) {
                    // Karşı kullanıcıyı ekle
                    await docRef.collection('groupMember').add({
                      'userID': otherUserDoc!.id,
                      'joinedAt': FieldValue.serverTimestamp(),
                      'isAdmin': false,
                    });
                  }

                  // Mesajlar koleksiyonunu oluştur
                  await docRef.collection('messages').add({
                    'content': isGroup
                        ? '${currentUser.email} grubu oluşturdu'
                        : 'Sohbet başlatıldı',
                    'senderID': 'system',
                    'timestamp': FieldValue.serverTimestamp(),
                    'messageType': 'system',
                  });

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            isGroup ? 'Grup oluşturuldu' : 'Sohbet başlatıldı'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Hata: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Oluştur'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sohbetler'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: currentUser == null
          ? const Center(child: Text('Giriş yapılmadı'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chat')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Bir hata oluştu: ${snapshot.error}'),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Henüz sohbet bulunmuyor'));
                }

                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final chat = snapshot.data!.docs[index];
                    String createdAtText;

                    try {
                      final createdAt = chat['createdAt'];
                      if (createdAt is Timestamp) {
                        createdAtText = createdAt.toDate().toString();
                      } else if (createdAt == null) {
                        createdAtText = 'Belirsiz';
                      } else {
                        createdAtText = createdAt.toString();
                      }
                    } catch (e) {
                      createdAtText = 'Belirsiz';
                    }

                    // Sohbet adını güvenli bir şekilde al
                    final chatName =
                        (chat['chatName'] as String?) ?? 'İsimsiz Sohbet';
                    final firstLetter =
                        chatName.isNotEmpty ? chatName[0].toUpperCase() : '?';

                    return ListTile(
                      title: Text(chatName),
                      subtitle: Text('Oluşturulma: $createdAtText'),
                      leading: CircleAvatar(
                        child: Text(firstLetter),
                      ),
                      trailing: chat['isGroup']
                          ? const Icon(Icons.group)
                          : const Icon(Icons.person),
                      onTap: () {
                        // TODO: Sohbet detay sayfasına yönlendirme
                      },
                    );
                  },
                );
              },
            ),
      floatingActionButton: currentUser == null
          ? null
          : FloatingActionButton(
              onPressed: () => _createNewChat(context),
              child: const Icon(Icons.add),
            ),
    );
  }
}
