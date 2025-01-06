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

  // Reaksiyon emojileri
  final List<String> reactions = ['👍', '❤️', '😂', '😮', '😢', '😡'];

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
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

      final fileName = '${DateTime.now().millisecondsSinceEpoch}${path.extension(file.path)}';
      final storageRef = FirebaseStorage.instance.ref().child(folder).child(fileName);

      String? downloadUrl;
      String? thumbnailUrl;
      String messageType = folder == 'images' ? 'image' : 'video';

      if (messageType == 'video') {
        // Video sıkıştırma
        final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
          file.path,
          quality: VideoQuality.MediumQuality,
        );

        if (mediaInfo?.file != null) {
          final uploadTask = await storageRef.putFile(
            File(mediaInfo!.file!.path),
            SettableMetadata(contentType: 'video/mp4'),
          );
          downloadUrl = await uploadTask.ref.getDownloadURL();

          // Thumbnail oluştur ve yükle
          final thumbnailFile = await VideoCompress.getFileThumbnail(file.path);
          final thumbnailRef = storageRef.parent!.child('thumbnails/$fileName.jpg');
          final thumbnailUpload = await thumbnailRef.putFile(thumbnailFile);
          thumbnailUrl = await thumbnailUpload.ref.getDownloadURL();
        }
      } else {
        // Resim sıkıştırma ve XFile'ı File'a dönüştürme
        if (file is XFile) {
          final compressedFile = await FlutterImageCompress.compressAndGetFile(
            file.path,
            '${file.path}_compressed.jpg',
            quality: 70,
          );

          if (compressedFile != null) {
            final uploadTask = await storageRef.putFile(
              File(compressedFile.path),
              SettableMetadata(contentType: 'image/jpeg'),
            );
            downloadUrl = await uploadTask.ref.getDownloadURL();
          }
        } else {
          final compressedFile = await FlutterImageCompress.compressAndGetFile(
            file.path,
            '${file.path}_compressed.jpg',
            quality: 70,
          );

          if (compressedFile != null) {
            final uploadTask = await storageRef.putFile(
              File(compressedFile.path),
              SettableMetadata(contentType: 'image/jpeg'),
            );
            downloadUrl = await uploadTask.ref.getDownloadURL();
          }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chatName),
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
                        messageContent = GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => _VideoPlayerScreen(
                                  videoUrl: messageData['content'],
                                ),
                              ),
                            );
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.network(
                                messageData['thumbnail'] ?? '',
                                width: 200,
                                fit: BoxFit.cover,
                              ),
                              const Icon(
                                Icons.play_circle_fill,
                                size: 50,
                                color: Colors.white,
                              ),
                            ],
                          ),
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
                          ],
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
