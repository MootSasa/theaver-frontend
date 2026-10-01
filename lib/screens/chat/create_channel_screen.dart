// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/chat_service.dart';
import 'channel_screen.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../utils/swipe_back_route.dart';

class CreateChannelScreen extends StatefulWidget {
  const CreateChannelScreen({Key? key}) : super(key: key);

  @override
  State<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends State<CreateChannelScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  
  // Channel settings
  bool _isPublic = true;
  bool _enableSignatures = false;
  bool _enableComments = true;
  bool _enableHistory = true;
  
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createChannel() async {
    final l10n = context.l10n;
    
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('channel_name_required'))),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Create channel via API
      final result = await ChatService.createChat(
        chatType: 'channel',
        name: _nameController.text.trim(),
        participantIds: [], // Channel creator is added automatically
      );

      if (mounted) {
        if (result['success'] == true) {
          final chat = result['chat'] as Chat;
          Navigator.pushReplacement(
            context,
            SwipeBackPageRoute(
              builder: (_) => ChannelScreen(
                channelId: chat.id,
                channelName: chat.name,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Failed to create channel')),
          );
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('chat_new_channel')),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createChannel,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    l10n.translate('create'),
                    style: const TextStyle(color: Colors.white),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Channel avatar and name
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () {
                      // TODO: Implement image picker
                    },
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: const Color(0xFF0088CC),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 32,
                          ),
                          Text(
                            l10n.translate('channel_add_photo'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            
            // Channel name
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.translate('channel_name'),
                hintText: l10n.translate('channel_name_hint'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.campaign),
              ),
            ),
            const SizedBox(height: 16),
            
            // Channel description
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: l10n.translate('channel_description'),
                hintText: l10n.translate('channel_description_hint'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.description),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            
            // Channel type section
            Text(
              l10n.translate('channel_type'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            // Public channel option
            RadioListTile<bool>(
              title: Text(l10n.translate('channel_public')),
              subtitle: Text(l10n.translate('channel_public_desc')),
              value: true,
              groupValue: _isPublic,
              onChanged: (value) => setState(() => _isPublic = value!),
              activeColor: const Color(0xFF0088CC),
            ),
            
            // Private channel option
            RadioListTile<bool>(
              title: Text(l10n.translate('channel_private')),
              subtitle: Text(l10n.translate('channel_private_desc')),
              value: false,
              groupValue: _isPublic,
              onChanged: (value) => setState(() => _isPublic = value!),
              activeColor: const Color(0xFF0088CC),
            ),
            const SizedBox(height: 24),
            
            // Channel settings section
            Text(
              l10n.translate('channel_settings'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            // Enable signatures
            _buildSettingsTile(
              icon: Icons.edit,
              title: l10n.translate('channel_signatures'),
              subtitle: l10n.translate('channel_signatures_desc'),
              value: _enableSignatures,
              onChanged: (value) => setState(() => _enableSignatures = value),
            ),
            
            // Enable comments
            _buildSettingsTile(
              icon: Icons.comment,
              title: l10n.translate('channel_comments'),
              subtitle: l10n.translate('channel_comments_desc'),
              value: _enableComments,
              onChanged: (value) => setState(() => _enableComments = value),
            ),
            
            // Enable history
            _buildSettingsTile(
              icon: Icons.history,
              title: l10n.translate('channel_history'),
              subtitle: l10n.translate('channel_history_desc'),
              value: _enableHistory,
              onChanged: (value) => setState(() => _enableHistory = value),
            ),
            const SizedBox(height: 24),
            
            // Info box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF0088CC).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.translate('channel_info_box'),
                      style: TextStyle(color: Colors.blue[700]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFF0088CC)),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: AdaptiveSwitch(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF0088CC),
      ),
    );
  }
}
