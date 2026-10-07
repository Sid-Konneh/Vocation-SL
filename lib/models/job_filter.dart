import 'enums.dart';
import 'job.dart';

/// Search criteria for jobs. Immutable; use [copyWith] to change.
class JobFilter {
  const JobFilter({
    this.query = '',
    this.locations = const {},
    this.employmentTypes = const {},
    this.industries = const {},
    this.experienceLevels = const {},
    this.workModes = const {},
    this.minSalary,
    this.datePosted = DatePosted.any,
    this.sort = JobSort.relevance,
    this.companyId,
  });

  final String query;
  final Set<String> locations;
  final Set<EmploymentType> employmentTypes;
  final Set<Industry> industries;
  final Set<ExperienceLevel> experienceLevels;
  final Set<WorkMode> workModes;
  final int? minSalary;
  final DatePosted datePosted;
  final JobSort sort;
  final String? companyId;

  static const empty = JobFilter();

  /// Number of active filters, excluding the text query and sort.
  int get activeCount =>
      locations.length +
      employmentTypes.length +
      industries.length +
      experienceLevels.length +
      workModes.length +
      (minSalary != null ? 1 : 0) +
      (datePosted != DatePosted.any ? 1 : 0) +
      (companyId != null ? 1 : 0);

  bool get isEmpty => query.trim().isEmpty && activeCount == 0;

  String get summary {
    final parts = <String>[
      if (query.trim().isNotEmpty) '"${query.trim()}"',
      ...locations,
      ...employmentTypes.map((e) => e.label),
      ...workModes.map((e) => e.label),
      ...industries.map((e) => e.label),
      ...experienceLevels.map((e) => e.label),
      if (minSalary != null) 'SLE ${minSalary!}+',
      if (datePosted != DatePosted.any) datePosted.label,
    ];
    return parts.isEmpty ? 'All jobs' : parts.join(' · ');
  }

  JobFilter copyWith({
    String? query,
    Set<String>? locations,
    Set<EmploymentType>? employmentTypes,
    Set<Industry>? industries,
    Set<ExperienceLevel>? experienceLevels,
    Set<WorkMode>? workModes,
    int? Function()? minSalary,
    DatePosted? datePosted,
    JobSort? sort,
    String? Function()? companyId,
  }) =>
      JobFilter(
        query: query ?? this.query,
        locations: locations ?? this.locations,
        employmentTypes: employmentTypes ?? this.employmentTypes,
        industries: industries ?? this.industries,
        experienceLevels: experienceLevels ?? this.experienceLevels,
        workModes: workModes ?? this.workModes,
        minSalary: minSalary != null ? minSalary() : this.minSalary,
        datePosted: datePosted ?? this.datePosted,
        sort: sort ?? this.sort,
        companyId: companyId != null ? companyId() : this.companyId,
      );

  JobFilter clearFilters() => JobFilter(query: query, sort: sort);

  /// Local matcher, used by the demo backend and for offline search over cache.
  bool matches(Job j, {DateTime? now}) {
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final haystack = [
        j.title,
        j.companyName,
        j.location,
        j.industry.label,
        ...j.skills,
      ].join(' ').toLowerCase();
      final terms = q.split(RegExp(r'\s+'));
      if (!terms.every(haystack.contains)) return false;
    }
    if (locations.isNotEmpty && !locations.contains(j.location)) return false;
    if (employmentTypes.isNotEmpty && !employmentTypes.contains(j.employmentType)) return false;
    if (industries.isNotEmpty && !industries.contains(j.industry)) return false;
    if (experienceLevels.isNotEmpty && !experienceLevels.contains(j.experienceLevel)) return false;
    if (workModes.isNotEmpty && !workModes.contains(j.workMode)) return false;
    if (companyId != null && j.companyId != companyId) return false;
    if (minSalary != null && (j.salaryMax ?? j.salaryMin ?? 0) < minSalary!) return false;
    final days = datePosted.days;
    if (days != null && (now ?? DateTime.now()).difference(j.postedAt).inHours > days * 24) return false;
    return true;
  }

  int relevance(Job j) {
    final q = query.trim().toLowerCase();
    var score = j.featured ? 2 : 0;
    if (q.isEmpty) return score;
    if (j.title.toLowerCase().contains(q)) score += 10;
    if (j.skills.any((s) => s.toLowerCase().contains(q))) score += 5;
    if (j.companyName.toLowerCase().contains(q)) score += 3;
    return score;
  }

  List<Job> apply(Iterable<Job> jobs) {
    final now = DateTime.now();
    final list = jobs.where((j) => matches(j, now: now)).toList();
    switch (sort) {
      case JobSort.newest:
        list.sort((a, b) => b.postedAt.compareTo(a.postedAt));
      case JobSort.salary:
        list.sort((a, b) => (b.salaryMax ?? 0).compareTo(a.salaryMax ?? 0));
      case JobSort.deadline:
        list.sort((a, b) => a.deadline.compareTo(b.deadline));
      case JobSort.relevance:
        list.sort((a, b) {
          final r = relevance(b).compareTo(relevance(a));
          return r != 0 ? r : b.postedAt.compareTo(a.postedAt);
        });
    }
    return list;
  }

  /// Stable key for caching search results.
  String get cacheKey => [
        query.trim().toLowerCase(),
        (locations.toList()..sort()).join(','),
        (employmentTypes.map((e) => e.name).toList()..sort()).join(','),
        (industries.map((e) => e.name).toList()..sort()).join(','),
        (experienceLevels.map((e) => e.name).toList()..sort()).join(','),
        (workModes.map((e) => e.name).toList()..sort()).join(','),
        minSalary ?? '',
        datePosted.name,
        sort.name,
        companyId ?? '',
      ].join('|');

  factory JobFilter.fromJson(Map<String, dynamic> j) => JobFilter(
        query: j['query'] as String? ?? '',
        locations: {...(j['locations'] as List? ?? const []).cast<String>()},
        employmentTypes: {
          for (final n in (j['employment_types'] as List? ?? const []))
            enumByName(EmploymentType.values, n, EmploymentType.fullTime)
        },
        industries: {
          for (final n in (j['industries'] as List? ?? const [])) enumByName(Industry.values, n, Industry.technology)
        },
        experienceLevels: {
          for (final n in (j['experience_levels'] as List? ?? const []))
            enumByName(ExperienceLevel.values, n, ExperienceLevel.mid)
        },
        workModes: {for (final n in (j['work_modes'] as List? ?? const [])) enumByName(WorkMode.values, n, WorkMode.onsite)},
        minSalary: (j['min_salary'] as num?)?.toInt(),
        datePosted: enumByName(DatePosted.values, j['date_posted'], DatePosted.any),
        sort: enumByName(JobSort.values, j['sort'], JobSort.relevance),
        companyId: j['company_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'query': query,
        'locations': locations.toList(),
        'employment_types': employmentTypes.map((e) => e.name).toList(),
        'industries': industries.map((e) => e.name).toList(),
        'experience_levels': experienceLevels.map((e) => e.name).toList(),
        'work_modes': workModes.map((e) => e.name).toList(),
        'min_salary': minSalary,
        'date_posted': datePosted.name,
        'sort': sort.name,
        'company_id': companyId,
      };
}

class PageResult<T> {
  const PageResult({required this.items, required this.page, required this.hasMore, this.total});
  final List<T> items;
  final int page;
  final bool hasMore;
  final int? total;
}
