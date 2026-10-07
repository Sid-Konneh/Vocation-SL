import 'enums.dart';

enum CompanyStatus {
  pending('Awaiting approval'),
  approved('Approved'),
  rejected('Not approved'),
  suspended('Suspended');

  const CompanyStatus(this.label);
  final String label;
}

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
    this.status = CompanyStatus.approved,
    this.email = '',
    this.phone = '',
    this.address = '',
    this.tin = '',
    this.ownerId,
    this.logoUrl,
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

  // Employer account fields.
  final CompanyStatus status;
  final String email;
  final String phone;
  final String address;

  /// Taxpayer identification number (optional, not shown in the app).
  final String tin;
  final String? ownerId;

  /// Uploaded logo image (public URL, or a data: URI in demo mode).
  final String? logoUrl;

  bool get isApproved => status == CompanyStatus.approved;

  String get initials {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, parts.first.length.clamp(1, 2)).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Company copyWith({
    String? name,
    Industry? industry,
    String? location,
    String? about,
    String? size,
    int? founded,
    String? website,
    int? brandColor,
    String? email,
    String? phone,
    String? address,
    String? tin,
    String? Function()? logoUrl,
  }) =>
      Company(
        id: id,
        name: name ?? this.name,
        industry: industry ?? this.industry,
        location: location ?? this.location,
        about: about ?? this.about,
        size: size ?? this.size,
        founded: founded ?? this.founded,
        website: website ?? this.website,
        brandColor: brandColor ?? this.brandColor,
        verified: verified,
        status: status,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        tin: tin ?? this.tin,
        ownerId: ownerId,
        logoUrl: logoUrl != null ? logoUrl() : this.logoUrl,
      );

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
        status: enumByName(CompanyStatus.values, j['status'], CompanyStatus.approved),
        email: j['email'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        address: j['address'] as String? ?? '',
        tin: j['tin'] as String? ?? '',
        ownerId: j['owner_id'] as String?,
        logoUrl: j['logo_url'] as String?,
      );

  /// Catalogue fields only (what job seekers and the seed script use).
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
        if (logoUrl != null) 'logo_url': logoUrl,
      };

  /// Fields an employer may write. Status, verification and ownership are
  /// controlled by the database.
  Map<String, dynamic> toEmployerJson() => {
        'name': name,
        'industry': industry.name,
        'location': location,
        'about': about,
        'size': size,
        'founded': founded,
        'website': website,
        'brand_color': brandColor,
        'email': email,
        'phone': phone,
        'address': address,
        // logo_url is written separately by uploadLogo().
      };
}
