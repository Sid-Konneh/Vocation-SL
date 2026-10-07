/// Shared enumerations used across models, filters and the UI.
library;

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// Which side of Vocation SL a person uses.
enum UserRole {
  seeker('Find a job'),
  employer('Hire talent');

  const UserRole(this.label);
  final String label;
}

enum EmploymentType {
  fullTime('Full-time'),
  partTime('Part-time'),
  contract('Contract'),
  internship('Internship'),
  temporary('Temporary'),
  volunteer('Volunteer');

  const EmploymentType(this.label);
  final String label;
}

enum WorkMode {
  onsite('On-site'),
  hybrid('Hybrid'),
  remote('Remote');

  const WorkMode(this.label);
  final String label;
}

enum ExperienceLevel {
  entry('Entry level'),
  mid('Mid level'),
  senior('Senior'),
  lead('Lead / Manager'),
  executive('Executive');

  const ExperienceLevel(this.label);
  final String label;
}

enum Industry {
  technology('Technology'),
  healthcare('Healthcare'),
  finance('Finance & Banking'),
  education('Education'),
  ngo('NGO & Development'),
  government('Government & Public'),
  agriculture('Agriculture'),
  engineering('Engineering'),
  energy('Energy'),
  logistics('Logistics');

  const Industry(this.label);
  final String label;
}

enum DatePosted {
  any('Any time', null),
  day('Past 24 hours', 1),
  threeDays('Past 3 days', 3),
  week('Past week', 7),
  month('Past month', 30);

  const DatePosted(this.label, this.days);
  final String label;
  final int? days;
}

enum JobSort {
  relevance('Most relevant'),
  newest('Newest'),
  salary('Highest salary'),
  deadline('Closing soon');

  const JobSort(this.label);
  final String label;
}

const sierraLeoneLocations = <String>[
  'Freetown',
  'Bo',
  'Kenema',
  'Makeni',
  'Port Loko',
  'Koidu',
  'Lunsar',
  'Waterloo',
];
