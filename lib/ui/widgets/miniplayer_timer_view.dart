import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/player_provider.dart';
import 'miniplayer_flyout_container.dart';
import "../../core/utils/thumbnail_url.dart";

class MiniplayerTimerView extends StatefulWidget {
  const MiniplayerTimerView({super.key});

  @override
  State<MiniplayerTimerView> createState() => _MiniplayerTimerViewState();
}

class _MiniplayerTimerViewState extends State<MiniplayerTimerView> {
  int _minutes = 15;
  late TextEditingController _minutesController;

  @override
  void initState() {
    super.initState();
    _minutesController = TextEditingController(text: _minutes.toString());
  }

  @override
  void dispose() {
    _minutesController.dispose();
    super.dispose();
  }

  String _formatRemaining(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;
    final activeColor = player.dominantColor ?? const Color(0xFFEAB308);

    return MiniplayerFlyoutContainer(
      thumbnailUrl: track?.thumbnailUrl,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
              child: Row(
                children: [
                  const Text(
                    'Sleep Timer',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Spacer(),

            if (player.isSleepTimerActive && player.sleepTimerRemaining != null) ...[
              const Text(
                'Time remaining',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Text(
                _formatRemaining(player.sleepTimerRemaining!),
                style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w300),
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () => player.cancelSleepTimer(),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white38),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                ),
                child: const Text('Cancel Timer', style: TextStyle(color: Colors.white70, fontSize: 16)),
              ),
            ] else ...[
              const Text(
                'Set auto-close timer',
                style: TextStyle(color: Colors.white54, fontSize: 15),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CircleButton(
                    icon: Icons.remove,
                    onTap: () {
                      setState(() {
                        _minutes = (_minutes - 5).clamp(5, 180);
                        _minutesController.text = _minutes.toString();
                      });
                    },
                  ),
                  const SizedBox(width: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _minutesController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (val) {
                            final parsed = int.tryParse(val);
                            if (parsed != null) {
                              _minutes = parsed.clamp(1, 1440);
                            }
                          },
                        ),
                      ),
                      const Text(
                        'min',
                        style: TextStyle(color: Colors.white70, fontSize: 24, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  _CircleButton(
                    icon: Icons.add,
                    onTap: () {
                      setState(() {
                        _minutes = (_minutes + 5).clamp(5, 180);
                        _minutesController.text = _minutes.toString();
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  player.startSleepTimer(Duration(minutes: _minutes));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: activeColor,
                  foregroundColor: activeColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  elevation: 0,
                ),
                child: const Text('Start Timer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],

            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white38, width: 1.5),
        ),
        child: Icon(icon, color: Colors.white70, size: 22),
      ),
    );
  }
}
