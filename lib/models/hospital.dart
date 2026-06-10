class Hospital {
  final String id;
  final String name;
  final String location;
  final String? avatarUrl;
  final String? contactNumber;
  final String? description;
  final String? accreditation;
  final double rating;
  final bool isOpen24hrs;
  final List<String> facilities;
  final int reviewCount;
  final int specialistCount;

  const Hospital({
    required this.id,
    required this.name,
    required this.location,
    this.avatarUrl,
    this.contactNumber,
    this.description,
    this.accreditation,
    required this.rating,
    required this.isOpen24hrs,
    required this.facilities,
    required this.reviewCount,
    required this.specialistCount,
  });

  factory Hospital.fromJson(Map<String, dynamic> json) {
    return Hospital(
      id: json['id'] as String,
      name: json['name'] as String,
      location: json['location'] as String,
      avatarUrl: json['avatar_url'] as String?,
      contactNumber: json['contact_number'] as String?,
      description: json['description'] as String?,
      accreditation: json['accreditation'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      isOpen24hrs: json['is_open_24hrs'] as bool? ?? false,
      facilities: (json['facilities'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      reviewCount: json['review_count'] as int? ?? 0,
      specialistCount: json['specialist_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'location': location,
      'avatar_url': avatarUrl,
      'contact_number': contactNumber,
      'description': description,
      'accreditation': accreditation,
      'rating': rating,
      'is_open_24hrs': isOpen24hrs,
      'facilities': facilities,
      'review_count': reviewCount,
      'specialist_count': specialistCount,
    };
  }
}
