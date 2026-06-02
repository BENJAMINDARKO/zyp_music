import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<_LicenseNotice>>(
          future: _loadLicenses(),
          builder: (context, snapshot) {
            final notices = snapshot.data ?? const <_LicenseNotice>[];
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF191919),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'Licenses',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                          itemCount: notices.length,
                          itemBuilder: (context, index) {
                            final notice = notices[index];
                            return _LicenseCard(notice: notice);
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static Future<List<_LicenseNotice>> _loadLicenses() async {
    final notices = <_LicenseNotice>[];
    await for (final entry in LicenseRegistry.licenses) {
      final packages = entry.packages.toList()..sort();
      final text = entry.paragraphs.map((p) => p.text).join('\n\n').trim();
      notices.add(_LicenseNotice(packages: packages, text: text));
    }
    notices.sort((a, b) => a.title.compareTo(b.title));
    return notices;
  }
}

class _LicenseNotice {
  final List<String> packages;
  final String text;

  const _LicenseNotice({required this.packages, required this.text});

  String get title => packages.isEmpty ? 'Package' : packages.join(', ');
}

class _LicenseCard extends StatelessWidget {
  final _LicenseNotice notice;

  const _LicenseCard({required this.notice});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(14)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 10),
          iconColor: Colors.white,
          collapsedIconColor: Colors.white54,
          title: Text(
            notice.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            '${notice.packages.length} package${notice.packages.length == 1 ? '' : 's'}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          children: [
            SelectableText(
              notice.text.isEmpty ? 'No license text provided.' : notice.text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
