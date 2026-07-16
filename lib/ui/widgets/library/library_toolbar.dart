import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../aurora_glass.dart';

class LibraryToolbar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSortPressed;
  final VoidCallback onFilterPressed;
  final String hintText;

  const LibraryToolbar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSortPressed,
    required this.onFilterPressed,
    this.hintText = 'Search your library...',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // 1. Search Box Pill
          Expanded(
            child: AuroraGlass(
              borderRadius: 999,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsRegular.magnifyingGlass,
                    color: Colors.white.withOpacity(0.54),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      onChanged: onSearchChanged,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.38)),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  if (searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        searchController.clear();
                        onSearchChanged('');
                      },
                      child: Icon(
                        PhosphorIconsRegular.x,
                        color: Colors.white.withOpacity(0.54),
                        size: 16,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // 2. Sort Button
          GestureDetector(
            onTap: onSortPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: AuroraGlass(
                borderRadius: 14,
                padding: EdgeInsets.zero,
                child: Center(
                  child: Icon(
                    PhosphorIconsRegular.sortAscending,
                    color: Colors.white.withOpacity(0.8),
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 3. Filter Button
          GestureDetector(
            onTap: onFilterPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: AuroraGlass(
                borderRadius: 14,
                padding: EdgeInsets.zero,
                child: Center(
                  child: Icon(
                    PhosphorIconsRegular.funnel,
                    color: Colors.white.withOpacity(0.8),
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
