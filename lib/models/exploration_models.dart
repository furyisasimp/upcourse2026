class SourceLink {
  final String name;
  final String url;
  SourceLink({required this.name, required this.url});

  factory SourceLink.fromJson(Map<String, dynamic> j) =>
      SourceLink(name: j['name'] ?? '', url: j['url'] ?? '');
}

class Strand {
  final String code;
  final String name;
  final String summary;
  final String badgeColor; // hex
  final String gradientStart; // hex
  final String gradientEnd; // hex
  final List<String> points;
  final List<String> sampleCurriculum;
  final List<String> entryRoles;
  final List<String> skills;
  final List<SourceLink> sources;

  Strand({
    required this.code,
    required this.name,
    required this.summary,
    required this.badgeColor,
    required this.gradientStart,
    required this.gradientEnd,
    required this.points,
    required this.sampleCurriculum,
    required this.entryRoles,
    required this.skills,
    required this.sources,
  });

  factory Strand.fromRow(Map<String, dynamic> r) => Strand(
    code: r['code'],
    name: r['name'] ?? '',
    summary: r['summary'] ?? '',
    badgeColor: r['badge_color'] ?? '#1976D2',
    gradientStart: r['gradient_start'] ?? '#B3E5FC',
    gradientEnd: r['gradient_end'] ?? '#81D4FA',
    points: List<String>.from(r['points'] ?? const []),
    sampleCurriculum: List<String>.from(r['sample_curriculum'] ?? const []),
    entryRoles: List<String>.from(r['entry_roles'] ?? const []),
    skills: List<String>.from(r['skills'] ?? const []),
    sources:
        (r['sources'] as List<dynamic>? ?? const [])
            .map((e) => SourceLink.fromJson(e as Map<String, dynamic>))
            .toList(),
  );
}

class Pathway {
  final String code;
  final String name;
  final String subtitle;
  final List<String> outcomes;
  final List<String> entryRoles;
  final List<String> stackSuggestions;
  final List<SourceLink> sources;

  Pathway({
    required this.code,
    required this.name,
    required this.subtitle,
    required this.outcomes,
    required this.entryRoles,
    required this.stackSuggestions,
    required this.sources,
  });

  factory Pathway.fromRow(Map<String, dynamic> r) => Pathway(
    code: r['code'],
    name: r['name'] ?? '',
    subtitle: r['subtitle'] ?? '',
    outcomes: List<String>.from(r['outcomes'] ?? const []),
    entryRoles: List<String>.from(r['entry_roles'] ?? const []),
    stackSuggestions: List<String>.from(r['stack_suggestions'] ?? const []),
    sources:
        (r['sources'] as List<dynamic>? ?? const [])
            .map((e) => SourceLink.fromJson(e as Map<String, dynamic>))
            .toList(),
  );
}
