import 'package:intl/intl.dart';

import '../../models/models.dart';

final _num = NumberFormat.decimalPattern('en');
final _date = DateFormat('d MMM yyyy');
final _dateShort = DateFormat('d MMM');
final _dateTime = DateFormat('EEE d MMM, h:mm a');

class Fmt {
  static String money(int v) => _num.format(v);

  static String salary(Job j, {bool short = false}) {
    final min = j.salaryMin, max = j.salaryMax;
    if (min == null && max == null) return 'Salary not disclosed';
    String k(int v) => short && v >= 1000 ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k' : _num.format(v);
    final range = (min != null && max != null && min != max) ? '${k(min)}–${k(max)}' : k((max ?? min)!);
    final period = j.salaryPeriod == 'month' ? (short ? '/mo' : ' / month') : ' / ${j.salaryPeriod}';
    return '${j.currency} $range$period';
  }

  static String date(DateTime d) => _date.format(d);
  static String dateShort(DateTime d) => _dateShort.format(d);
  static String dateTime(DateTime d) => _dateTime.format(d);

  static String ago(DateTime d, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(d);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return _date.format(d);
  }

  static String posted(DateTime d) {
    final s = ago(d);
    return s == 'Just now' || s == 'Yesterday' ? s : 'Posted ${s.replaceAll(' ago', '')} ago';
  }

  static String deadline(DateTime d) {
    final now = DateTime.now();
    if (d.isBefore(now)) return 'Closed';
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days == 0) return 'Closes today';
    if (days == 1) return 'Closes tomorrow';
    if (days <= 7) return 'Closes in $days days';
    return 'Closes ${_dateShort.format(d)}';
  }

  static bool deadlineSoon(DateTime d) {
    final diff = d.difference(DateTime.now());
    return !diff.isNegative && diff.inDays < 4;
  }

  static String fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String monthYear(DateTime d) => DateFormat('MMM yyyy').format(d);

  static String countdown(DateTime d) {
    final diff = d.difference(DateTime.now());
    if (diff.isNegative) return 'Passed';
    if (diff.inDays >= 1) return 'in ${diff.inDays} day${diff.inDays == 1 ? '' : 's'}';
    if (diff.inHours >= 1) return 'in ${diff.inHours} hour${diff.inHours == 1 ? '' : 's'}';
    return 'in ${diff.inMinutes} min';
  }
}
