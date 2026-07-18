import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../presentation/providers/equalizer_provider.dart';
import '../widgets/aurora_glass.dart';
import '../widgets/animated_eq_mini_curve.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  final List<String> _freqLabels = [
    '31', '45', '63', '90', '125', '180', '250', '355',
    '500', '710', '1k', '1.4k', '2k', '4k', '8k', '16k'
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<EqualizerProvider>(
      builder: (context, provider, child) {
        final settings = provider.settings;
        final activePreset = provider.presets.firstWhere(
          (p) => p.id == settings.selectedPresetId,
          orElse: () => provider.presets.first,
        );

        final String activePresetName = settings.selectedPresetId == 'custom'
            ? 'Custom'
            : activePreset.name;
        final String activePresetDesc = settings.selectedPresetId == 'custom'
            ? 'Fine tuned manually'
            : activePreset.description;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(PhosphorIconsRegular.caretLeft, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Column(
              children: [
                Text(
                  'SETTINGS • AUDIO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: ZypAuroraColors.cyan.withOpacity(0.85),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Equalizer',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(PhosphorIconsRegular.question, color: Colors.white),
                onPressed: () {},
              ),
            ],
          ),
          body: Stack(
            children: [
              // Aurora background circles
              Positioned(
                top: 40,
                left: -30,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ZypAuroraColors.pink.withOpacity(0.12),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: -40,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ZypAuroraColors.cyan.withOpacity(0.10),
                  ),
                ),
              ),
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  // 1. Breadcrumbs path
                  _buildBreadcrumbs(),
                  const SizedBox(height: 12),

                  // 2. Equalizer Hero Card
                  _buildHeroCard(settings),
                  const SizedBox(height: 16),

                  // 3. Enabled State Switch
                  _buildEnabledCard(provider),
                  const SizedBox(height: 16),

                  if (settings.enabled) ...[
                    // 4. Presets Rail Header
                    _buildSectionHeader('Presets', 'tap to apply'),
                    
                    // Presets Horizontal list
                    _buildPresetsRail(provider),
                    const SizedBox(height: 16),

                    // 5. 16-band Equalizer Panel
                    _buildSectionHeader('16-band equalizer', null, onReset: () {
                      provider.selectPreset('prism');
                    }),
                    _buildEqualizerPanel(provider, activePresetName, activePresetDesc),
                    const SizedBox(height: 16),

                    // 6. Preamp, Bass boost & Virtualizer sliders
                    _buildPreampCard(provider),
                    const SizedBox(height: 16),

                    // 7. Toggle Switches Grid (Limiter & Per-device EQ)
                    _buildTogglesGrid(provider),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBreadcrumbs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildCrumbChip('Settings', false),
          _buildCrumbArrow(),
          _buildCrumbChip('Audio', false),
          _buildCrumbArrow(),
          _buildCrumbChip('Equalizer', true),
        ],
      ),
    );
  }

  Widget _buildCrumbChip(String text, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? Colors.transparent : Colors.white.withOpacity(0.11),
        ),
        gradient: active
            ? const LinearGradient(
                colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
              )
            : null,
        color: active ? null : Colors.white.withOpacity(0.065),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: active ? const Color(0xFF080711) : Colors.white.withOpacity(0.60),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildCrumbArrow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Icon(
        PhosphorIconsRegular.caretRight,
        size: 12,
        color: Colors.white.withOpacity(0.3),
      ),
    );
  }

  Widget _buildHeroCard(EqualizerSettings settings) {
    return AuroraGlass(
      borderRadius: 34,
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _buildHeroTag('16-BAND'),
                    const SizedBox(width: 8),
                    _buildHeroTag('CUSTOM TUNING'),
                  ],
                ),
                const SizedBox(height: 12),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1.5,
                      height: 1.0,
                      fontFamily: 'Inter',
                    ),
                    children: [
                      const TextSpan(text: 'Shape your ', style: TextStyle(color: Colors.white)),
                      TextSpan(
                        text: 'soundprint.',
                        style: TextStyle(
                          foreground: Paint()
                            ..shader = const LinearGradient(
                              colors: [Colors.white, ZypAuroraColors.cyan, ZypAuroraColors.pink, ZypAuroraColors.peach],
                            ).createShader(const Rect.fromLTWH(0, 0, 300, 40)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Use presets or fine tune all 16 bands with ZYP's Aurora equalizer.",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // EQ visualizer orb
          Container(
            width: 110,
            height: 110,
            transform: Matrix4.rotationZ(0.08),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
              color: Colors.white.withOpacity(0.13),
              boxShadow: [
                BoxShadow(
                  color: ZypAuroraColors.violet.withOpacity(0.25),
                  blurRadius: 44,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            padding: const EdgeInsets.all(10),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(23),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF05040B).withOpacity(0.72),
                    Colors.white.withOpacity(0.08),
                  ],
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: AnimatedEqMiniCurve(
                values: settings.bandGains,
                height: 60,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.17)),
        color: Colors.white.withOpacity(0.095),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: Colors.white70,
        ),
      ),
    );
  }

  Widget _buildEnabledCard(EqualizerProvider provider) {
    final enabled = provider.settings.enabled;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        color: Colors.white.withOpacity(0.06),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: const Text(
          'Equalizer enabled',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.35,
            color: Colors.white,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            'Applied globally to playback, downloads, queue, and Auto-DJ sessions.',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: Colors.white.withOpacity(0.62),
            ),
          ),
        ),
        trailing: Switch(
          value: enabled,
          activeColor: ZypAuroraColors.cyan,
          activeTrackColor: ZypAuroraColors.cyan.withOpacity(0.3),
          inactiveThumbColor: Colors.white54,
          inactiveTrackColor: Colors.white10,
          onChanged: (val) {
            provider.setEnabled(val);
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String? subtitle, {VoidCallback? onReset}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 2, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.55,
              color: Colors.white,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: const TextStyle(
                color: ZypAuroraColors.cyan,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            )
          else if (onReset != null)
            GestureDetector(
              onTap: onReset,
              child: const Text(
                'Reset',
                style: TextStyle(
                  color: ZypAuroraColors.cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPresetsRail(EqualizerProvider provider) {
    final activeId = provider.settings.selectedPresetId;
    final allPresets = [
      ...provider.presets,
      const EqualizerPreset(
        id: 'custom',
        name: 'Custom',
        description: 'Your saved curve',
        bandGains: [2, 2, 3, 2, 1, 0, 0, 1, 2, 3, 3, 2, 1, 0, 1, 2],
        preamp: 0,
        bassBoost: 22,
        virtualizer: 20,
      )
    ];

    final colors = [
      ZypAuroraColors.cyan,
      Colors.white70,
      ZypAuroraColors.pink,
      ZypAuroraColors.lime,
      ZypAuroraColors.peach,
      ZypAuroraColors.violet,
      const Color(0xFF6EA8FF),
      const Color(0xFF20D676),
      ZypAuroraColors.pink,
    ];

    return SizedBox(
      height: 84,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: allPresets.length,
        itemBuilder: (context, index) {
          final p = allPresets[index];
          final isSelected = activeId == p.id;
          final glowColor = colors[index % colors.length];

          return Padding(
            padding: const EdgeInsets.only(right: 10.0),
            child: GestureDetector(
              onTap: () {
                provider.selectPreset(p.id);
              },
              child: Container(
                width: 128,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isSelected
                        ? ZypAuroraColors.cyan.withOpacity(0.45)
                        : Colors.white.withOpacity(0.10),
                  ),
                  color: isSelected
                      ? ZypAuroraColors.cyan.withOpacity(0.06)
                      : Colors.white.withOpacity(0.05),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: ZypAuroraColors.cyan.withOpacity(0.08),
                            blurRadius: 18,
                          )
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Glow effect circle
                    Positioned(
                      right: -34,
                      bottom: -40,
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: glowColor.withOpacity(0.16),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            p.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            p.description,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.60),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEqualizerPanel(
    EqualizerProvider provider,
    String activePresetName,
    String activePresetDesc,
  ) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        color: Colors.white.withOpacity(0.05),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Toolbar
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activePresetName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.4,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      activePresetDesc,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.60),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildMiniButton('Flat', () {
                provider.selectPreset('flat');
              }, isPrimary: false),
              const SizedBox(width: 8),
              _buildMiniButton('Save', () {
                provider.saveCustomCurve();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Custom equalizer curve saved!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }, isPrimary: true),
            ],
          ),
          const SizedBox(height: 14),

          // dB Scale Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('+12dB', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38)),
              Text('0dB', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38)),
              Text('-12dB', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38)),
            ],
          ),
          const SizedBox(height: 8),

          // Scrollable 16 vertical sliders
          SizedBox(
            height: 236,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 16,
              itemBuilder: (context, index) {
                final freq = _freqLabels[index];
                final gainVal = provider.settings.bandGains[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 9.0),
                  child: Container(
                    width: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withOpacity(0.045),
                      border: Border.all(color: Colors.white.withOpacity(0.075)),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${gainVal > 0 ? '+' : ''}${gainVal.round()}dB',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.white.withOpacity(0.70),
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: ZypAuroraColors.cyan,
                              inactiveTrackColor: Colors.white.withOpacity(0.10),
                              thumbColor: Colors.white,
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                            ),
                            child: RotatedBox(
                              quarterTurns: -1,
                              child: Slider(
                                value: gainVal,
                                min: -12,
                                max: 12,
                                divisions: 24,
                                onChanged: (newVal) {
                                  provider.setBandGain(index, newVal);
                                },
                              ),
                            ),
                          ),
                        ),
                        Text(
                          freq,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.white.withOpacity(0.48),
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

  Widget _buildMiniButton(String label, VoidCallback onTap, {required bool isPrimary}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: isPrimary ? null : Border.all(color: Colors.white.withOpacity(0.10)),
          gradient: isPrimary
              ? const LinearGradient(
                  colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
                )
              : null,
          color: isPrimary ? null : Colors.white.withOpacity(0.06),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isPrimary ? const Color(0xFF080711) : Colors.white.withOpacity(0.74),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildPreampCard(EqualizerProvider provider) {
    final settings = provider.settings;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        color: Colors.white.withOpacity(0.05),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          _buildHorizontalSliderRow(
            label: 'Preamp',
            value: settings.preamp,
            min: -12.0,
            max: 12.0,
            divisions: 24,
            valueSuffix: 'dB',
            onChanged: (newVal) {
              provider.setPreamp(newVal);
            },
          ),
          const SizedBox(height: 10),
          _buildHorizontalSliderRow(
            label: 'Bass boost',
            value: settings.bassBoost,
            min: 0.0,
            max: 100.0,
            divisions: 100,
            valueSuffix: '%',
            onChanged: (newVal) {
              provider.setBassBoost(newVal);
            },
          ),
          const SizedBox(height: 10),
          _buildHorizontalSliderRow(
            label: 'Virtualizer',
            value: settings.virtualizer,
            min: 0.0,
            max: 100.0,
            divisions: 100,
            valueSuffix: '%',
            onChanged: (newVal) {
              provider.setVirtualizer(newVal);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueSuffix,
    required ValueChanged<double> onChanged,
  }) {
    final String labelVal = '${value > 0 && valueSuffix == 'dB' ? '+' : ''}${value.round()}$valueSuffix';
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: ZypAuroraColors.cyan,
              inactiveTrackColor: Colors.white.withOpacity(0.10),
              thumbColor: Colors.white,
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            labelVal,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.white.withOpacity(0.62),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTogglesGrid(EqualizerProvider provider) {
    final settings = provider.settings;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: [
        _buildToggleCard(
          title: 'Limiter',
          subtitle: 'Prevent clipping from boosted bands.',
          glowColor: ZypAuroraColors.cyan,
          value: settings.limiterEnabled,
          onChanged: (val) {
            provider.setLimiterEnabled(val);
          },
        ),
        _buildToggleCard(
          title: 'Per-device EQ',
          subtitle: 'Remember curve for each output.',
          glowColor: ZypAuroraColors.pink,
          value: settings.perDeviceEnabled,
          onChanged: (val) {
            provider.setPerDeviceEnabled(val);
          },
        ),
      ],
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required Color glowColor,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        color: Colors.white.withOpacity(0.05),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -34,
            bottom: -38,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: glowColor.withOpacity(0.18),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.60),
                        fontSize: 10,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () => onChanged(!value),
                  child: Container(
                    width: 46,
                    height: 27,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: value
                          ? const LinearGradient(
                              colors: [ZypAuroraColors.cyan, ZypAuroraColors.lime],
                            )
                          : null,
                      color: value ? null : Colors.white.withOpacity(0.10),
                    ),
                    padding: const EdgeInsets.all(3),
                    alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      width: 21,
                      height: 21,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF07110D),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
