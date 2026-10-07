import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/data/demo/demo_companies.dart';
import 'package:vocation_sl/data/demo/demo_jobs.dart';
import 'package:vocation_sl/data/demo/demo_seed.dart';
import 'package:vocation_sl/models/models.dart';

void main() {
  final now = DateTime.now();
  final companies = {for (final c in demoCompanies) c.id: c};
  final jobs = buildDemoJobs(now).map((j) => j.withCompany(companies[j.companyId])).toList();

  group('demo data', () {
    test('has enough jobs, companies and locations', () {
      expect(jobs.length, greaterThanOrEqualTo(20));
      expect(demoCompanies.length, greaterThanOrEqualTo(10));
      final locations = jobs.map((j) => j.location).toSet();
      expect(locations, containsAll(['Freetown', 'Bo', 'Kenema', 'Makeni', 'Port Loko']));
      expect(jobs.map((j) => j.industry).toSet().length, greaterThanOrEqualTo(8));
    });

    test('every job references a real company and is open', () {
      for (final j in jobs) {
        expect(j.company, isNotNull, reason: j.id);
        expect(j.isClosed, isFalse, reason: j.id);
      }
    });

    test('ids are unique', () {
      expect(jobs.map((j) => j.id).toSet().length, jobs.length);
    });
  });

  group('JobFilter', () {
    test('matches title and skills', () {
      final f = const JobFilter(query: 'flutter');
      final r = f.apply(jobs);
      expect(r, isNotEmpty);
      expect(r.first.title, contains('Flutter'));
    });

    test('combines location, remote and salary filters', () {
      final f = JobFilter(locations: {'Freetown'}, workModes: {WorkMode.remote}, minSalary: 15000);
      for (final j in f.apply(jobs)) {
        expect(j.location, 'Freetown');
        expect(j.workMode, WorkMode.remote);
        expect(j.salaryMax!, greaterThanOrEqualTo(15000));
      }
    });

    test('date posted filter excludes older jobs', () {
      final r = const JobFilter(datePosted: DatePosted.day).apply(jobs);
      for (final j in r) {
        expect(now.difference(j.postedAt).inHours, lessThanOrEqualTo(24));
      }
    });

    test('round-trips through JSON', () {
      final f = JobFilter(
        query: 'nurse',
        locations: {'Bo'},
        industries: {Industry.healthcare},
        employmentTypes: {EmploymentType.fullTime},
        experienceLevels: {ExperienceLevel.mid},
        minSalary: 5000,
        datePosted: DatePosted.week,
        sort: JobSort.salary,
      );
      expect(JobFilter.fromJson(f.toJson()).cacheKey, f.cacheKey);
    });

    test('sorts by deadline', () {
      final r = const JobFilter(sort: JobSort.deadline).apply(jobs);
      for (var i = 1; i < r.length; i++) {
        expect(!r[i].deadline.isBefore(r[i - 1].deadline), isTrue);
      }
    });
  });

  group('models', () {
    test('user and applications round-trip through JSON', () {
      final user = buildDemoUser(now);
      final back = AppUser.fromJson(user.toJson());
      expect(back.fullName, user.fullName);
      expect(back.preferences.industries, user.preferences.industries);
      for (final a in buildDemoApplications(now, user)) {
        final b = JobApplication.fromJson(a.toJson());
        expect(b.status, a.status);
        expect(b.history.length, a.history.length);
      }
    });

    test('profile completion is a percentage', () {
      final user = buildDemoUser(now);
      expect(user.completion, inInclusiveRange(0, 100));
      expect(const AppUser(id: 'x', fullName: 'A B', email: 'a@b.c').completion, lessThan(user.completion));
    });

    test('document format detection', () {
      expect(DocumentFormat.fromFileName('cv.PDF'), DocumentFormat.pdf);
      expect(DocumentFormat.fromFileName('cv.docx'), DocumentFormat.docx);
      expect(DocumentFormat.fromFileName('cv.doc'), DocumentFormat.doc);
      expect(DocumentFormat.fromFileName('cv.png'), isNull);
    });
  });
}
