import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_player/video_player.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String chatName;

  const ChatScreen({
    Key? key,
    required this.chatId,
    required this.chatName,
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final currentUser = FirebaseAuth.instance.currentUser;
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;

  // Reaksiyon emojileri
  final List<String> reactions = ['👍', '❤️', '😂', '😮', '😢', '😡'];

  // Reaksiyon ekleme fonksiyonu
  Future<void> _addReaction(String messageId, String reaction) async {
    try {
      final messageRef = FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .collection('messages')
          .doc(messageId);

      // Mevcut reaksiyonları al
      final messageDoc = await messageRef.get();
      Map<String, dynamic> reactions = {};
      
      // Mevcut reaksiyonları güvenli bir şekilde dönüştür
      if (messageDoc.data()?['reactions'] != null) {
        reactions = Map<String, dynamic>.from(messageDoc.data()!['reactions'] as Map);
      }

      // Kullanıcının önceki reaksiyonunu kontrol et
      String? userPreviousReaction;
      reactions.forEach((emoji, users) {
        if ((users as List).contains(currentUser?.uid)) {
          userPreviousReaction = emoji;
        }
      });

      // Eğer aynı reaksiyonu tekrar seçtiyse, reaksiyonu kaldır
      if (userPreviousReaction == reaction) {
        final List<String> updatedUsers = List<String>.from(reactions[reaction] as List)
            .where((uid) => uid != currentUser?.uid)
            .toList();
            
        if (updatedUsers.isEmpty) {
          reactions.remove(reaction);
        } else {
          reactions[reaction] = updatedUsers;
        }
      } else {
        // Önceki reaksiyonu kaldır
        if (userPreviousReaction != null) {
          final List<String> previousUsers = List<String>.from(reactions[userPreviousReaction!] as List)
              .where((uid) => uid != currentUser?.uid)
              .toList();
              
          if (previousUsers.isEmpty) {
            reactions.remove(userPreviousReaction);
          } else {
            reactions[userPreviousReaction!] = previousUsers;
          }
        }
        
        // Yeni reaksiyonu ekle
        if (!reactions.containsKey(reaction)) {
          reactions[reaction] = <String>[];
        }
        final List<String> users = List<String>.from(reactions[reaction] as List? ?? []);
        users.add(currentUser!.uid);
        reactions[reaction] = users;
      }

      // Reaksiyonları güncelle
      await messageRef.update({'reactions': reactions});
      
      print('Reaksiyonlar güncellendi: $reactions'); // Debug için
    } catch (e) {
      print('Reaksiyon ekleme hatası: $e');
      print(e.toString()); // Detaylı hata mesajı
    }
  }

  // Reaksiyon seçme diyaloğu
  void _showReactionPicker(String messageId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.all(16),
        content: Wrap(
          spacing: 8,
          children: reactions.map((emoji) => GestureDetector(
            onTap: () {
              Navigator.pop(context);
              _addReaction(messageId, emoji);
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 24),
              ),
            ),
          )).toList(),
        ),
      ),
    );
  }

  // Reaksiyonları gösteren widget
  Widget _buildReactions(Map<String, dynamic>? reactions) {
    if (reactions == null || reactions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: reactions.entries.map((entry) {
          final emoji = entry.key;
          final users = entry.value as List;
          final count = users.length;
          final hasReacted = users.contains(currentUser?.uid);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: hasReacted 
                ? const Color(0xFF2C5364).withOpacity(0.2) 
                : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hasReacted 
                  ? const Color(0xFF2C5364).withOpacity(0.3) 
                  : Colors.grey.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  emoji,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 4),
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: hasReacted 
                      ? const Color(0xFF2C5364) 
                      : Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .collection('messages')
          .add({
        'content': _messageController.text.trim(),
        'senderID': currentUser?.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'messageType': 'text',
      });

      // Update last message in chat document
      await FirebaseFirestore.instance.collection('chat').doc(widget.chatId).update({
        'lastMessage': _messageController.text.trim(),
        'lastMessageTime': FieldValue.serverTimestamp(),
      });

      _messageController.clear();
    } catch (e) {
      print('Mesaj gönderme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mesaj gönderilemedi')),
      );
    }
  }

  // Medya seçme ve gönderme fonksiyonu
  Future<void> _pickAndSendMedia(ImageSource source, bool isVideo) async {
    try {
      setState(() => _isUploading = true);

      final XFile? file = isVideo
          ? await _picker.pickVideo(source: source)
          : await _picker.pickImage(source: source);

      if (file == null) {
        setState(() => _isUploading = false);
        return;
      }

      String? mediaUrl;
      String messageType;
      
      if (isVideo) {
        // Video sıkıştırma
        final MediaInfo? compressedVideo = await VideoCompress.compressVideo(
          file.path,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
        );
        
        if (compressedVideo?.file == null) throw 'Video sıkıştırılamadı';
        
        // Sıkıştırılmış videoyu yükle
        mediaUrl = await _uploadFile(File(compressedVideo!.file!.path), 'videos');
        messageType = 'video';
      } else {
        // Resmi sıkıştır ve JPEG'e dönüştür
        final File compressedImage = await _compressImage(File(file.path));
        
        // Sıkıştırılmış resmi yükle
        mediaUrl = await _uploadFile(compressedImage, 'images');
        messageType = 'image';
      }

      if (mediaUrl != null) {
        // Mesajı veritabanına kaydet
        await FirebaseFirestore.instance
            .collection('chat')
            .doc(widget.chatId)
            .collection('messages')
            .add({
          'content': mediaUrl,
          'senderID': FirebaseAuth.instance.currentUser?.uid,
          'timestamp': FieldValue.serverTimestamp(),
          'messageType': messageType,
        });

        print('Medya mesajı başarıyla kaydedildi');
      } else {
        throw 'Medya yüklenemedi';
      }
    } catch (e) {
      print('Medya gönderme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Medya gönderilemedi: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  // Resim sıkıştırma fonksiyonu
  Future<File> _compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath = path.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}.jpg');
    
    final result = await FlutterImageCompress.compressAndGetFile(
      file.path,
      targetPath,
      quality: 70,
      format: CompressFormat.jpeg,
    );
    
    return File(result?.path ?? file.path);
  }

  // Dosya yükleme fonksiyonu
  Future<String?> _uploadFile(File file, String folder) async {
    try {
      // Storage referansını oluştur
      final storageRef = FirebaseStorage.instance.ref();
      
      // Dosya adını oluştur
      final fileName = '${DateTime.now().millisecondsSinceEpoch}${path.extension(file.path)}';
      
      // Doğrudan dosya referansını oluştur
      final fileRef = storageRef.child('$folder/$fileName');
      
      print('Dosya yükleniyor: $folder/$fileName');
      
      // Metadata oluştur
      final metadata = SettableMetadata(
        contentType: folder == 'images' ? 'image/jpeg' : 'video/mp4',
        customMetadata: {
          'uploaded': DateTime.now().toIso8601String(),
          'originalName': path.basename(file.path),
        },
      );

      // Dosyayı yükle
      final uploadTask = await fileRef.putFile(file, metadata);
      
      if (uploadTask.state == TaskState.success) {
        // Dosyanın URL'sini al
        final downloadUrl = await fileRef.getDownloadURL();
        print('Dosya başarıyla yüklendi. URL: $downloadUrl');
        return downloadUrl;
      } else {
        throw 'Dosya yükleme başarısız: ${uploadTask.state}';
      }
    } on FirebaseException catch (e) {
      print('Firebase Storage hatası: ${e.code} - ${e.message}');
      print('Stack trace: ${StackTrace.current}');
      
      // Kullanıcıya daha anlaşılır bir hata mesajı göster
      String errorMessage = 'Dosya yüklenemedi';
      switch (e.code) {
        case 'object-not-found':
          errorMessage = 'Depolama konumu bulunamadı';
          break;
        case 'unauthorized':
          errorMessage = 'Yükleme için yetkiniz yok';
          break;
        case 'canceled':
          errorMessage = 'Yükleme iptal edildi';
          break;
        default:
          errorMessage = 'Bir hata oluştu: ${e.message}';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
      
      rethrow;
    } catch (e) {
      print('Yükleme hatası: $e');
      print('Stack trace: ${StackTrace.current}');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dosya yüklenirken bir hata oluştu: $e')),
      );
      
      rethrow;
    }
  }

  // Medya seçme dialog'u
  void _showMediaPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Kamera ile Fotoğraf Çek'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendMedia(ImageSource.camera, false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeriden Fotoğraf Seç'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendMedia(ImageSource.gallery, false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Kamera ile Video Çek'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendMedia(ImageSource.camera, true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Galeriden Video Seç'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendMedia(ImageSource.gallery, true);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Tam ekran resim görüntüleme
  void _showFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
              ),
            ),
          ),
          backgroundColor: Colors.black,
        ),
      ),
    );
  }

  // Video önizleme widget'ı
  Widget _buildVideoThumbnail(String videoUrl) {
    return GestureDetector(
      onTap: () => _playVideo(context, videoUrl),
      child: Container(
        width: 200,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.play_circle_fill,
              size: 48,
              color: Colors.white,
            ),
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.videocam,
                      color: Colors.white,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Video',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Video oynatma ekranı
  void _playVideo(BuildContext context, String videoUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _VideoPlayerScreen(videoUrl: videoUrl),
      ),
    );
  }

  // Yeni üye ekleme fonksiyonu
  Future<void> _addNewMembers() async {
    final TextEditingController emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Üye Ekle'),
          content: TextField(
            controller: emailController,
            decoration: const InputDecoration(
              labelText: 'Kullanıcı E-posta',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () async {
                final email = emailController.text.trim();
                if (email.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('E-posta adresi gerekli')),
                  );
                  return;
                }

                try {
                  // Kullanıcıyı bul
                  final userQuery = await FirebaseFirestore.instance
                      .collection('users')
                      .where('email', isEqualTo: email)
                      .get();

                  if (userQuery.docs.isEmpty) {
                    throw 'Kullanıcı bulunamadı';
                  }

                  // Kullanıcının zaten üye olup olmadığını kontrol et
                  final memberQuery = await FirebaseFirestore.instance
                      .collection('chat')
                      .doc(widget.chatId)
                      .collection('groupMember')
                      .where('userID', isEqualTo: userQuery.docs.first.id)
                      .get();

                  if (memberQuery.docs.isNotEmpty) {
                    throw 'Kullanıcı zaten üye';
                  }

                  // Yeni üyeyi ekle
                  await FirebaseFirestore.instance
                      .collection('chat')
                      .doc(widget.chatId)
                      .collection('groupMember')
                      .add({
                    'userID': userQuery.docs.first.id,
                    'addedAt': FieldValue.serverTimestamp(),
                    'addedBy': currentUser?.uid,
                  });

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Üye başarıyla eklendi')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              },
              child: const Text('Ekle'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chatName),
        actions: [
          // Grup sohbeti kontrolü ve üye ekleme butonu
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('chat')
                .doc(widget.chatId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasData && 
                  snapshot.data!.exists && 
                  (snapshot.data!.data() as Map<String, dynamic>)['isGroup'] == true) {
                return IconButton(
                  icon: const Icon(Icons.person_add),
                  onPressed: _addNewMembers,
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chat')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Bir hata oluştu: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Henüz mesaj yok'));
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(8.0),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final message = snapshot.data!.docs[index];
                    final messageData = message.data() as Map<String, dynamic>;
                    final isMyMessage = messageData['senderID'] == currentUser?.uid;
                    final messageType = messageData['messageType'] as String? ?? 'text';

                    Widget messageContent;
                    switch (messageType) {
                      case 'image':
                        messageContent = GestureDetector(
                          onTap: () => _showFullScreenImage(context, messageData['content']),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              messageData['content'],
                              width: 200,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const Center(child: CircularProgressIndicator());
                              },
                            ),
                          ),
                        );
                        break;
                      case 'video':
                        messageContent = _buildVideoThumbnail(messageData['content']);
                        break;
                      default:
                        messageContent = Text(
                          messageData['content'],
                          style: TextStyle(
                            color: isMyMessage ? Colors.white : Colors.black,
                          ),
                        );
                    }

                    return GestureDetector(
                      onLongPress: () => _showReactionPicker(message.id),
                      child: Align(
                        alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isMyMessage ? const Color(0xFF203A43) : Colors.grey[300],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              messageContent,
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    messageData['timestamp'] != null
                                        ? DateFormat('HH:mm').format(
                                            (messageData['timestamp'] as Timestamp).toDate())
                                        : '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isMyMessage ? Colors.white70 : Colors.black54,
                                    ),
                                  ),
                                  if (messageData['reactions'] != null) ...[
                                    Container(
                                      height: 16,
                                      margin: const EdgeInsets.symmetric(horizontal: 8),
                                      width: 1,
                                      color: isMyMessage ? Colors.white30 : Colors.black12,
                                    ),
                                    _buildReactions(messageData['reactions']),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _isUploading ? null : _showMediaPicker,
                  color: const Color(0xFF2C5364),
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: _isUploading ? 'Yükleniyor...' : 'Mesajınızı yazın...',
                      border: const OutlineInputBorder(),
                    ),
                    enabled: !_isUploading,
                    maxLines: null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isUploading ? null : _sendMessage,
                  color: const Color(0xFF2C5364),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Video oynatıcı ekranı
class _VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;

  const _VideoPlayerScreen({required this.videoUrl});

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
        });
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _controller.value.isPlaying
                              ? _controller.pause()
                              : _controller.play();
                        });
                      },
                      child: Container(
                        color: Colors.transparent,
                        child: Center(
                          child: Icon(
                            _controller.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.white.withOpacity(0.7),
                            size: 64.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
