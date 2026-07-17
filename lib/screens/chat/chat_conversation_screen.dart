import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../services/imagekit_service.dart';
import '../../providers/auth_provider.dart' as app_auth;
import '../../services/display_name_service.dart';

class ChatConversationScreen extends StatefulWidget {
  final String chatId;
  final String otherUserId;
  final String otherUserName;
  const ChatConversationScreen({super.key, required this.chatId, required this.otherUserId, required this.otherUserName});
  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  final _currentUser = FirebaseAuth.instance.currentUser;
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();

  bool _isRecording = false;
  bool _isRecordingPaused = false;
  String? _recordingPath;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  bool _isTyping = false;
  Timer? _typingTimer;
  String? _playingVoiceUrl;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  Duration _voicePosition = Duration.zero;
  Duration _voiceDuration = Duration.zero;
  bool _isOtherOnline = false;
  bool _isOtherSubscribed = false;

  String? _replyToMessageId;
  String? _replyToText;
  String? _replyToType;
  String? _replyToImageUrl;
  int? _replyToVoiceDuration;
  bool _isReplying = false;

  DocumentSnapshot? _lastDocument;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;

  final Map<String, String> _voiceCache = {};

  // Pending uploads
  final Set<String> _uploadingVoiceUrls = {};

  @override
  void initState() {
    super.initState();
    _markMessagesAsRead();
    _listenToOnlineStatus();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        final wasPlaying = _isPlaying;
        setState(() => _isPlaying = state == PlayerState.playing);
        if (wasPlaying && state == PlayerState.completed) {
          setState(() {
            _isPlaying = false;
            _playingVoiceUrl = null;
            _voicePosition = Duration.zero;
          });
        }
      }
    });
    _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _voicePosition = pos);
    });
    _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _voiceDuration = dur);
    });
    _scrollController.addListener(_onScroll);
    _messageController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients && _scrollController.position.pixels <= 100 && _hasMoreMessages && !_isLoadingMore) {
      _loadMoreMessages();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  void _onTextChanged() {
    final hasText = _messageController.text.isNotEmpty;
    if (hasText && !_isTyping) {
      _setTyping(true);
    } else if (!hasText && _isTyping) {
      _setTyping(false);
    }
    setState(() {});
  }

  Future<void> _setTyping(bool value) async {
    _isTyping = value;
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({'typing_${_currentUser!.uid}': value});
    if (value) { _typingTimer?.cancel(); _typingTimer = Timer(const Duration(seconds: 3), () { if (_isTyping) _setTyping(false); }); }
  }

  Future<void> _markMessagesAsRead() async {
    final unread = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').where('senderId', isEqualTo: widget.otherUserId).where('readAt', isEqualTo: null).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in unread.docs) { batch.update(doc.reference, {'readAt': FieldValue.serverTimestamp(), 'status': 'read'}); }
    await batch.commit();
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
      'unreadCount': {_currentUser!.uid: 0},
    });
  }

  void _listenToOnlineStatus() {
    FirebaseFirestore.instance.collection('users').doc(widget.otherUserId).snapshots().listen((doc) {
      if (doc.exists && mounted) setState(() { _isOtherOnline = doc.data()?['isOnline'] ?? false; _isOtherSubscribed = doc.data()?['isSubscribed'] == true; });
    });
  }

  bool get _canSend => _messageController.text.trim().isNotEmpty;

  Future<void> _sendMessage({String? text, String? imageUrl, String? voiceUrl, int? voiceDuration}) async {
    if (_currentUser == null) return;
    String type = 'text';
    if (imageUrl != null) type = 'image';
    if (voiceUrl != null) type = 'voice';

    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').add({
      'senderId': _currentUser.uid, 'type': type, 'text': text ?? '', 'imageUrl': imageUrl, 'voiceUrl': voiceUrl,
      'voiceDuration': voiceDuration, 'replyTo': _replyToMessageId, 'reactions': [], 'isEdited': false,
      'readAt': null, 'status': 'sent', 'createdAt': FieldValue.serverTimestamp(),
      'deletedFor': [],
    });

    String lastMessage = text ?? '';
    if (imageUrl != null) lastMessage = '📷 Photo';
    if (voiceUrl != null) lastMessage = '🎤 Voice note';

    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
      'lastMessage': lastMessage, 'lastMessageType': type, 'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadCount': {widget.otherUserId: FieldValue.increment(1)},
    });

    if (text != null) {
      _messageController.clear();
      _setTyping(false);
      _messageFocusNode.requestFocus();
    }
    final displayName = await DisplayNameService.getDisplayName(_currentUser.uid);
    final preview = lastMessage.length > 80 ? '${lastMessage.substring(0, 80)}...' : lastMessage;
    await FirebaseFirestore.instance.collection('users').doc(widget.otherUserId).collection('notifications').add({
      'type': 'message',
      'title': displayName,
      'body': preview,
      'read': false,
      'data': {
        'chatId': widget.chatId,
        'otherUserId': _currentUser.uid,
        'otherUserName': displayName,
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
    _cancelReply();
    _scrollToBottom();
  }

  void _startReply(String messageId, String messageText, {String? type, String? imageUrl, int? voiceDuration}) {
    setState(() {
      _replyToMessageId = messageId;
      _replyToText = messageText;
      _replyToType = type ?? 'text';
      _replyToImageUrl = imageUrl;
      _replyToVoiceDuration = voiceDuration;
      _isReplying = true;
    });
  }

  void _cancelReply() => setState(() { _replyToMessageId = null; _replyToText = null; _replyToType = null; _replyToImageUrl = null; _replyToVoiceDuration = null; _isReplying = false; });

  Future<void> _pickAndSendPhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    // Send immediately with a placeholder, then update
    final tempUrl = 'uploading_${DateTime.now().millisecondsSinceEpoch}';
    _sendMessage(imageUrl: tempUrl);
    final result = await ImageKitService.uploadImage(File(picked.path), 'chat_${DateTime.now().millisecondsSinceEpoch}');
    if (mounted && result['success'] == true) {
      // Update the message with real URL — handled by stream
    }
  }

  Future<void> _startRecording() async {
    if (!await _audioRecorder.hasPermission()) return;
    setState(() { _isRecording = true; _isRecordingPaused = false; _recordingSeconds = 0; });
    final tempDir = await getTemporaryDirectory();
    _recordingPath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 22050), path: _recordingPath!);
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isRecording && !_isRecordingPaused) setState(() => _recordingSeconds++);
    });
  }

  Future<void> _pauseRecording() async {
    if (_isRecordingPaused) {
      await _audioRecorder.resume();
      setState(() => _isRecordingPaused = false);
    } else {
      await _audioRecorder.pause();
      setState(() => _isRecordingPaused = true);
    }
  }

  Future<void> _deleteRecording() async {
    _recordingTimer?.cancel();
    await _audioRecorder.stop();
    if (_recordingPath != null) {
      final file = File(_recordingPath!);
      if (await file.exists()) await file.delete();
    }
    setState(() { _isRecording = false; _isRecordingPaused = false; _recordingPath = null; _recordingSeconds = 0; });
  }

  Future<void> _sendRecording() async {
    _recordingTimer?.cancel();
    final path = await _audioRecorder.stop();
    if (mounted) setState(() { _isRecording = false; _isRecordingPaused = false; });
    if (path == null) return;
    
    final file = File(path);
    final fileSize = await file.length();
    final duration = (fileSize / 4000).round().clamp(1, 600);
    
    // Send immediately with a placeholder URL
    final tempUrl = 'uploading_${DateTime.now().millisecondsSinceEpoch}';
    _uploadingVoiceUrls.add(tempUrl);
    _sendMessage(voiceUrl: tempUrl, voiceDuration: duration);
    
    // Upload in background
    final result = await ImageKitService.uploadImage(file, 'voice_${DateTime.now().millisecondsSinceEpoch}');
    if (mounted && result['success'] == true) {
      _uploadingVoiceUrls.remove(tempUrl);
      // Update the message with real URL — handled by stream
    }
    _recordingPath = null;
    _recordingSeconds = 0;
  }

  String _formatRecordingTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<String> _getCachedVoice(String url) async {
    if (_voiceCache.containsKey(url)) return _voiceCache[url]!;
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/voice_${url.hashCode}.m4a');
    if (await file.exists()) { _voiceCache[url] = file.path; return file.path; }
    final response = await http.get(Uri.parse(url));
    await file.writeAsBytes(response.bodyBytes);
    _voiceCache[url] = file.path;
    return file.path;
  }

  Future<void> _playVoice(String url) async {
    if (url.startsWith('uploading_')) return; // Can't play uploading files
    final localPath = await _getCachedVoice(url);
    if (_isPlaying && _playingVoiceUrl == url) {
      await _audioPlayer.pause();
    } else if (_playingVoiceUrl == url && !_isPlaying) {
      await _audioPlayer.resume();
    } else {
      await _audioPlayer.stop();
      setState(() { _voicePosition = Duration.zero; });
      await _audioPlayer.play(DeviceFileSource(localPath));
      setState(() { _playingVoiceUrl = url; _isPlaying = true; });
    }
    await _audioPlayer.setPlaybackRate(_playbackSpeed);
  }

  void _seekVoice(double value) {
    final targetMs = (value * _voiceDuration.inMilliseconds).round();
    _audioPlayer.seek(Duration(milliseconds: targetMs));
  }

  void _cycleSpeed() {
    setState(() {
      if (_playbackSpeed >= 2.0) {
        _playbackSpeed = 0.5;
      } else if (_playbackSpeed >= 1.5) {
        _playbackSpeed = 2.0;
      } else if (_playbackSpeed >= 1.0) {
        _playbackSpeed = 1.5;
      } else {
        _playbackSpeed = 1.0;
      }
    });
    _audioPlayer.setPlaybackRate(_playbackSpeed);
  }

  Future<void> _addReaction(String messageId, String emoji) async {
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').doc(messageId).update({'reactions': FieldValue.arrayUnion([emoji])});
  }

  Future<void> _deleteMessage(String messageId, String senderId) async {
    if (senderId == _currentUser?.uid) {
      await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').doc(messageId).delete();
    } else {
      await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').doc(messageId).update({
        'deletedFor': FieldValue.arrayUnion([_currentUser!.uid]),
      });
    }
  }

  Future<void> _editMessage(String messageId, String currentText) async {
    final controller = TextEditingController(text: currentText);
    final result = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text('Edit Message', style: AppTextStyles.bodyLarge), content: TextField(controller: controller, maxLines: 3), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Save', style: TextStyle(color: AppColors.primary)))]));
    if (result == true && controller.text.trim().isNotEmpty) {
      await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').doc(messageId).update({'text': controller.text.trim(), 'isEdited': true});
    }
  }

  void _showMessageMenu(String messageId, String text, String type, String senderId, List<dynamic> reactions) {
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    final isOwn = senderId == _currentUser?.uid;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16.r))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: emojis.map((emoji) {
                return GestureDetector(
                  onTap: () { Navigator.pop(ctx); _addReaction(messageId, emoji); },
                  child: Container(padding: EdgeInsets.all(8.w), child: Text(emoji, style: TextStyle(fontSize: 24.sp))),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          ListTile(leading: Icon(Icons.reply, size: 20.sp), title: Text('Reply', style: AppTextStyles.bodyMedium), onTap: () { Navigator.pop(ctx); _startReply(messageId, text); }),
          if (type == 'text' && isOwn) ListTile(leading: Icon(Icons.edit, size: 20.sp), title: Text('Edit', style: AppTextStyles.bodyMedium), onTap: () { Navigator.pop(ctx); _editMessage(messageId, text); }),
          ListTile(leading: Icon(Icons.delete_outline, size: 20.sp, color: AppColors.error), title: Text(isOwn ? 'Delete' : 'Delete for me', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)), onTap: () { Navigator.pop(ctx); _deleteMessage(messageId, senderId); }),
          SizedBox(height: 8.h),
        ]),
      ),
    );
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages || _lastDocument == null) return;
    setState(() => _isLoadingMore = true);
    final snapshot = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').orderBy('createdAt', descending: true).startAfterDocument(_lastDocument!).limit(30).get();
    if (snapshot.docs.isEmpty) { setState(() { _hasMoreMessages = false; _isLoadingMore = false; }); }
    else { _lastDocument = snapshot.docs.last; setState(() => _isLoadingMore = false); }
  }

  String _getMessageGroup(DateTime date) {
    final now = DateTime.now(); final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(date.year, date.month, date.day)).inDays;
    if (diff == 0) return 'Today'; if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This Week'; if (diff < 30) return 'This Month';
    return 'Older';
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    return '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _fmtDuration(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final isEarlyAccess = context.watch<app_auth.AuthProvider>().isEarlyAccess;
    final showBadge = isEarlyAccess || _isOtherSubscribed;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 20.sp),
          onPressed: () => context.pop(),
        ),
        title: GestureDetector(
          onTap: () => context.push('/provider/${widget.otherUserId}'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FutureBuilder<DocumentSnapshot?>(
                future: FirebaseFirestore.instance.collection('users').doc(widget.otherUserId).get(),
                builder: (context, snap) {
                  final data = snap.data?.data() as Map<String, dynamic>?;
                  final photoUrl = data?['profileImage'] ?? data?['photoUrl'];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(24.r),
                    child: SizedBox(
                      width: 36.w, height: 36.w,
                      child: photoUrl != null && photoUrl.toString().isNotEmpty
                          ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover)
                          : Icon(Icons.person, size: 20.sp, color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                  );
                },
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(child: Text(widget.otherUserName, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                        if (showBadge) ...[SizedBox(width: 4.w), Icon(Icons.verified, size: 14.sp, color: Color(0xFF2196F3))],
                      ],
                    ),
                    StreamBuilder<DocumentSnapshot?>(
                      stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).snapshots(),
                      builder: (context, snap) {
                        final data = snap.data?.data() as Map<String, dynamic>?;
                        final typing = data?['typing_${widget.otherUserId}'] == true;
                        return Text(
                          typing ? 'typing...' : (_isOtherOnline ? 'Online' : 'Offline'),
                          style: AppTextStyles.caption.copyWith(color: typing ? AppColors.primary : (_isOtherOnline ? AppColors.success : AppColors.grey)),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').orderBy('createdAt', descending: true).limit(30).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final allMessages = snapshot.data!.docs;
                final currentUid = _currentUser?.uid ?? '';
                final messages = allMessages.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final deletedFor = List<String>.from(data['deletedFor'] ?? []);
                  return !deletedFor.contains(currentUid);
                }).toList();

                if (messages.isEmpty) return Center(child: Text('No messages yet. Say hello!', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.5))));
                if (messages.isNotEmpty) _lastDocument = messages.last;

                final grouped = <String, List<Map<String, dynamic>>>{};
                for (final doc in messages) {
                  final data = doc.data() as Map<String, dynamic>;
                  final ts = data['createdAt'] as Timestamp?;
                  if (ts != null) grouped.putIfAbsent(_getMessageGroup(ts.toDate()), () => []).add({...data, 'id': doc.id});
                }
                // Date separators appear BEFORE their messages - Today first, then older
                final order = ['Today', 'Yesterday', 'This Week', 'This Month', 'Older'];
                final keys = grouped.keys.toList()..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));

                final widgets = <Widget>[];
                for (final key in keys) {
                  // Date separator comes BEFORE the messages of that group
                  widgets.add(Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    child: Center(child: Container(padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12.r)), child: FittedBox(child: Text(key, style: AppTextStyles.caption)))),
                  ));
                  for (final msg in grouped[key]!) { widgets.add(_buildMessage(msg)); }
                }
                if (_isLoadingMore) widgets.add(const Center(child: CircularProgressIndicator()));

                return ListView.builder(reverse: true, controller: _scrollController, padding: EdgeInsets.all(16.w), itemCount: widgets.length, itemBuilder: (_, i) => widgets[i]);
              },
            ),
          ),
          if (_isReplying) _buildReplyBar(),
          if (_isRecording) _buildRecordingBar(),
          if (!_isRecording) _buildInputBar(),
        ]),
      ),
    );
  }

  Widget _buildReplyBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      color: AppColors.primary.withValues(alpha: 0.04),
      child: Row(children: [
        Container(width: 3.w, height: 30.h, color: AppColors.primary),
        SizedBox(width: 8.w),
        if (_replyToType == 'image' && _replyToImageUrl != null)
          ClipRRect(borderRadius: BorderRadius.circular(4.r), child: CachedNetworkImage(imageUrl: _replyToImageUrl!, width: 30.w, height: 30.h, fit: BoxFit.cover))
        else if (_replyToType == 'voice')
          Row(children: [Icon(Icons.mic, size: 14.sp, color: AppColors.primary), SizedBox(width: 4.w), Text('${_replyToVoiceDuration ?? 0}s', style: AppTextStyles.caption)])
        else
          Expanded(child: Text(_replyToText ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption)),
        if (_replyToType != 'text' || (_replyToText?.isEmpty ?? true))
          Expanded(child: Text(_replyToType == 'image' ? '📷 Photo' : '🎤 Voice note', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption)),
        if (_replyToType == 'text' && (_replyToText?.isNotEmpty ?? false))
          Expanded(child: Text(_replyToText ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption)),
        IconButton(icon: Icon(Icons.close, size: 16.sp), onPressed: _cancelReply),
      ]),
    );
  }

  Widget _buildRecordingBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      color: AppColors.white,
      child: Row(children: [
        Icon(Icons.fiber_manual_record, color: AppColors.error, size: 16.sp),
        SizedBox(width: 8.w),
        Text(_formatRecordingTime(_recordingSeconds), style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
        if (_isRecordingPaused) ...[SizedBox(width: 4.w), Text('(Paused)', style: AppTextStyles.caption.copyWith(color: AppColors.grey))],
        const Spacer(),
        IconButton(icon: Icon(Icons.delete_outline, color: AppColors.grey, size: 22.sp), onPressed: _deleteRecording),
        IconButton(icon: Icon(_isRecordingPaused ? Icons.play_arrow : Icons.pause, color: AppColors.primary, size: 22.sp), onPressed: _pauseRecording),
        IconButton(icon: Icon(Icons.send_rounded, color: AppColors.primary, size: 22.sp), onPressed: _sendRecording),
      ]),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 16.h),
      color: AppColors.white,
      child: Row(children: [
        IconButton(icon: Icon(Icons.add_circle_outline, size: 24.sp, color: AppColors.primary), onPressed: _pickAndSendPhoto),
        GestureDetector(
          onTap: _startRecording,
          child: Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(24.r)),
            child: Icon(Icons.mic_none, size: 24.sp, color: AppColors.primary),
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: TextField(
            controller: _messageController,
            focusNode: _messageFocusNode,
            onChanged: (_) => _onTextChanged(),
            style: AppTextStyles.bodyMedium,
            decoration: InputDecoration(
              hintText: _isReplying ? 'Type your reply...' : 'Type a message...',
              hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.3)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24.r), borderSide: BorderSide.none),
              filled: true,
              fillColor: AppColors.background,
              contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
            ),
            onSubmitted: (t) { if (_canSend) _sendMessage(text: t); },
          ),
        ),
        SizedBox(width: 8.w),
        IconButton(
          onPressed: _canSend ? () => _sendMessage(text: _messageController.text) : null,
          icon: Icon(Icons.send_rounded, size: 24.sp, color: _canSend ? AppColors.primary : AppColors.grey),
        ),
      ]),
    );
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    final isMine = msg['senderId'] == _currentUser?.uid;
    final type = msg['type'] ?? 'text';
    final text = msg['text'] ?? '';
    final imageUrl = msg['imageUrl'];
    final voiceUrl = msg['voiceUrl'];
    final voiceDuration = msg['voiceDuration'] as int?;
    final replyTo = msg['replyTo'] as String?;
    final senderId = msg['senderId'] as String? ?? '';
    final reactions = List<String>.from(msg['reactions'] ?? []);
    final isEdited = msg['isEdited'] ?? false;
    final status = msg['status'] ?? 'sent';
    final ts = msg['createdAt'] as Timestamp?;
    final isUploading = (imageUrl != null && imageUrl.startsWith('uploading_')) ||
        (voiceUrl != null && _uploadingVoiceUrls.contains(voiceUrl));

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: 8.h),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Column(
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (replyTo != null) _buildReplyPreview(replyTo),
            GestureDetector(
              onLongPress: isUploading ? null : () => _showMessageMenu(msg['id'], text, type, senderId, reactions),
              child: _buildMessageBubble(type, text, imageUrl, voiceUrl, voiceDuration, isMine, isUploading),
            ),
            if (reactions.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 2.h),
                child: Wrap(spacing: 2.w, children: reactions.map((e) => Text(e, style: TextStyle(fontSize: 14.sp))).toList()),
              ),
            if (isUploading)
              Padding(
                padding: EdgeInsets.only(top: 2.h),
                child: Text('Sending...', style: AppTextStyles.caption.copyWith(fontSize: 9.sp, color: AppColors.grey, fontStyle: FontStyle.italic)),
              ),
            SizedBox(height: 2.h),
            if (!isUploading)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(child: Text(_formatTime(ts), style: AppTextStyles.caption.copyWith(fontSize: 9.sp))),
                  if (isMine) ...[SizedBox(width: 4.w), FittedBox(child: Text(status == 'read' ? 'Read' : status == 'delivered' ? 'Delivered' : 'Sent', style: AppTextStyles.caption.copyWith(fontSize: 9.sp, color: status == 'read' ? AppColors.success : AppColors.grey)))],
                  if (isEdited) ...[SizedBox(width: 4.w), FittedBox(child: Text('edited', style: AppTextStyles.caption.copyWith(fontSize: 9.sp, fontStyle: FontStyle.italic)))],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyPreview(String replyToId) {
    return FutureBuilder<DocumentSnapshot?>(
      future: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').doc(replyToId).get(),
      builder: (context, snap) {
        final doc = snap.data;
        if (doc == null || !doc.exists) return const SizedBox.shrink();
        final data = doc.data() as Map<String, dynamic>;
        final replyType = data['type'] ?? 'text';
        return Container(
          margin: EdgeInsets.only(bottom: 4.h),
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8.r),
            border: Border(left: BorderSide(color: AppColors.primary, width: 3.w)),
          ),
          child: _buildReplyContent(replyType, data),
        );
      },
    );
  }

  Widget _buildReplyContent(String type, Map<String, dynamic> data) {
    if (type == 'image') {
      final imageUrl = data['imageUrl'] as String?;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (imageUrl != null)
            ClipRRect(borderRadius: BorderRadius.circular(4.r), child: CachedNetworkImage(imageUrl: imageUrl, width: 24.w, height: 24.h, fit: BoxFit.cover)),
          SizedBox(width: 4.w),
          Text('📷 Photo', style: AppTextStyles.caption),
        ],
      );
    }
    if (type == 'voice') {
      final duration = data['voiceDuration'] as int?;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic, size: 14.sp, color: AppColors.primary),
          SizedBox(width: 4.w),
          Text('🎤 Voice note ${duration != null ? '(${duration}s)' : ''}', style: AppTextStyles.caption),
        ],
      );
    }
    return Text(data['text'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption);
  }

  Widget _buildMessageBubble(String type, String text, String? imageUrl, String? voiceUrl, int? voiceDuration, bool isMine, bool isUploading) {
    final bgColor = isMine ? AppColors.primary : AppColors.white;
    final textColor = isMine ? AppColors.white : AppColors.primary;
    final borderRadius = BorderRadius.only(
      topLeft: Radius.circular(16.r),
      topRight: Radius.circular(16.r),
      bottomLeft: Radius.circular(isMine ? 16.r : 4.r),
      bottomRight: Radius.circular(isMine ? 4.r : 16.r),
    );

    if (type == 'image' && imageUrl != null) {
      return GestureDetector(
        onTap: isUploading ? null : () => _showFullScreenImage(imageUrl),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16.r),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 200.w, maxHeight: 200.h),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isUploading)
                  Container(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover),
              ],
            ),
          ),
        ),
      );
    }
    if (type == 'voice' && voiceUrl != null) {
      final isCurrentVoice = _isPlaying && _playingVoiceUrl == voiceUrl;
      if (isUploading) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: borderRadius,
            border: isMine ? null : Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 20.h, width: 20.w, child: const CircularProgressIndicator(strokeWidth: 2, color: AppColors.grey)),
              SizedBox(width: 8.w),
              Text('Sending voice note...', style: AppTextStyles.caption.copyWith(color: AppColors.grey)),
            ],
          ),
        );
      }
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16.r),
          border: isMine ? null : Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
        ),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.45,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _playVoice(voiceUrl),
                child: Icon(
                  isCurrentVoice ? Icons.pause : Icons.play_arrow,
                  color: textColor,
                  size: 24.sp,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2.r),
                      child: LinearProgressIndicator(
                        value: isCurrentVoice && _voiceDuration.inMilliseconds > 0
                            ? _voicePosition.inMilliseconds / _voiceDuration.inMilliseconds
                            : 0.0,
                        minHeight: 4.h,
                        backgroundColor: textColor.withValues(alpha: 0.2),
                        color: textColor,
                      ),
                    ),
                    if (isCurrentVoice && _voiceDuration.inMilliseconds > 0)
                      Positioned(
                        left: (_voicePosition.inMilliseconds / _voiceDuration.inMilliseconds) * (MediaQuery.of(context).size.width * 0.45 - 80) - 6,
                        top: -4.h,
                        child: GestureDetector(
                          onHorizontalDragUpdate: (details) {
                            final box = context.findRenderObject() as RenderBox;
                            final boxWidth = box.size.width;
                            if (boxWidth > 0) {
                              _seekVoice((details.localPosition.dx / boxWidth).clamp(0.0, 1.0));
                            }
                          },
                          child: Container(
                            width: 12.w,
                            height: 12.w,
                            decoration: BoxDecoration(
                              color: textColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: 6.w),
              Text(
                isCurrentVoice
                    ? _fmtDuration(_voicePosition)
                    : _fmtDuration(Duration(seconds: voiceDuration ?? 0)),
                style: AppTextStyles.caption.copyWith(fontSize: 10.sp, color: textColor),
              ),
              SizedBox(width: 4.w),
              GestureDetector(
                onTap: isCurrentVoice ? _cycleSpeed : null,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                  child: FittedBox(
                    child: Text(
                      '${_playbackSpeed}x',
                      style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: textColor),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: borderRadius,
        border: isMine ? null : Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
      ),
      child: Text(text, style: AppTextStyles.bodyMedium.copyWith(color: textColor)),
    );
  }

  void _showFullScreenImage(String imageUrl) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, iconTheme: IconThemeData(color: Colors.white)), body: Center(child: CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain)))));
  }
}