import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/player_provider.dart';
import 'apple_music_sheet.dart';

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
    final activeColor = player.dominantColor ?? const Color(0xFFEAB308);

    return AppleMusicSheet(
      title: 'Sleep Timer',
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            if (player.isSleepTimerActive && player.sleepTimerRemaining != null) ...[
              Text(
                'Time remaining',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 14),
              ),
              const SizedBox(height: 12),
              Text(
                _formatRemaining(player.sleepTimerRemaining!),
                style: TextStyle(fontSize: 64, fontWeight: FontWeight.w300),
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () => player.cancelSleepTimer(),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                ),
                child: Text('Cancel Timer', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.70), fontSize: 16)),
              ),
            ] else ...[
              Text(
                'Set auto-close timer',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), fontSize: 15),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CircleButton(
                    icon: PhosphorIconsRegular.minus,
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
                          style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
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
                      Text(
                        'min',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.70), fontSize: 24, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  _CircleButton(
                    icon: PhosphorIconsRegular.plus,
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
                  foregroundColor: activeColor.computeLuminance() > 0.5 ? Colors.black : Theme.of(context).colorScheme.onSurface,
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
          border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.38), width: 1.5),
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.70), size: 22),
      ),
    );
  }
}
