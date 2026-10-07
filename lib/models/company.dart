import 'enums.dart';

class Company {
  const Company({
    required this.id,
    required this.name,
    required this.industry,
    required this.location,
    required this.about,
    required this.size,
    required this.founded,
    required this.website,
    required this.brandColor,
    this.verified = false,
  });

  final String id;
  final String name;
  final Industry industry;
  final String location;
  final String about;
  final String size;
  final int founded;
  final String website;

  /// ARGB colour used to draw the generated company logo.
  final int brandColor;
  final bool verified;

  String get initials {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.substring(0, 2).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  factory Company.fromJson(Map<String, dynamic> j) => Company(
        id: j['id'] as String,
        name: j['name'] as String,
        industry: enumByName(Industry.values, j['industry'], Industry.technology),
        location: j['location'] as String? ?? '',
        about: j['about'] as String? ?? '',
        size: j['size'] as String? ?? '',
        founded: (j['founded'] as num?)?.toInt() ?? 0,
        website: j['website'] as String? ?? '',
        brandColor: (j['brand_color'] as num?)?.toInt() ?? 0xFF2F6B2A,
        verified: j['verified'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'industry': industry.name,
        'location': location,
        'about': about,
        'size': size,
        'founded': founded,
        'website': website,
        'brand_color': brandColor,
        'verified': verified,
      };
}
