import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/data/backend/message_backend.dart';
import 'package:vocation_sl/models/models.dart';

void main() {
  test('all 16 districts are offered, and existing town names still match', () {
    final districts = [for (final d in sierraLeoneDistricts.values) ...d];
    expect(districts.length, 16);
    expect(districts.toSet().length, 16);
    for (final d in districts) {
      expect(sierraLeoneLocations, contains(d));
    }
    for (final town in ['Freetown', 'Bo', 'Kenema', 'Makeni', 'Port Loko', 'Koidu', 'Lunsar', 'Waterloo']) {
      expect(sierraLeoneLocations, contains(town), reason: 'used by existing jobs and profiles');
    }
    expect(sierraLeoneLocations.first, 'Freetown');
    expect(sierraLeoneLocations.toSet().length, sierraLeoneLocations.length, reason: 'no duplicates');
  });

  test('employer and candidate share one thread', () async {
    final b = DemoMessageBackend();
    await b.send('app-1', 'Can you come in on Monday?', asEmployer: true);
    await b.send('app-1', 'Yes, Monday works for me.', asEmployer: false);
    await b.send('app-2', 'Other application', asEmployer: true);
    final t = await b.thread('app-1');
    expect(t.map((m) => m.fromEmployer), [true, false]);
    expect(t.last.body, 'Yes, Monday works for me.');
    expect(() => b.send('app-1', '   ', asEmployer: false), throwsA(isA<Exception>()));
  });

  test('message rows parse the sender from the database role', () {
    final m = AppMessage.fromJson({
      'id': 'x',
      'application_id': 'app-1',
      'sender_role': 'candidate',
      'body': 'Thank you',
      'created_at': '2026-10-07T09:00:00Z',
    });
    expect(m.fromEmployer, isFalse);
    expect(m.readAt, isNull);
    expect(m.hasAttachment, isFalse);
  });

  test('a PDF can be sent with or without text', () async {
    final b = DemoMessageBackend();
    final pdf = await b.uploadAttachment('Offer letter.pdf', Uint8List.fromList([1, 2, 3]));
    await b.send('app-1', '', asEmployer: true, attachment: pdf);
    await b.send('app-1', 'Please sign and send it back.', asEmployer: true, attachment: pdf);
    final t = await b.thread('app-1');
    expect(t.every((m) => m.hasAttachment && m.attachmentName == 'Offer letter.pdf'), isTrue);
    expect(t.first.body, 'Sent a document: Offer letter.pdf');
    expect(t.last.body, 'Please sign and send it back.');

    final row = AppMessage.fromJson({
      'id': 'y',
      'application_id': 'app-1',
      'sender_role': 'employer',
      'body': 'Your offer',
      'created_at': '2026-10-20T09:00:00Z',
      'attachment_path': 'uid/messages/1-Offer-letter.pdf',
      'attachment_name': 'Offer letter.pdf',
    });
    expect(row.hasAttachment, isTrue);
    expect(row.attachmentPath, 'uid/messages/1-Offer-letter.pdf');
  });

  test('attachment file names are made safe for storage', () {
    expect(safePdfName('Offer letter (final).PDF'), 'Offer-letter-final.pdf');
    expect(safePdfName('../../x.pdf'), 'x.pdf');
    expect(safePdfName('???'), 'document.pdf');
  });

  test('job review statuses round-trip through the database names', () {
    for (final s in [JobStatus.declined, JobStatus.rejected]) {
      final j = Job.fromJson({
        'id': 'j',
        'title': 'T',
        'company_id': 'c',
        'posted_at': '2026-10-01T00:00:00Z',
        'deadline': '2026-11-01T00:00:00Z',
        'status': s.name,
        'review_note': 'Add the salary range',
      });
      expect(j.status, s);
      expect(j.reviewNote, 'Add the salary range');
      expect(j.toJson()['status'], s.name);
    }
  });
}
