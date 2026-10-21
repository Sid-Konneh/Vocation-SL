import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';

/// Remembers where a job seeker opened each job (home, search, an alert...)
/// so the application can tell the employer where applicants come from.
/// Kept in memory only: it's a hint for reports, not personal data.
class JobSource {
  static final _seen = <String, ApplicationSource>{};

  static void note(String jobId, ApplicationSource source) => _seen[jobId] = source;

  static void noteFromNotification(String jobId, NotificationType type) {
    if (type == NotificationType.invite) {
      note(jobId, ApplicationSource.invite);
    } else if (type == NotificationType.savedSearch || type == NotificationType.newMatch) {
      note(jobId, ApplicationSource.alert);
    }
  }

  /// Called by the job page: a job page that is the first page on screen
  /// came from a shared link or the website.
  static void noteOpened(String jobId, {required bool firstPage}) {
    if (firstPage) {
      _seen[jobId] = ApplicationSource.link;
    } else {
      _seen.putIfAbsent(jobId, () => ApplicationSource.app);
    }
  }

  /// Where [jobId] was opened from.
  static ApplicationSource of(String jobId) => _seen[jobId] ?? ApplicationSource.app;

  /// The source implied by the page the user is on.
  static ApplicationSource fromPath(String path) {
    if (path.startsWith('/jobs')) return ApplicationSource.home;
    if (path.startsWith('/search')) return ApplicationSource.search;
    if (path.startsWith('/saved')) return ApplicationSource.saved;
    if (path.startsWith('/company/')) return ApplicationSource.company;
    return ApplicationSource.app;
  }
}

/// Opens a job's page, noting where it was opened from.
void openJob(BuildContext context, String jobId, {ApplicationSource? source}) {
  ApplicationSource from;
  try {
    from = source ?? JobSource.fromPath(GoRouterState.of(context).uri.path);
  } catch (_) {
    from = source ?? ApplicationSource.app;
  }
  JobSource.note(jobId, from);
  context.push('/job/$jobId');
}
