class StudentProfile {
  final String fullName;
  final String? photoUrl;
  final List<ProfileSection> sections;

  const StudentProfile({
    required this.fullName,
    required this.sections,
    this.photoUrl,
  });
}

class ProfileSection {
  final String id;
  final String title;
  final List<ProfileItem> items;
  final List<ProfileImage> images;

  const ProfileSection({
    required this.id,
    required this.title,
    required this.items,
    this.images = const [],
  });
}

class ProfileItem {
  final String label;
  final String value;

  const ProfileItem({required this.label, required this.value});
}

class ProfileImage {
  final String source;

  const ProfileImage(this.source);

  bool get isDataUri => source.startsWith('data:image/');
}
