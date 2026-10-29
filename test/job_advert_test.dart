import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/admin/scam_flags.dart';
import 'package:vocation_sl/employer/data/demo_employer_backend.dart';
import 'package:vocation_sl/models/models.dart';

const _pdfUrl = 'https://x.supabase.co/storage/v1/object/public/job-adverts/u1/1730000000000-advert.pdf';
const _photoUrl = 'https://x.supabase.co/storage/v1/object/public/job-adverts/u1/1730000000000-advert.jpg';

Job _job({String description = '', String advertUrl = _photoUrl}) => Job(
      id: 'j1',
      title: 'Accounts Assistant',
      companyId: 'c1',
      location: 'Bo',
      employmentType: EmploymentType.fullTime,
      workMode: WorkMode.onsite,
      industry: Industry.finance,
      experienceLevel: ExperienceLevel.mid,
      salaryMin: null,
      salaryMax: null,
      postedAt: DateTime(2026, 10, 1),
      deadline: DateTime(2026, 11, 1),
      about: '',
      description: description,
      responsibilities: const [],
      requirements: const [],
      preferred: const [],
      skills: const [],
      benefits: const [],
      advertUrl: advertUrl,
    );

void main() {
  test('the advert survives JSON and older jobs have none', () {
    final j = _job();
    expect(Job.fromJson(j.toJson()).advertUrl, _photoUrl);
    expect(Job.fromJson({...j.toJson()}..remove('advert_url')).hasAdvert, isFalse);
    expect(j.withCompany(null).advertUrl, _photoUrl);
  });

  test('PDF and photo adverts are told apart by the file name', () {
    expect(_job(advertUrl: _pdfUrl).advertIsPdf, isTrue);
    expect(_job().advertIsPdf, isFalse);
    expect(Job.isPdfAdvert('Advert.PDF'), isTrue);
    expect(Job.isPdfAdvert('$_pdfUrl?download=1'), isTrue, reason: 'query strings are ignored');
  });

  test('moderators are told to read an advert-only job', () {
    expect(scamFlags(_job()), contains(startsWith('Details are only in the uploaded advert')));
    expect(scamFlags(_job(description: 'Keep the books for our Bo branch.')), isEmpty);
  });

  test('demo employers can post a job with only an advert', () async {
    final b = DemoEmployerBackend(approveOnRegister: true);
    final url = await b.uploadJobAdvert(Uint8List.fromList([37, 80, 68, 70]), 'advert.pdf');
    expect(url, startsWith('data:application/pdf;base64,'));
    final saved = await b.saveJob(_job(advertUrl: url), status: JobStatus.published);
    expect(saved.advertUrl, url);
  });
}
