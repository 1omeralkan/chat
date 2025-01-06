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
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_player/video_player.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';

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
  late final AudioRecorder _audioRecorder;
  final _audioPlayer = AudioPlayer();
  bool _isUploading = false;
  bool _isRecording = false;
  String? _recordingPath;
  Timer? _recordingTimer;
  int _recordingDuration = 0;
  bool _isPlaying = false;
  String? _currentlyPlayingUrl;
  bool _isAdmin = false;

  // Reaksiyon emojileri
  final List<String> reactions = ['👍', '❤️', '😂', '😮', '😢', '😡'];

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _checkAdminStatus();
  }

  // Admin durumunu kontrol et
  Future<void> _checkAdminStatus() async {
    if (currentUser == null) return;

    final memberQuery = await FirebaseFirestore.instance
        .collection('chat')
        .doc(widget.chatId)
        .collection('groupMember')
        .where('userID', isEqualTo: currentUser!.uid)
        .get();

    if (memberQuery.docs.isNotEmpty) {
      setState(() {
        _isAdmin = memberQuery.docs.first.data()['isAdmin'] ?? false;
      });
    }
  }

  // Üye yönetimi menüsü
  void _showMemberManagement() async {
    final members = await FirebaseFirestore.instance
        .collection('chat')
        .doc(widget.chatId)
        .collection('groupMember')
        .get();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Üye Yönetimi'),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<QuerySnapshot>(
            future: FirebaseFirestore.instance.collection('users').get(),
            builder: (context, usersSnapshot) {
              if (!usersSnapshot.hasData) {
                return const CircularProgressIndicator();
              }

              return ListView.builder(
                shrinkWrap: true,
                itemCount: members.docs.length,
                itemBuilder: (context, index) {
                  final member = members.docs[index];
                  final userId = member.data()['userID'] as String;
                  final isAdmin = member.data()['isAdmin'] ?? false;
                  
                  // Kullanıcı bilgilerini bul
                  final userDoc = usersSnapshot.data!.docs
                      .firstWhere((doc) => doc.id == userId);
                  final userEmail = (userDoc.data() as Map)['email'] as String;

                  return ListTile(
                    title: Text(userEmail),
                    subtitle: Text(isAdmin ? 'Admin' : 'Üye'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Admin yapma/yetkisini alma butonu
                        if (_isAdmin && userId != currentUser?.uid)
                          IconButton(
                            icon: Icon(
                              isAdmin ? Icons.admin_panel_settings : Icons.admin_panel_settings_outlined,
                              color: isAdmin ? Colors.red : Colors.green,
                            ),
                            onPressed: () => _toggleAdminStatus(member.id, !isAdmin),
                          ),
                        // Üyeyi çıkarma butonu
                        if (_isAdmin && userId != currentUser?.uid)
                          IconButton(
                            icon: const Icon(Icons.remove_circle, color: Colors.red),
                            onPressed: () => _removeMember(member.id),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          if (_isAdmin)
            TextButton(
              onPressed: _addNewMember,
              child: const Text('Yeni Üye Ekle'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  // Admin durumunu değiştir
  Future<void> _toggleAdminStatus(String memberId, bool newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .collection('groupMember')
          .doc(memberId)
          .update({'isAdmin': newStatus});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kullanıcı ${newStatus ? 'admin yapıldı' : 'admin yetkisi alındı'}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Üyeyi çıkar
  Future<void> _removeMember(String memberId) async {
    try {
      await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .collection('groupMember')
          .doc(memberId)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Üye gruptan çıkarıldı'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Yeni üye ekleme fonksiyonu
  Future<void> _addNewMember() async {
    final TextEditingController emailController = TextEditingController();

    try {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Yeni Üye Ekle'),
          content: TextField(
            controller: emailController,
            decoration: const InputDecoration(
              labelText: 'E-posta Adresi',
              hintText: 'ornek@email.com',
            ),
            keyboardType: TextInputType.emailAddress,
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

                // Kullanıcıyı bul
                final userQuery = await FirebaseFirestore.instance
                    .collection('users')
                    .where('email', isEqualTo: email.toLowerCase())
                    .get();

                if (userQuery.docs.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Kullanıcı bulunamadı')),
                    );
                  }
                  return;
                }

                final userId = userQuery.docs.first.id;

                // Kullanıcının zaten üye olup olmadığını kontrol et
                final memberQuery = await FirebaseFirestore.instance
                    .collection('chat')
                    .doc(widget.chatId)
                    .collection('groupMember')
                    .where('userID', isEqualTo: userId)
                    .get();

                if (memberQuery.docs.isNotEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Bu kullanıcı zaten grupta')),
                    );
                  }
                  return;
                }

                // Yeni üyeyi ekle
                await FirebaseFirestore.instance
                    .collection('chat')
                    .doc(widget.chatId)
                    .collection('groupMember')
                    .add({
                  'userID': userId,
                  'addedAt': FieldValue.serverTimestamp(),
                  'addedBy': currentUser?.uid,
                  'isAdmin': false,
                });

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Üye başarıyla eklendi')),
                  );
                }
              },
              child: const Text('Ekle'),
            ),
          ],
        ),
      );
    } finally {
      emailController.dispose();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  // Ses kaydı başlatma fonksiyonu
  Future<void> _startRecording() async {
    try {
      if (await Permission.microphone.request().isGranted) {
        final tempDir = await getTemporaryDirectory();
        _recordingPath = '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: _recordingPath!,
        );

        setState(() {
          _isRecording = true;
          _recordingDuration = 0;
        });

        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _recordingDuration++;
          });
        });
      }
    } catch (e) {
      print('Ses kaydı başlatma hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ses kaydı başlatılamadı: $e')),
      );
    }
  }

  // Ses kaydını durdurma ve gönderme fonksiyonu
  Future<void> _stopRecordingAndSend() async {
    try {
      _recordingTimer?.cancel();
      final path = await _audioRecorder.stop();
      
      setState(() {
        _isRecording = false;
        _recordingDuration = 0;
      });

      if (path != null) {
        final file = File(path);
        final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('audio')
            .child(fileName);

        final uploadTask = storageRef.putFile(
          file,
          SettableMetadata(
            contentType: 'audio/m4a',
            customMetadata: {
              'duration': _recordingDuration.toString(),
            },
          ),
        );

        final snapshot = await uploadTask;
        final downloadUrl = await snapshot.ref.getDownloadURL();

        await FirebaseFirestore.instance
            .collection('chat')
            .doc(widget.chatId)
            .collection('messages')
            .add({
          'content': downloadUrl,
          'senderID': currentUser?.uid,
          'timestamp': FieldValue.serverTimestamp(),
          'messageType': 'audio',
          'duration': _recordingDuration,
        });
      }
    } catch (e) {
      print('Ses kaydı durdurma hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ses kaydı gönderilemedi: $e')),
      );
    }
  }

  // Ses oynatma fonksiyonu
  Future<void> _playAudio(String url) async {
    try {
      if (_isPlaying && _currentlyPlayingUrl == url) {
        // Aynı ses dosyası çalıyorsa durdur
        await _audioPlayer.stop();
        setState(() {
          _isPlaying = false;
          _currentlyPlayingUrl = null;
        });
        return;
      }

      // Başka bir ses dosyası çalıyorsa önce onu durdur
      if (_isPlaying) {
        await _audioPlayer.stop();
      }

      // Yeni ses dosyasını çal
      await _audioPlayer.setSourceUrl(url);  // Önce kaynağı ayarla
      await _audioPlayer.resume();  // Sonra oynatmaya başla

      setState(() {
        _isPlaying = true;
        _currentlyPlayingUrl = url;
      });

      // Ses bittiğinde durumu güncelle
      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _currentlyPlayingUrl = null;
          });
        }
      });

    } catch (e) {
      print('Ses oynatma hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ses oynatılamadı: $e')),
      );
    }
  }

  // Ses mesajı widget'ı
  Widget _buildAudioMessage(Map<String, dynamic> messageData) {
    final duration = messageData['duration'] as int? ?? 0;
    final minutes = (duration / 60).floor();
    final seconds = duration % 60;
    final durationText = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    final url = messageData['content'] as String;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              (_isPlaying && _currentlyPlayingUrl == url) 
                  ? Icons.pause 
                  : Icons.play_arrow
            ),
            onPressed: () => _playAudio(url),
          ),
          Text(durationText),
          if (_isPlaying && _currentlyPlayingUrl == url)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            ),
        ],
      ),
    );
  }

  // Medya seçici fonksiyonu
  Future<void> _showMediaPicker() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Fotoğraf'),
              onTap: () async {
                Navigator.pop(context);
                final image = await _picker.pickImage(source: ImageSource.gallery);
                if (image != null) {
                  await _uploadMedia(File(image.path), 'images');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Video'),
              onTap: () async {
                Navigator.pop(context);
                final video = await _picker.pickVideo(source: ImageSource.gallery);
                if (video != null) {
                  await _uploadMedia(File(video.path), 'videos');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // Medya yükleme fonksiyonu
  Future<void> _uploadMedia(File file, String folder) async {
    try {
      setState(() => _isUploading = true);

      String? downloadUrl;
      String? thumbnailUrl;
      String messageType = folder == 'images' ? 'image' : 'video';

      if (messageType == 'video') {
        // Video sıkıştırma
        final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
          file.path,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
        );

        if (mediaInfo?.file != null) {
          // Thumbnail oluştur
          final thumbnailFile = await VideoCompress.getFileThumbnail(
            file.path,
            quality: 50,
            position: -1,
          );

          // Thumbnail'i yükle
          final thumbnailRef = FirebaseStorage.instance
              .ref()
              .child('thumbnails')
              .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

          final thumbnailUpload = await thumbnailRef.putFile(
            thumbnailFile,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          thumbnailUrl = await thumbnailUpload.ref.getDownloadURL();

          // Videoyu yükle
          final videoRef = FirebaseStorage.instance
              .ref()
              .child(folder)
              .child('${DateTime.now().millisecondsSinceEpoch}.mp4');

          final uploadTask = await videoRef.putFile(
            File(mediaInfo!.file!.path),
            SettableMetadata(contentType: 'video/mp4'),
          );
          downloadUrl = await uploadTask.ref.getDownloadURL();
        }
      } else {
        // Resim sıkıştırma ve yükleme
        final compressedFile = await FlutterImageCompress.compressAndGetFile(
          file.path,
          '${file.path}_compressed.jpg',
          quality: 70,
        );

        if (compressedFile != null) {
          final imageRef = FirebaseStorage.instance
              .ref()
              .child(folder)
              .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

          final uploadTask = await imageRef.putFile(
            File(compressedFile.path),
            SettableMetadata(contentType: 'image/jpeg'),
          );
          downloadUrl = await uploadTask.ref.getDownloadURL();
        }
      }

      if (downloadUrl != null) {
        await FirebaseFirestore.instance
            .collection('chat')
            .doc(widget.chatId)
            .collection('messages')
            .add({
          'content': downloadUrl,
          'thumbnail': thumbnailUrl,
          'senderID': currentUser?.uid,
          'timestamp': FieldValue.serverTimestamp(),
          'messageType': messageType,
        });
      }
    } catch (e) {
      print('Medya yükleme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Medya yüklenemedi: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  // Video thumbnail alma fonksiyonu
  Future<String?> _getThumbnail(String videoUrl) async {
    try {
      final thumbnailFile = await VideoCompress.getFileThumbnail(
        videoUrl,
        quality: 50,
        position: -1,
      );

      final thumbnailRef = FirebaseStorage.instance
          .ref()
          .child('thumbnails')
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      final uploadTask = await thumbnailRef.putFile(
        thumbnailFile,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      return await uploadTask.ref.getDownloadURL();
    } catch (e) {
      print('Thumbnail oluşturma hatası: $e');
      return null;
    }
  }

  // Mesaj gönderme fonksiyonu
  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .collection('messages')
          .add({
        'content': message,
        'senderID': currentUser?.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'messageType': 'text',
      });

      _messageController.clear();
    } catch (e) {
      print('Mesaj gönderme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesaj gönderilemedi: $e')),
      );
    }
  }

  // Profil resmi değiştirme fonksiyonu
  Future<void> _changeGroupPhoto() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
      );

      if (image == null) return;

      setState(() => _isUploading = true);

      // Resmi sıkıştır
      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        image.path,
        '${image.path}_compressed.jpg',
        quality: 70,
      );

      if (compressedFile == null) throw 'Resim sıkıştırılamadı';

      // Storage'a yükle
      final fileName = 'group_${widget.chatId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('group_photos')
          .child(fileName);

      final uploadTask = await storageRef.putFile(
        File(compressedFile.path),
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final downloadUrl = await uploadTask.ref.getDownloadURL();

      // Firestore'u güncelle
      await FirebaseFirestore.instance
          .collection('chat')
          .doc(widget.chatId)
          .update({
        'photoUrl': downloadUrl,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Grup fotoğrafı güncellendi')),
        );
      }
    } catch (e) {
      print('Profil resmi değiştirme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf güncellenemedi: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('chat')
              .doc(widget.chatId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return Text(widget.chatName);

            final data = snapshot.data!.data() as Map<String, dynamic>?;
            final isGroup = data?['isGroup'] ?? false;
            final photoUrl = data?['photoUrl'];

            return Row(
              children: [
                if (isGroup && photoUrl != null)
                  GestureDetector(
                    onTap: _isAdmin ? _changeGroupPhoto : null,
                    child: Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        image: DecorationImage(
                          image: NetworkImage(photoUrl),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  )
                else if (isGroup)
                  GestureDetector(
                    onTap: _isAdmin ? _changeGroupPhoto : null,
                    child: Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey,
                      ),
                      child: const Icon(
                        Icons.group,
                        color: Colors.white,
                      ),
                    ),
                  ),
                Expanded(child: Text(widget.chatName)),
              ],
            );
          },
        ),
        actions: [
          // Grup yönetimi butonu
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('chat')
                .doc(widget.chatId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasData && 
                  snapshot.data!.exists && 
                  (snapshot.data!.data() as Map<String, dynamic>)['isGroup'] == true &&
                  _isAdmin) {
                return IconButton(
                  icon: const Icon(Icons.group_add),
                  onPressed: _showMemberManagement,
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

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                return ListView.builder(
              reverse: true,
                  itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                    final message = snapshot.data!.docs[index];
                    final messageData = message.data() as Map<String, dynamic>;
                    final isMyMessage = messageData['senderID'] == currentUser?.uid;
                    final messageType = messageData['messageType'] as String? ?? 'text';

                    Widget messageContent;
                    switch (messageType) {
                      case 'text':
                        messageContent = Text(
                          messageData['content'],
                          style: TextStyle(
                            color: isMyMessage ? Colors.white : Colors.black,
                          ),
                        );
                        break;
                      case 'image':
                        messageContent = Image.network(
                          messageData['content'],
                          width: 200,
                          fit: BoxFit.cover,
                        );
                        break;
                      case 'video':
                        messageContent = FutureBuilder<String?>(
                          future: _getThumbnail(messageData['content']),
                          builder: (context, snapshot) {
                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => _VideoPlayerScreen(
                                      videoUrl: messageData['content'],
                                      thumbnailUrl: messageData['thumbnail'],
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                width: 200,
                                height: 150,
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    if (messageData['thumbnail'] != null)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          messageData['thumbnail']!,
                                          width: 200,
                                          height: 150,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              color: Colors.grey[800],
                                              child: const Icon(
                                                Icons.video_file,
                                                color: Colors.white54,
                                                size: 50,
                                              ),
                                            );
                                          },
                                        ),
                                      )
                                    else
                                      Container(
                                        color: Colors.grey[800],
                                        child: const Icon(
                                          Icons.video_file,
                                          color: Colors.white54,
                                          size: 50,
                                        ),
                                      ),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.black45,
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      child: const Icon(
                                        Icons.play_circle_fill,
                                        color: Colors.white,
                                        size: 40,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                        break;
                      case 'audio':
                        messageContent = _buildAudioMessage(messageData);
                        break;
                      default:
                        messageContent = Text(messageData['content'] ?? 'Boş mesaj');
                    }

                    return Align(
                      alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              contentPadding: const EdgeInsets.all(16),
                              content: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                children: reactions.map((emoji) {
                                  return InkWell(
                                    onTap: () async {
                                      try {
                                        // Reaksiyonu ekle
                                        await FirebaseFirestore.instance
                                            .collection('chat')
                                            .doc(widget.chatId)
                                            .collection('messages')
                                            .doc(message.id)
                                            .update({
                                          'reactions.${currentUser?.uid}': emoji,
                                        });
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      } catch (e) {
                                        print('Reaksiyon ekleme hatası: $e');
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        emoji,
                                        style: const TextStyle(fontSize: 24),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          );
                        },
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
                                  if (messageData['reactions'] != null)
                                    ...(messageData['reactions'] as Map<String, dynamic>)
                                        .values
                                        .fold<Map<String, int>>(
                                          {},
                                          (map, emoji) {
                                            map[emoji] = (map[emoji] ?? 0) + 1;
                                            return map;
                                          },
                                        )
                                        .entries
                                        .map(
                                          (entry) => Container(
                                            margin: const EdgeInsets.only(left: 4),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.black12,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '${entry.key}${entry.value > 1 ? ' ${entry.value}' : ''}',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                        ),
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
                GestureDetector(
                  onLongPress: _startRecording,
                  onLongPressEnd: (_) => _stopRecordingAndSend(),
                  child: IconButton(
                    icon: Icon(_isRecording ? Icons.mic : Icons.mic_none),
                    color: _isRecording ? Colors.red : const Color(0xFF2C5364),
                    onPressed: null,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _isUploading ? null : _showMediaPicker,
                  color: const Color(0xFF2C5364),
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: _isRecording 
                          ? 'Kayıt yapılıyor... ${_recordingDuration}s'
                          : _isUploading 
                              ? 'Yükleniyor...' 
                              : 'Mesajınızı yazın...',
                      border: const OutlineInputBorder(),
                    ),
                    enabled: !_isUploading && !_isRecording,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isUploading || _isRecording ? null : _sendMessage,
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

// Video oynatıcı widget'ı
class _VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl;

  const _VideoPlayerScreen({
    required this.videoUrl,
    this.thumbnailUrl,
  });

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

// Video oynatıcı state sınıfı
class _VideoPlayerScreenState extends State<_VideoPlayerScreen> with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  late AnimationController _playPauseController;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isBuffering = false;

  @override
  void initState() {
    super.initState();
    _playPauseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      setState(() => _isBuffering = true);
      
      _controller = VideoPlayerController.network(
        widget.videoUrl,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      await _controller.initialize();

      _controller.addListener(_videoListener);

      setState(() {
        _isInitialized = true;
        _isBuffering = false;
      });
    } catch (e) {
      print('Video yükleme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video yüklenemedi: $e')),
        );
      }
      setState(() => _isBuffering = false);
    }
  }

  void _videoListener() {
    if (!mounted) return;
    
    final isPlaying = _controller.value.isPlaying;
    if (isPlaying != _isPlaying) {
      setState(() => _isPlaying = isPlaying);
      isPlaying ? _playPauseController.reverse() : _playPauseController.forward();
    }

    if (_controller.value.position >= _controller.value.duration) {
      setState(() {
        _isPlaying = false;
      });
      _controller.seekTo(Duration.zero);
      _playPauseController.forward();
    }
  }

  void _togglePlay() {
    if (!_controller.value.isInitialized) return;
    
    setState(() {
      _isPlaying = !_isPlaying;
      _isPlaying ? _controller.play() : _controller.pause();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_videoListener);
    _controller.dispose();
    _playPauseController.dispose();
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
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!_isInitialized && widget.thumbnailUrl != null)
              Image.network(
                widget.thumbnailUrl!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(),
              ),
            if (_isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _togglePlay,
                child: AnimatedBuilder(
                  animation: _playPauseController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _playPauseController.value,
                      child: Container(
                        color: Colors.black26,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 50.0,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (_isBuffering)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            if (_isInitialized)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.red,
                    bufferedColor: Colors.grey,
                    backgroundColor: Colors.black45,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 8,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
