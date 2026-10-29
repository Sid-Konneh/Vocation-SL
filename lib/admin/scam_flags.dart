import '../models/models.dart';

/// Warning signs in a job post that moderators should check before approving.
/// These are hints, not proof: a flagged job may be genuine.
List<String> scamFlags(Job j) {
  final text = [
    j.title,
    j.about,
    j.description,
    ...j.requirements,
    ...j.responsibilities,
    ...j.benefits,
    j.documentsNote,
  ].join(' \n ').toLowerCase();
  final flags = <String>[];

  bool has(String pattern) => RegExp(pattern, caseSensitive: false).hasMatch(text);

  if (has(r'\b(registration|application|processing|training|medical|uniform|interview|form)\s+(fee|fees|charge|charges)\b') ||
      has(r'\b(pay|paying|payment|deposit|send)\b[^.\n]{0,40}\b(fee|fees|money|le\b|sle\b|leones|mobile money|orange money|africell money)\b') ||
      has(r'\bfee(s)? (is|are|of)\b')) {
    flags.add('Mentions fees or payment from candidates');
  }
  if (has(r'wa\.me/|chat\.whatsapp|whatsapp (only|me)|contact (us )?on whatsapp')) {
    flags.add('Asks candidates to apply or pay by WhatsApp');
  }
  if (has(r'\b(bank details|bvn|pin code|mobile money pin|account number)\b')) {
    flags.add('Asks for bank or Mobile Money details');
  }
  if (has(r'\b(urgent(ly)?|immediate(ly)?)\b') && has(r'\b(no experience|no qualification|anyone can apply)\b')) {
    flags.add('Urgent hiring with no experience needed');
  }
  final link = j.applyUrl.toLowerCase();
  if (link.isNotEmpty) {
    if (RegExp(r'(bit\.ly|tinyurl|t\.co/|goo\.gl|is\.gd|cutt\.ly|shorturl|rb\.gy)').hasMatch(link)) {
      flags.add('Application link is a shortened link');
    } else if (RegExp(r'(wa\.me|whatsapp|forms\.gle|docs\.google\.com/forms)').hasMatch(link)) {
      flags.add('Application link is a WhatsApp chat or a free form; check who runs it');
    }
    if (link.startsWith('http://')) flags.add('Application link is not secure (http)');
  }
  if (j.hasAdvert && j.description.trim().isEmpty) {
    flags.add('Details are only in the uploaded advert, so the checks above can\'t read it; read the advert');
  }
  if ((j.salaryMax ?? 0) > 150000 && j.experienceLevel == ExperienceLevel.entry) {
    flags.add('Very high salary for an entry-level job');
  }
  return flags;
}
