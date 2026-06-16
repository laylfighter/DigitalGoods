import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import '../theme.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text('Messages', style: AppTheme.heading(20, color: Colors.white)),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.primaryGradient)),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: uid)
            .orderBy('lastMessageTime', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _chatSkeleton();
          }

          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(child: Text('No chats yet'));
          }

          final chats = snap.data!.docs;

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, i) {
              final chat = chats[i];
              final chatData = chat.data() as Map<String, dynamic>? ?? {};
              final participants = List<String>.from(chatData['participants'] ?? []);

              if (participants.length < 2) return const SizedBox();

              final otherUid = participants.firstWhere(
                    (u) => u != uid,
                orElse: () => '',
              );
              if (otherUid.isEmpty) return const SizedBox();

              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(otherUid)
                    .snapshots(),
                builder: (context, userSnap) {
                  if (!userSnap.hasData || !userSnap.data!.exists) {
                    return _chatSkeletonItem();
                  }

                  final userData = userSnap.data!.data() as Map<String, dynamic>? ?? {};
                  final unread = (chatData['unread_$uid'] ?? 0) as int;

                  return Dismissible(
                    key: Key(chat.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red.shade500,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    secondaryBackground: Container(
                      color: Colors.red.shade500,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    confirmDismiss: (direction) async {
                      return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Chat'),
                          content: const Text('Are you sure you want to delete this chat?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ) ?? false;
                    },
                    onDismissed: (direction) => _deleteChat(context, chat.id),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundImage: userData['photoUrl'] != null
                            ? NetworkImage(userData['photoUrl'])
                            : null,
                        child: userData['photoUrl'] == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(userData['name'] ?? 'User', style: AppTheme.heading(16)),
                      subtitle: Text(
                        chatData['lastMessage'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(14, color: AppTheme.textSecondary),
                      ),
                      trailing: unread > 0
                          ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryStart,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          unread.toString(),
                          style: AppTheme.body(11, weight: FontWeight.bold, color: Colors.white),
                        ),
                      )
                          : null,
                      // ✅ FIX: Use StatefulBuilder or separate handler to check context
                      onTap: () => _handleChatTap(context, chat.id, uid, otherUid),
                      onLongPress: () => _deleteChat(context, chat.id),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // ✅ NEW: Separate handler with proper context checking
  Future<void> _handleChatTap(
      BuildContext context,
      String chatId,
      String uid,
      String otherUid,
      ) async {
    try {
      // Reset unread
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .update({'unread_$uid': 0})
          .catchError((e) {
        debugPrint('Unread update error: $e');
        return null; // Don't crash if update fails
      });

      // ✅ Check if widget is still mounted before navigating
      if (!context.mounted) {
        debugPrint('Context no longer valid, skipping navigation');
        return;
      }

      // Now safe to navigate
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatId: chatId,
              otherUserId: otherUid,
            ),
          ),
        ).catchError((e) {
          debugPrint('Navigation error: $e');
        });
      }
    } catch (e) {
      debugPrint('Chat tap error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Widget _chatSkeleton() {
    return ListView.builder(
      itemCount: 6,
      itemBuilder: (_, __) => _chatSkeletonItem(),
    );
  }

  Widget _chatSkeletonItem() {
    return const ListTile(
      leading: CircleAvatar(backgroundColor: Colors.grey),
      title: SizedBox(
        height: 10,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.grey),
        ),
      ),
      subtitle: SizedBox(height: 8),
    );
  }

  void _deleteChat(BuildContext context, String chatId) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat deleted')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }
}