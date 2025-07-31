import 'package:flutter/material.dart';

enum DeleteGroupAction { deleteForEveryone, deleteForMe, cancel }

class DeleteGroupMessageSheet extends StatelessWidget {
  final bool isMyMessage;
  final bool isAdmin;
  final bool isOnline;

  const DeleteGroupMessageSheet({
    super.key,
    required this.isMyMessage,
    this.isAdmin = false,
    this.isOnline = true,
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
            if (isMyMessage || isAdmin)
              _DeleteOptionTile(
                icon: Icons.delete_outline,
                text: 'Delete for everyone',
                color: Colors.red,
                onTap:
                    () => Navigator.pop(
                      context,
                      DeleteGroupAction.deleteForEveryone,
                    ),
                enabled: isOnline,
              ),
            _DeleteOptionTile(
              icon: Icons.delete,
              text: 'Delete for me',
              color: Colors.red,
              onTap:
                  () => Navigator.pop(context, DeleteGroupAction.deleteForMe),
            ),
            const Divider(height: 1),
            _DeleteOptionTile(
              icon: Icons.close,
              text: 'Cancel',
              onTap: () => Navigator.pop(context, DeleteGroupAction.cancel),
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
  final Color? color;
  final VoidCallback onTap;
  final bool enabled;

  const _DeleteOptionTile({
    required this.icon,
    required this.text,
    this.color,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: enabled ? color : Colors.grey),
      title: Text(
        text,
        style: TextStyle(
          color: enabled ? color : Colors.grey,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: enabled ? onTap : null,
    );
  }
}
