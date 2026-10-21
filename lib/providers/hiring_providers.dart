import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend/hiring_backend.dart';
import '../models/models.dart';
import 'session_providers.dart';

/// Overridden in main.dart with the Supabase version when live.
final hiringBackendProvider = Provider<HiringBackend>((ref) => DemoHiringBackend());

/// The latest interview times offered on an application.
final interviewProposalProvider = FutureProvider.autoDispose.family<InterviewProposal?, String>((ref, applicationId) {
  ref.watch(sessionProvider);
  return ref.watch(hiringBackendProvider).latestProposal(applicationId);
});

/// How quickly a company usually replies to applicants.
final replySpeedProvider = FutureProvider.autoDispose.family<ReplySpeed, String>((ref, companyId) {
  ref.watch(sessionProvider);
  return ref.watch(hiringBackendProvider).replySpeed(companyId);
});

/// Whether the signed-in job seeker lets employers find them.
final discoverableProvider = FutureProvider.autoDispose<bool>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(hiringBackendProvider).myDiscoverable();
});

final jobReportProvider = FutureProvider.autoDispose.family<JobReport, String>((ref, jobId) {
  ref.watch(sessionProvider);
  return ref.watch(hiringBackendProvider).jobReport(jobId);
});

final myTicketsProvider = FutureProvider.autoDispose<List<SupportTicket>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(hiringBackendProvider).myTickets();
});

final allTicketsProvider = FutureProvider.autoDispose<List<SupportTicket>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(hiringBackendProvider).allTickets();
});

final supportThreadProvider = FutureProvider.autoDispose.family<List<SupportMessage>, String>((ref, ticketId) {
  ref.watch(sessionProvider);
  return ref.watch(hiringBackendProvider).supportThread(ticketId);
});

final weeklyDigestProvider = FutureProvider.autoDispose<WeeklyDigest>((ref) => ref.watch(hiringBackendProvider).weeklyDigest());
