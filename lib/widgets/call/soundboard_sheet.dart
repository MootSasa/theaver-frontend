import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/call_models.dart';
import '../../services/call_service.dart';
import '../../services/call_state_provider.dart';
import '../../services/community_service.dart';

/// Bottom sheet modal for playing soundboard sounds during a voice/group call.
class SoundboardSheet extends StatefulWidget {
  final String callId;
  final String? communityId;

  const SoundboardSheet({
    super.key,
    required this.callId,
    this.communityId,
  });

  static Future<void> show(
    BuildContext context, {
    required String callId,
    String? communityId,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SoundboardSheet(
        callId: callId,
        communityId: communityId,
      ),
    );
  }

  @override
  State<SoundboardSheet> createState() => _SoundboardSheetState();
}

class _SoundboardSheetState extends State<SoundboardSheet> {
  List<SoundboardItem> _sounds = [];
  bool _isLoading = true;
  String? _currentlyPlayingId;

  @override
  void initState() {
    super.initState();
    _loadSounds();
  }

  Future<void> _loadSounds() async {
    final commId = widget.communityId;
    if (commId == null || commId.isEmpty || commId == '0') {
      setState(() {
        _sounds = _defaultSounds;
        _isLoading = false;
      });
      return;
    }

    final list = await CommunityService.getSoundboardSounds(commId);
    if (!mounted) return;
    setState(() {
      _sounds = [...list, ..._defaultSounds];
      _isLoading = false;
    });
  }

  static const List<SoundboardItem> _defaultSounds = [
    SoundboardItem(
      id: 'default_airhorn',
      communityId: '0',
      name: 'Гудок',
      emoji: '📢',
      audioUrl: '',
      durationMs: 1500,
    ),
    SoundboardItem(
      id: 'default_applause',
      communityId: '0',
      name: 'Аплодисменты',
      emoji: '👏',
      audioUrl: '',
      durationMs: 2500,
    ),
    SoundboardItem(
      id: 'default_rimshot',
      communityId: '0',
      name: 'Ба-дум-тсс',
      emoji: '🥁',
      audioUrl: '',
      durationMs: 1200,
    ),
    SoundboardItem(
      id: 'default_crickets',
      communityId: '0',
      name: 'Сверчки',
      emoji: '🦗',
      audioUrl: '',
      durationMs: 2000,
    ),
    SoundboardItem(
      id: 'default_tada',
      communityId: '0',
      name: 'Та-да!',
      emoji: '🎉',
      audioUrl: '',
      durationMs: 1400,
    ),
    SoundboardItem(
      id: 'default_sad_trombone',
      communityId: '0',
      name: 'Тромбон',
      emoji: '🎺',
      audioUrl: '',
      durationMs: 2200,
    ),
    SoundboardItem(
      id: 'default_drumroll',
      communityId: '0',
      name: 'Дробь',
      emoji: '🪘',
      audioUrl: '',
      durationMs: 1800,
    ),
    SoundboardItem(
      id: 'default_bell',
      communityId: '0',
      name: 'Колокольчик',
      emoji: '🔔',
      audioUrl: '',
      durationMs: 900,
    ),
  ];

  Future<void> _playSound(SoundboardItem item) async {
    setState(() => _currentlyPlayingId = item.id);
    if (mounted) {
      context.read<CallStateProvider>().playLocalSoundboardClip(
            soundId: item.id,
            soundUrl: item.audioUrl,
          );
    }
    await CallService.playSoundboard(widget.callId, item.id);
    await Future.delayed(Duration(milliseconds: item.durationMs.clamp(500, 4000)));
    if (mounted) {
      setState(() {
        if (_currentlyPlayingId == item.id) {
          _currentlyPlayingId = null;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 380,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E24),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.music_note_rounded, color: Color(0xFF00E676), size: 22),
              const SizedBox(width: 8),
              const Text(
                'Саундборд',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E676)))
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.15,
                    ),
                    itemCount: _sounds.length,
                    itemBuilder: (context, index) {
                      final item = _sounds[index];
                      final isPlaying = _currentlyPlayingId == item.id;

                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _playSound(item),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: isPlaying
                                ? const Color(0xFF00E676).withValues(alpha: 0.25)
                                : const Color(0xFF282832),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isPlaying ? const Color(0xFF00E676) : Colors.white10,
                              width: isPlaying ? 1.8 : 1,
                            ),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                item.emoji.isNotEmpty ? item.emoji : '🔊',
                                style: const TextStyle(fontSize: 26),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isPlaying ? const Color(0xFF00E676) : Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
