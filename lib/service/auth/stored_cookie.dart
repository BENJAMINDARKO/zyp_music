class StoredCookie {
  final String name;
  final String value;
  final String domain;
  final String path;

  const StoredCookie({
    required this.name,
    required this.value,
    this.domain = '',
    this.path = '/',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
      };

  factory StoredCookie.fromJson(Map<String, dynamic> json) => StoredCookie(
        name: json['name'] as String,
        value: json['value'] as String,
        domain: json['domain'] as String? ?? '',
        path: json['path'] as String? ?? '/',
      );
}
