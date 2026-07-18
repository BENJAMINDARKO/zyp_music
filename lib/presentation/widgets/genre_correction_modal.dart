import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/video.dart';
import '../../core/services/genre_feedback_service.dart';
import '../../core/services/genre_proximity_graph.dart';

void showGenreCorrectionModal(BuildContext context, Track track) {
  final graph = context.read<GenreProximityGraph>();
  final List<String> allCanonicalGenres = graph.knownGenres.toList()..sort();
  final List<String> quickShortcuts = [
    'Highlife',
    'Hiplife',
    'Asakaa',
    'Afrobeats',
    'Dancehall',
    'Hip-Hop',
  ];
  final selectedGenres = <String>[];
  String targetType = 'track';
  String? selectedCountry = track.country;
  final Map<String, String> countryList = {
    'GH': '\u{1F1EC}\u{1F1ED} Ghana',
    'NG': '\u{1F1F3}\u{1F1EC} Nigeria',
    'KE': '\u{1F1F0}\u{1F1EA} Kenya',
    'ZA': '\u{1F1FF}\u{1F1E6} South Africa',
    'TZ': '\u{1F1F9}\u{1F1FF} Tanzania',
    'UG': '\u{1F1FA}\u{1F1EC} Uganda',
    'US': '\u{1F1FA}\u{1F1F8} United States',
    'GB': '\u{1F1EC}\u{1F1E7} United Kingdom',
    'CA': '\u{1F1E8}\u{1F1E6} Canada',
    'BR': '\u{1F1E7}\u{1F1F7} Brazil',
  };
  String searchQuery = '';
  final searchController = TextEditingController();

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    useRootNavigator: true,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF17171C),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Material(
              color: Colors.transparent,
              child: SafeArea(
                top: false,
                child: StatefulBuilder(
                  builder: (ctx, setModalState) {
                    final filteredSearch = searchQuery.isEmpty
                        ? <String>[]
                        : allCanonicalGenres
                              .where(
                                (g) =>
                                    g.toLowerCase().contains(
                                      searchQuery.toLowerCase(),
                                    ) &&
                                    !selectedGenres.contains(g),
                              )
                              .take(4)
                              .toList();

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                        top: 20,
                        left: 20,
                        right: 20,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Suggest Metadata Edit',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setModalState(
                                      () => targetType = 'track',
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: targetType == 'track'
                                            ? Colors.amber.withValues(
                                                alpha: 0.15,
                                              )
                                            : const Color(0xFF202026),
                                        border: Border.all(
                                          color: targetType == 'track'
                                              ? Colors.amber
                                              : Colors.transparent,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Center(
                                        child: Text(
                                          'Just this track',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setModalState(
                                      () => targetType = 'artist',
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: targetType == 'artist'
                                            ? Colors.amber.withValues(
                                                alpha: 0.15,
                                              )
                                            : const Color(0xFF202026),
                                        border: Border.all(
                                          color: targetType == 'artist'
                                              ? Colors.amber
                                              : Colors.transparent,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'All songs by ${track.author ?? "Artist"}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Select Country of Origin:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.amber,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF202026),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: selectedCountry,
                                  hint: const Text(
                                    'Select country...',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                  ),
                                  dropdownColor: const Color(0xFF17171C),
                                  icon: const Icon(
                                    Icons.arrow_drop_down,
                                    color: Colors.amber,
                                  ),
                                  isExpanded: true,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                  onChanged: (String? newValue) {
                                    setModalState(() {
                                      selectedCountry = newValue;
                                    });
                                  },
                                  items: countryList.entries
                                      .map<DropdownMenuItem<String>>((entry) {
                                        return DropdownMenuItem<String>(
                                          value: entry.key,
                                          child: Text(entry.value),
                                        );
                                      })
                                      .toList(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Search All ${allCanonicalGenres.length} Genres:',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.amber,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: searchController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Type to filter (e.g. Bongo Flava, Drill)...',
                                hintStyle: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: Colors.grey,
                                ),
                                fillColor: const Color(0xFF202026),
                                filled: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (val) =>
                                  setModalState(() => searchQuery = val),
                            ),
                            if (filteredSearch.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF202026),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: filteredSearch.map((genre) {
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        genre,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                      trailing: const Icon(
                                        Icons.add,
                                        color: Colors.green,
                                        size: 18,
                                      ),
                                      onTap: () {
                                        setModalState(() {
                                          selectedGenres.add(genre);
                                          searchQuery = '';
                                          searchController.clear();
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                            if (selectedGenres.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Text(
                                'Active Selection:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: selectedGenres
                                    .map(
                                      (g) => InputChip(
                                        label: Text(
                                          g,
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        backgroundColor: Colors.amber,
                                        deleteIcon: const Icon(
                                          Icons.close,
                                          size: 12,
                                          color: Colors.black,
                                        ),
                                        onDeleted: () => setModalState(
                                          () => selectedGenres.remove(g),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                            const SizedBox(height: 16),
                            const Text(
                              'Popular Shortcuts:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: quickShortcuts.map((genre) {
                                final isSelected = selectedGenres.contains(
                                  genre,
                                );
                                return FilterChip(
                                  label: Text(genre),
                                  selected: isSelected,
                                  selectedColor: Colors.amber,
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.black
                                        : Colors.white,
                                    fontSize: 12,
                                  ),
                                  backgroundColor: const Color(0xFF202026),
                                  onSelected: (selected) {
                                    setModalState(() {
                                      if (selected) {
                                        if (!selectedGenres.contains(genre)) {
                                          selectedGenres.add(genre);
                                        }
                                      } else {
                                        selectedGenres.remove(genre);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: selectedGenres.isEmpty
                                    ? null
                                    : () async {
                                        final service = GenreFeedbackService();
                                        bool success;
                                        if (targetType == 'track') {
                                          success = await service
                                              .submitTrackSuggestion(
                                                track: track,
                                                genres: List<String>.from(
                                                  selectedGenres,
                                                ),
                                                country: selectedCountry,
                                              );
                                        } else {
                                          success = await service
                                              .submitArtistSuggestion(
                                                artistName:
                                                    track.author ??
                                                    'Unknown Artist',
                                                genres: List<String>.from(
                                                  selectedGenres,
                                                ),
                                                country: selectedCountry,
                                              );
                                        }
                                        if (ctx.mounted) {
                                          Navigator.of(ctx).pop();
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                success
                                                    ? 'Suggestion logged! Updates apply on approval.'
                                                    : 'Network error. Suggestion cached.',
                                              ),
                                              backgroundColor: success
                                                  ? Colors.green
                                                  : Colors.red,
                                            ),
                                          );
                                        }
                                      },
                                child: const Text(
                                  'Submit Suggestion',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: child,
      );
    },
  );
}
