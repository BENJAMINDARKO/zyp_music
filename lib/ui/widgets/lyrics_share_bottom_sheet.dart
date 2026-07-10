import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'lyrics_share_card.dart';

/// The six palette swatches offered to the user.
/// The first slot is always the album-art dominant colour (passed in).
List<Color> _buildSwatches(Color dominant) => [
      dominant, // default: album art colour
      const Color(0xFF0A0A0A), // near-black
      const Color(0xFF0D1B2A), // deep navy
      const Color(0xFF1A0A2E), // deep purple
      const Color(0xFF0F2318), // forest green
      const Color(0xFF2A0A0A), // deep crimson
    ];

class LyricsShareBottomSheet extends StatefulWidget {
  final List<String> selectedLines;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final Color dominantColor;

  const LyricsShareBottomSheet({
    super.key,
    required this.selectedLines,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    required this.dominantColor,
  });

  static Future<void> show(
    BuildContext context, {
    required List<String> selectedLines,
    required String title,
    required String artist,
    String? thumbnailUrl,
    required Color dominantColor,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LyricsShareBottomSheet(
        selectedLines: selectedLines,
        title: title,
        artist: artist,
        thumbnailUrl: thumbnailUrl,
        dominantColor: dominantColor,
      ),
    );
  }

  @override
  State<LyricsShareBottomSheet> createState() =>
      _LyricsShareBottomSheetState();
}

class _LyricsShareBottomSheetState extends State<LyricsShareBottomSheet> {
  final _repaintKey = GlobalKey();
  late Color _selectedColor;
  bool _isSharing = false;
  late List<Color> _swatches;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.dominantColor;
    _swatches = _buildSwatches(widget.dominantColor);
  }

  Future<void> _share() async {
    setState(() => _isSharing = true);
    try {
      // Give Flutter one frame to settle the repaint boundary at full size
      await Future.delayed(const Duration(milliseconds: 80));
      final bytes = await LyricsShareCard.capture(_repaintKey);
      if (bytes == null || !mounted) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/zyp_lyrics_share.png');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: '${widget.title} — ${widget.artist}\n\n'
              '${widget.selectedLines.join('\n')}\n\nvia Zyp Music',
        ),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheetBg = darkenColor(_selectedColor, maxLightness: 0.12);

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: textColorFor(sheetBg).withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Live card preview — scrollable if tall
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: LyricsShareCard(
                repaintKey: _repaintKey,
                selectedLines: widget.selectedLines,
                title: widget.title,
                artist: widget.artist,
                thumbnailUrl: widget.thumbnailUrl,
                baseColor: _selectedColor,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Colour swatches
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: _swatches.asMap().entries.map((e) {
                final i = e.key;
                final color = e.value;
                final darkened = darkenColor(color);
                final isSelected = darkened == darkenColor(_selectedColor) ||
                    (i == 0 && _selectedColor == widget.dominantColor);
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedColor = color),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 36,
                      decoration: BoxDecoration(
                        color: darkened,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? Colors.white
                              : Colors.white.withOpacity(0.15),
                          width: isSelected ? 2.5 : 1,
                        ),
                      ),
                      child: isSelected
                          ? Icon(Icons.check,
                              size: 16,
                              color: textColorFor(darkened).withOpacity(0.8))
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 20),

          // Share button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      textColorFor(sheetBg).withOpacity(0.12),
                  foregroundColor: textColorFor(sheetBg),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: textColorFor(sheetBg).withOpacity(0.25),
                    ),
                  ),
                ),
                onPressed: _isSharing ? null : _share,
                icon: _isSharing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: textColorFor(sheetBg),
                        ),
                      )
                    : const Icon(Icons.share_rounded, size: 20),
                label: Text(
                  _isSharing ? 'Preparing…' : 'Share',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
