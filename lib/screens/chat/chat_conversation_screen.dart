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
import '../../config/theme.dart';
import '../../services/imagekit_service.dart';

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
  final _currentUser = FirebaseAuth.instance.currentUser;
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();

  bool _isUploading = false;
  bool _isRecording = false;
  bool _isTyping = false;
  Timer? _typingTimer;
  String? _playingVoiceUrl;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  bool _isOtherOnline = false;
  bool _isOtherSubscribed = false;

  String? _replyToMessageId;
  String? _replyToText;
  bool _isReplying = false;

  DocumentSnapshot? _lastDocument;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;

  final Map<String, String> _voiceCache = {};

  @override
  void initState() {
    super.initState();
    _listenToTyping();
    _markMessagesAsRead();
    _listenToOnlineStatus();
    _audioPlayer.onPlayerStateChanged.listen((state) { if (mounted) setState(() => _isPlaying = state == PlayerState.playing); });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _messageController.dispose(); _scrollController.dispose(); _typingTimer?.cancel();
    _audioRecorder.dispose(); _audioPlayer.dispose();
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

  void _listenToTyping() {
    _messageController.addListener(() {
      if (_messageController.text.isNotEmpty && !_isTyping) {
        _setTyping(true);
      } else if (_messageController.text.isEmpty && _isTyping) {
        _setTyping(false);
      }
    });
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
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({'unreadCount.${_currentUser!.uid}': 0});
  }

  void _listenToOnlineStatus() {
    FirebaseFirestore.instance.collection('users').doc(widget.otherUserId).snapshots().listen((doc) {
      if (doc.exists && mounted) {
        setState(() {
          _isOtherOnline = doc.data()?['isOnline'] ?? false;
          _isOtherSubscribed = doc.data()?['isSubscribed'] == true;
        });
      }
    });
  }

  Future<void> _sendMessage({String? text, String? imageUrl, String? voiceUrl, int? voiceDuration}) async {
    if (_currentUser == null) return;
    String type = 'text';
    if (imageUrl != null) type = 'image';
    if (voiceUrl != null) type = 'voice';

    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').add({
      'senderId': _currentUser.uid, 'type': type, 'text': text ?? '', 'imageUrl': imageUrl, 'voiceUrl': voiceUrl,
      'voiceDuration': voiceDuration, 'replyTo': _replyToMessageId, 'reactions': [], 'isEdited': false,
      'readAt': null, 'status': 'sent', 'createdAt': FieldValue.serverTimestamp(),
    });

    String lastMessage = text ?? '';
    if (imageUrl != null) lastMessage = '📷 Photo';
    if (voiceUrl != null) lastMessage = '🎤 Voice note';

    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
      'lastMessage': lastMessage, 'lastMessageType': type, 'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadCount.${widget.otherUserId}': FieldValue.increment(1),
    });

    if (text != null) {
      _messageController.clear();
      _setTyping(false);
    }
    // Create notification for receiver
    final displayName = _currentUser.displayName ?? 'Someone';
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

  void _startReply(String messageId, String messageText) => setState(() { _replyToMessageId = messageId; _replyToText = messageText; _isReplying = true; });
  void _cancelReply() => setState(() { _replyToMessageId = null; _replyToText = null; _isReplying = false; });

  Future<void> _pickAndSendPhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _isUploading = true);
    final result = await ImageKitService.uploadImage(File(picked.path), 'chat_${DateTime.now().millisecondsSinceEpoch}');
    if (mounted) { setState(() => _isUploading = false); if (result['success'] == true) await _sendMessage(imageUrl: result['url']); }
  }

  Future<void> _startRecording() async {
    if (!await _audioRecorder.hasPermission()) return;
    setState(() => _isRecording = true);
    final tempDir = await getTemporaryDirectory();
    await _audioRecorder.start(RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 22050), path: '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
  }

  Future<void> _stopRecording() async {
    final path = await _audioRecorder.stop();
    if (mounted) setState(() => _isRecording = false);
    if (path == null) return;
    setState(() => _isUploading = true);
    final result = await ImageKitService.uploadImage(File(path), 'voice_${DateTime.now().millisecondsSinceEpoch}');
    if (mounted) {
      setState(() => _isUploading = false);
      if (result['success'] == true) {
        final file = File(path); final fileSize = await file.length();
        await _sendMessage(voiceUrl: result['url'], voiceDuration: (fileSize / 4000).round().clamp(1, 600));
      }
    }
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
    final localPath = await _getCachedVoice(url);
    if (_isPlaying && _playingVoiceUrl == url) { await _audioPlayer.pause(); }
    else if (_playingVoiceUrl == url && !_isPlaying) { await _audioPlayer.resume(); }
    else { await _audioPlayer.stop(); await _audioPlayer.play(DeviceFileSource(localPath)); _playingVoiceUrl = url; }
    await _audioPlayer.setPlaybackRate(_playbackSpeed);
  }

  void _cycleSpeed() {
    setState(() {
      if (_playbackSpeed >= 2.0) _playbackSpeed = 0.5;
      else if (_playbackSpeed >= 1.5) _playbackSpeed = 2.0;
      else if (_playbackSpeed >= 1.0) _playbackSpeed = 1.5;
      else _playbackSpeed = 1.0;
    });
    _audioPlayer.setPlaybackRate(_playbackSpeed);
  }

  Future<void> _addReaction(String messageId, String emoji) async {
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').doc(messageId).update({'reactions': FieldValue.arrayUnion([emoji])});
  }

  Future<void> _deleteMessage(String messageId) async {
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').doc(messageId).delete();
  }

  Future<void> _editMessage(String messageId, String currentText) async {
    final controller = TextEditingController(text: currentText);
    final result = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text('Edit Message', style: AppTextStyles.bodyLarge), content: TextField(controller: controller, maxLines: 3), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Save', style: TextStyle(color: AppColors.primary)))]));
    if (result == true && controller.text.trim().isNotEmpty) {
      await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').doc(messageId).update({'text': controller.text.trim(), 'isEdited': true});
    }
  }

  void _showMessageMenu(String messageId, String text, String type, List<dynamic> reactions) {
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
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
          if (type == 'text') ListTile(leading: Icon(Icons.edit, size: 20.sp), title: Text('Edit', style: AppTextStyles.bodyMedium), onTap: () { Navigator.pop(ctx); _editMessage(messageId, text); }),
          ListTile(leading: Icon(Icons.delete_outline, size: 20.sp, color: AppColors.error), title: Text('Delete', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)), onTap: () { Navigator.pop(ctx); _deleteMessage(messageId); }),
          SizedBox(height: 8.h),
        ]),
      ),
    );
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages || _lastDocument == null) return;
    setState(() => _isLoadingMore = true);
    final snapshot = await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .startAfterDocument(_lastDocument)
        .limit(30)
        .get();
    if (snapshot.docs.isEmpty) {
      setState(() {
        _hasMoreMessages = false;
        _isLoadingMore = false;
      });
    } else {
      _lastDocument = snapshot.docs.last;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _showReviewDialog() async {
    int rating = 0;
    final controller = TextEditingController();
    final result = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) => AlertDialog(title: Text('Rate Provider', style: AppTextStyles.bodyLarge), content: Column(mainAxisSize: MainAxisSize.min, children: [Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) => IconButton(icon: Icon(i < rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 36.sp), onPressed: () => setDialogState(() => rating = i + 1)))), SizedBox(height: 12.h), TextField(controller: controller, maxLines: 3, decoration: InputDecoration(hintText: 'Share your experience (optional)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r))))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), TextButton(onPressed: () { if (rating > 0) Navigator.pop(ctx, true); }, child: Text('Submit', style: TextStyle(color: AppColors.primary)))])));
    if (result == true && rating > 0 && _currentUser != null) {
      final existing = await FirebaseFirestore.instance.collection('reviews').where('providerId', isEqualTo: widget.otherUserId).where('clientId', isEqualTo: _currentUser.uid).get();
      if (existing.docs.isNotEmpty) {
        await existing.docs.first.reference.update({'rating': rating, 'comment': controller.text.trim(), 'createdAt': FieldValue.serverTimestamp()});
      } else {
        await FirebaseFirestore.instance.collection('reviews').add({'providerId': widget.otherUserId, 'clientId': _currentUser.uid, 'clientName': _currentUser.displayName ?? 'Client', 'rating': rating, 'comment': controller.text.trim(), 'createdAt': FieldValue.serverTimestamp()});
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Review submitted!'), backgroundColor: AppColors.success));
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: AppColors.background, appBar: AppBar(
      leading: GestureDetector(
        onTap: _isOtherSubscribed ? () => context.push('/provider/${widget.otherUserId}') : null,
        child: Padding(padding: EdgeInsets.all(8.w), child: FutureBuilder<DocumentSnapshot?>(future: FirebaseFirestore.instance.collection('users').doc(widget.otherUserId).get(), builder: (context, snap) {
          final data = snap.data?.data() as Map<String, dynamic>?;
          final photoUrl = data?['profileImage'] ?? data?['photoUrl'];
          return ClipRRect(borderRadius: BorderRadius.circular(24.r), child: photoUrl != null && photoUrl.toString().isNotEmpty ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover) : Icon(Icons.person, color: AppColors.primary.withValues(alpha: 0.3)));
        })),
      ),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.otherUserName, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600)),
        StreamBuilder<DocumentSnapshot?>(stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).snapshots(), builder: (context, snap) {
          final data = snap.data?.data() as Map<String, dynamic>?;
          final typing = data?['typing_${widget.otherUserId}'] == true;
          return Text(typing ? 'typing...' : (_isOtherOnline ? 'Online' : 'Offline'), style: AppTextStyles.caption.copyWith(color: typing ? AppColors.primary : (_isOtherOnline ? AppColors.success : AppColors.grey)));
        }),
      ]),
      actions: [IconButton(icon: Icon(Icons.star_outline, size: 22.sp), tooltip: 'Rate Provider', onPressed: _showReviewDialog)],
    ), body: GestureDetector(onTap: () => FocusScope.of(context).unfocus(), child: Column(children: [
      Expanded(child: StreamBuilder<QuerySnapshot>(stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').orderBy('createdAt', descending: true).limit(30).snapshots(), builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final messages = snapshot.data!.docs;
        if (messages.isEmpty) return Center(child: Text('No messages yet. Say hello!', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.5))));
        if (messages.isNotEmpty) _lastDocument = messages.last;

        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final doc in messages) {
          final data = doc.data() as Map<String, dynamic>;
          final ts = data['createdAt'] as Timestamp?;
          if (ts != null) grouped.putIfAbsent(_getMessageGroup(ts.toDate()), () => []).add({...data, 'id': doc.id});
        }
        final order = ['Today', 'Yesterday', 'This Week', 'This Month', 'Older'];
        final keys = grouped.keys.toList()..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));

        final widgets = <Widget>[];
        for (final key in keys) {
          widgets.add(Padding(padding: EdgeInsets.symmetric(vertical: 8.h), child: Center(child: Container(padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h), decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12.r)), child: Text(key, style: AppTextStyles.caption)))));
          for (final msg in grouped[key]!) { widgets.add(_buildMessage(msg)); }
        }
        if (_isLoadingMore) widgets.add(const Center(child: CircularProgressIndicator()));

        return ListView.builder(reverse: true, controller: _scrollController, padding: EdgeInsets.all(16.w), itemCount: widgets.length, itemBuilder: (_, i) => widgets[i]);
      })),
      if (_isReplying) Container(padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h), color: AppColors.primary.withValues(alpha: 0.04), child: Row(children: [Container(width: 3.w, height: 30.h, color: AppColors.primary), SizedBox(width: 8.w), Expanded(child: Text(_replyToText ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption)), IconButton(icon: Icon(Icons.close, size: 16.sp), onPressed: _cancelReply)])),
      Container(padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 16.h), color: AppColors.white, child: Row(children: [
        if (_isUploading) SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator(strokeWidth: 2))
        else ...[
          IconButton(icon: Icon(Icons.add_circle_outline, size: 24.sp, color: AppColors.primary), onPressed: _pickAndSendPhoto),
          GestureDetector(onLongPressStart: (_) => _startRecording(), onLongPressEnd: (_) => _stopRecording(), child: Container(padding: EdgeInsets.all(8.w), decoration: BoxDecoration(color: _isRecording ? AppColors.error.withValues(alpha: 0.1) : Colors.transparent, borderRadius: BorderRadius.circular(24.r)), child: Icon(_isRecording ? Icons.mic : Icons.mic_none, size: 24.sp, color: _isRecording ? AppColors.error : AppColors.primary))),
        ],
        SizedBox(width: 8.w),
        Expanded(child: TextField(controller: _messageController, style: AppTextStyles.bodyMedium, decoration: InputDecoration(hintText: _isReplying ? 'Type your reply...' : 'Type a message...', hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary.withValues(alpha: 0.3)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24.r), borderSide: BorderSide.none), filled: true, fillColor: AppColors.background, contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h)), onSubmitted: (t) => _sendMessage(text: t))),
        SizedBox(width: 8.w),
        IconButton(onPressed: () => _sendMessage(text: _messageController.text), icon: Icon(Icons.send_rounded, size: 24.sp, color: AppColors.primary)),
      ])),
    ])));
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    final isMine = msg['senderId'] == _currentUser?.uid;
    final type = msg['type'] ?? 'text'; final text = msg['text'] ?? '';
    final imageUrl = msg['imageUrl']; final voiceUrl = msg['voiceUrl'];
    final voiceDuration = msg['voiceDuration'] as int?;
    final replyTo = msg['replyTo'] as String?;
    final reactions = List<String>.from(msg['reactions'] ?? []);
    final isEdited = msg['isEdited'] ?? false;
    final status = msg['status'] ?? 'sent';
    final ts = msg['createdAt'] as Timestamp?;

    return Align(alignment: isMine ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: EdgeInsets.only(bottom: 8.h), constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75), child: Column(crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      if (replyTo != null) _buildReplyPreview(replyTo),
      GestureDetector(onLongPress: () => _showMessageMenu(msg['id'], text, type, reactions), child: _buildMessageBubble(type, text, imageUrl, voiceUrl, voiceDuration, isMine)),
      if (reactions.isNotEmpty) Padding(padding: EdgeInsets.only(top: 2.h), child: Wrap(spacing: 2.w, children: reactions.map((e) => Text(e, style: TextStyle(fontSize: 14.sp))).toList())),
      SizedBox(height: 2.h),
      Row(mainAxisSize: MainAxisSize.min, children: [Text(_formatTime(ts), style: AppTextStyles.caption.copyWith(fontSize: 9.sp)), if (isMine) ...[SizedBox(width: 4.w), Text(status == 'read' ? 'Read' : status == 'delivered' ? 'Delivered' : 'Sent', style: AppTextStyles.caption.copyWith(fontSize: 9.sp, color: status == 'read' ? AppColors.success : AppColors.grey))], if (isEdited) ...[SizedBox(width: 4.w), Text('edited', style: AppTextStyles.caption.copyWith(fontSize: 9.sp, fontStyle: FontStyle.italic))]]),
    ])));
  }

  Widget _buildReplyPreview(String replyToId) {
    return FutureBuilder<DocumentSnapshot?>(
      future: FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(replyToId)
          .get(),
      builder: (context, snap) {
        final doc = snap.data;
        if (doc == null || !doc.exists) return const SizedBox.shrink();
        final data = doc.data() as Map<String, dynamic>;
        final replyType = data['type'] ?? 'text';
        final replyText = replyType == 'image'
            ? '📷 Photo'
            : replyType == 'voice'
                ? '🎤 Voice note'
                : (data['text'] ?? '');
        return Container(
          margin: EdgeInsets.only(bottom: 4.h),
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8.r),
            border: Border(
              left: BorderSide(color: AppColors.primary, width: 3.w),
            ),
          ),
          child: Text(
            replyText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption,
          ),
        );
      },
    );
  }

  Widget _buildMessageBubble(String type, String text, String? imageUrl, String? voiceUrl, int? voiceDuration, bool isMine) {
    final bgColor = isMine ? AppColors.primary : AppColors.white;
    final textColor = isMine ? AppColors.white : AppColors.primary;
    final borderRadius = isMine ? BorderRadius.only(topLeft: Radius.circular(16.r), bottomLeft: Radius.circular(16.r), bottomRight: Radius.circular(4.r)) : BorderRadius.only(topRight: Radius.circular(16.r), bottomLeft: Radius.circular(4.r), bottomRight: Radius.circular(16.r));

    if (type == 'image' && imageUrl != null) return GestureDetector(onTap: () => _showFullScreenImage(imageUrl), child: ClipRRect(borderRadius: BorderRadius.circular(16.r), child: CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover, width: double.infinity)));
    if (type == 'voice' && voiceUrl != null) return _VoiceBubble(voiceUrl: voiceUrl, duration: voiceDuration ?? 0, isMine: isMine, isPlaying: _isPlaying && _playingVoiceUrl == voiceUrl, playbackSpeed: _playbackSpeed, onPlay: () => _playVoice(voiceUrl), onSpeedCycle: _cycleSpeed, onGetCached: () => _getCachedVoice(voiceUrl));
    return Container(padding: EdgeInsets.all(12.w), decoration: BoxDecoration(color: bgColor, borderRadius: borderRadius, border: isMine ? null : Border.all(color: AppColors.primary.withValues(alpha: 0.1))), child: Text(text, style: AppTextStyles.bodyMedium.copyWith(color: textColor)));
  }

  void _showFullScreenImage(String imageUrl) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, iconTheme: IconThemeData(color: Colors.white)), body: Center(child: CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.contain)))));
  }
}

class _VoiceBubble extends StatefulWidget {
  final String voiceUrl; final int duration; final bool isMine; final bool isPlaying;
  final double playbackSpeed; final VoidCallback onPlay; final VoidCallback onSpeedCycle;
  final Future<String> Function() onGetCached;
  const _VoiceBubble({required this.voiceUrl, required this.duration, required this.isMine, required this.isPlaying, required this.playbackSpeed, required this.onPlay, required this.onSpeedCycle, required this.onGetCached});
  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final _audioPlayer = AudioPlayer();
  Duration _position = Duration.zero; Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.duration);
    _audioPlayer.onPositionChanged.listen((pos) { if (mounted) setState(() => _position = pos); });
    _audioPlayer.onDurationChanged.listen((dur) { if (mounted) setState(() => _duration = dur); });
    _initPlayer();
  }

  Future<void> _initPlayer() async { await widget.onGetCached(); }

  @override
  void dispose() { _audioPlayer.dispose(); super.dispose(); }

  void _seekTo(double value) { _audioPlayer.seek(Duration(milliseconds: (value * _duration.inMilliseconds).round())); }

  String _fmt(Duration d) => '${d.inMinutes.remainder(60).toString().padLeft(1, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isMine ? AppColors.primary : AppColors.white;
    final textColor = widget.isMine ? AppColors.white : AppColors.primary;
    final progress = _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0.0;
    final width = MediaQuery.of(context).size.width * 0.45;

    return Container(padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h), decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16.r), border: widget.isMine ? null : Border.all(color: AppColors.primary.withValues(alpha: 0.1))), child: SizedBox(width: width, child: Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(onTap: widget.onPlay, child: Icon(widget.isPlaying ? Icons.pause : Icons.play_arrow, color: textColor, size: 24.sp)),
      SizedBox(width: 8.w),
      Expanded(child: GestureDetector(
        onTapDown: (details) { final box = context.findRenderObject() as RenderBox; _seekTo((details.localPosition.dx - 44) / (box.size.width - 56)); },
        onHorizontalDragUpdate: (details) { final box = context.findRenderObject() as RenderBox; _seekTo((details.localPosition.dx - 44) / (box.size.width - 56)); },
        child: ClipRRect(borderRadius: BorderRadius.circular(2.r), child: LinearProgressIndicator(value: progress, minHeight: 4.h, backgroundColor: textColor.withValues(alpha: 0.2), color: textColor)),
      )),
      SizedBox(width: 6.w),
      Text(_fmt(_position), style: AppTextStyles.caption.copyWith(fontSize: 10.sp, color: textColor)),
      SizedBox(width: 4.w),
      GestureDetector(onTap: widget.onSpeedCycle, child: Container(padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h), decoration: BoxDecoration(color: textColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4.r)), child: Text('${widget.playbackSpeed}x', style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: textColor)))),
    ])));
  }
}
