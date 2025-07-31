import 'package:flutter/material.dart';
import 'package:slt_chat/service/local_db_helper.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

enum DeleteAction { deleteForMe, deleteForEveryone, cancel }

class DeleteModule {
  static Future<DeleteAction?> showDeleteDialog({
    required BuildContext context,
    required bool isMyMessage,
    required bool isOnline,
  }) async {
    final action = await showModalBottomSheet<DeleteAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => _DeleteOptionsBottomSheet(
            isMyMessage: isMyMessage,
            isOnline: isOnline,
          ),
    );

    return action;
  }

  static Future<void> deleteMessage({
    required String messageId,
    required String tempId,
    required String senderId,
    required String receiverId,
    required DeleteAction action,
    required LocalDBHelper localDB,
    required IO.Socket socket,
  }) async {
    try {
      // Update local database first
      await localDB.deleteMessage(tempId);

      if (action == DeleteAction.deleteForEveryone && socket.connected) {
        // Send delete request to server
        socket.emit('delete_message', {
          'message_id': messageId,
          'temp_id': tempId,
          'sender_id': senderId,
          'receiver_id': receiverId,
          'action': 'delete_for_everyone',
        });
      }
    } catch (e) {
      print('Error deleting message: $e');
    }
  }
}

class _DeleteOptionsBottomSheet extends StatelessWidget {
  final bool isMyMessage;
  final bool isOnline;

  const _DeleteOptionsBottomSheet({
    required this.isMyMessage,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMyMessage)
              _DeleteOptionTile(
                icon: Icons.delete_outline,
                text: 'Delete for everyone',
                color: Colors.red,
                onTap:
                    () =>
                        Navigator.pop(context, DeleteAction.deleteForEveryone),
                /* enabled: isOnline, */
              ),
            _DeleteOptionTile(
              icon: Icons.delete,
              text: 'Delete for me',
              color: Colors.red,
              onTap: () => Navigator.pop(context, DeleteAction.deleteForMe),
            ),
            const Divider(height: 1),
            _DeleteOptionTile(
              icon: Icons.close,
              text: 'Cancel',
              onTap: () => Navigator.pop(context, DeleteAction.cancel),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DeleteOptionTile extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final Color? color;
  final bool enabled;

  const _DeleteOptionTile({
    required this.icon,
    required this.text,
    required this.onTap,
    this.color,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: enabled ? color : Colors.grey),
      title: Text(
        text,
        style: TextStyle(color: enabled ? color : Colors.grey, fontSize: 16),
      ),
      onTap: enabled ? onTap : null,
    );
  }
}
