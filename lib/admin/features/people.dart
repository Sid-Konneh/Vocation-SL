import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../employer/widgets.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/document_viewer.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';

Future<void> _act(BuildContext context, String done, Future<void> Function() action) async {
  try {
    await action();
    if (context.mounted) showSnack(context, done);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

String _initial(String s) => s.trim().isEmpty ? '?' : s.trim()[0].toUpperCase();

// ---- Users -----------------------------------------------------------------------------

enum _UserFilter { all, seekers, employers, suspended }

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  _UserFilter _filter = _UserFilter.all;
  String _q = '';

  bool _matches(AdminUser u) => _matchesFilter(_filter, u);

  static bool _matchesFilter(_UserFilter f, AdminUser u) => switch (f) {
        _UserFilter.all => true,
        _UserFilter.seekers => u.role != 'employer',
        _UserFilter.employers => u.role == 'employer',
        _UserFilter.suspended => u.suspended,
      };

  Future<void> _do(AdminUser u, String action) async {
    final a = ref.read(adminActionsProvider);
    switch (action) {
      case 'view':
        await showDialog<void>(context: context, builder: (_) => _UserDialog(user: u));
      case 'suspend':
        final reason = await showDialog<String>(context: context, builder: (_) => _ReasonDialog(name: u.name.isEmpty ? u.email : u.name));
        if (reason == null || !mounted) return;
        await _act(context, '${u.email} suspended', () => a.run((b) => b.setUserSuspended(u.id, true, reason: reason), refresh: [adminUsersProvider]));
      case 'unsuspend':
        await _act(context, '${u.email} reinstated', () => a.run((b) => b.setUserSuspended(u.id, false), refresh: [adminUsersProvider]));
      case 'delete':
        final ok = await showDialog<bool>(context: context, builder: (_) => _TypedConfirm(email: u.email));
        if (ok != true || !mounted) return;
        await _act(context, '${u.email} deleted', () => a.run((b) => b.deleteUser(u.id), refresh: [adminUsersProvider, adminApplicationsProvider]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminUsersProvider);
    final canManage = adminCan(ref, AdminRole.admin);
    return EmployerPage(
      title: 'Users',
      subtitle: 'Every job seeker and employer account.',
      onRefresh: () async => ref.invalidate(adminUsersProvider),
      children: [
        AdminAsync<List<AdminUser>>(
          value: async,
          onRetry: () => ref.invalidate(adminUsersProvider),
          builder: (all) {
            final q = _q.trim().toLowerCase();
            final list = all.where((u) => _matches(u) && (q.isEmpty || '${u.name} ${u.email}'.toLowerCase().contains(q))).toList();
            final counts = {for (final f in _UserFilter.values) f: all.where((u) => _matchesFilter(f, u)).length};
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final f in _UserFilter.values)
                  ChoiceChip(
                    label: Text('${switch (f) { _UserFilter.all => 'All', _UserFilter.seekers => 'Job seekers', _UserFilter.employers => 'Employers', _UserFilter.suspended => 'Suspended' }} (${counts[f]})'),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                SizedBox(
                  width: 280,
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: const InputDecoration(hintText: 'Search name or email', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              TableCard(
                empty: const EmptyState(icon: Icons.people_outline_rounded, title: 'No users match', message: 'Try another filter or search.'),
                columns: const [
                  DataColumn(label: Text('User')),
                  DataColumn(label: Text('Uses app as')),
                  DataColumn(label: Text('Joined')),
                  DataColumn(label: Text('Last seen')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('')),
                ],
                rows: [
                  for (final u in list)
                    DataRow(onSelectChanged: (_) => _do(u, 'view'), cells: [
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: Row(children: [
                          UserAvatar(initials: _initial(u.name.isEmpty ? u.email : u.name), photoBase64: u.photoBase64, size: 32),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(u.name.isEmpty ? '(no name)' : u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(u.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
                            ]),
                          ),
                        ]),
                      )),
                      DataCell(Text(u.roleLabel)),
                      DataCell(Text(Fmt.dateShort(u.createdAt))),
                      DataCell(Text(u.lastSeenAt == null ? '—' : Fmt.ago(u.lastSeenAt!))),
                      DataCell(u.suspended
                          ? TagChip('Suspended', dense: true, color: AppColors.danger, background: AppColors.danger.withValues(alpha: 0.12))
                          : TagChip('Active', dense: true, color: AppColors.success, background: AppColors.success.withValues(alpha: 0.12))),
                      DataCell(PopupMenuButton<String>(
                        tooltip: 'Actions for ${u.email}',
                        onSelected: (a) => _do(u, a),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'view', child: Text('View profile')),
                          if (canManage && !u.suspended) const PopupMenuItem(value: 'suspend', child: Text('Suspend')),
                          if (canManage && u.suspended) const PopupMenuItem(value: 'unsuspend', child: Text('Reinstate')),
                          if (canManage) const PopupMenuItem(value: 'delete', child: Text('Delete account')),
                        ],
                      )),
                    ]),
                ],
              ),
            ]);
          },
        ),
      ],
    );
  }
}

/// Everything about one account: sign-in details, the full profile and
/// their applications.
class _UserDialog extends ConsumerWidget {
  const _UserDialog({required this.user});
  final AdminUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = context.palette.muted;
    final p = user.profile;
    final canSeeLogin = adminCan(ref, AdminRole.admin);
    final apps = (ref.watch(adminApplicationsProvider).value ?? const <JobApplication>[]).where((a) => a.userId == user.id).toList();

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: context.text.titleMedium),
            const SizedBox(height: 6),
            ...children,
          ]),
        );
    Widget line(String text, {String? sub}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (sub != null && sub.isNotEmpty) Text(sub, style: context.text.bodySmall?.copyWith(color: muted)),
          ]),
        );
    String when(DateTime? d) => d == null ? '—' : '${Fmt.dateTime(d)} (${Fmt.ago(d)})';
    String years(int start, int? end) => '$start – ${end ?? 'present'}';

    final login = canSeeLogin
        ? ref.watch(adminUserLoginProvider(user.id)).when(
              loading: () => const [Skeleton(child: Column(children: [ListTileSkeleton(), ListTileSkeleton()]))],
              error: (e, _) => [Text('Couldn\'t load sign-in details: $e', style: context.text.bodySmall?.copyWith(color: AppColors.danger))],
              data: (l) => l == null
                  ? [Text('No sign-in record for this account.', style: context.text.bodySmall?.copyWith(color: muted))]
                  : [
                      InfoRow(
                        icon: Icons.key_outlined,
                        label: 'Signs in with',
                        value: l.providers.isEmpty ? '—' : l.providers.map(UserLoginInfo.providerLabel).join(', '),
                      ),
                      InfoRow(
                        icon: Icons.mark_email_read_outlined,
                        label: 'Email confirmed',
                        value: l.emailConfirmedAt == null ? 'Not confirmed' : Fmt.dateTime(l.emailConfirmedAt!),
                      ),
                      InfoRow(icon: Icons.event_outlined, label: 'Account created', value: when(l.createdAt)),
                      InfoRow(icon: Icons.login_rounded, label: 'Last sign-in', value: when(l.lastSignInAt)),
                      if (l.phone.isNotEmpty) InfoRow(icon: Icons.phone_outlined, label: 'Sign-in phone', value: l.phone),
                      if (l.adminRole != null) InfoRow(icon: Icons.admin_panel_settings_outlined, label: 'Admin role', value: l.adminRole!.label),
                      for (final c in l.companies)
                        InfoRow(icon: Icons.business_outlined, label: 'Company (${c.role})', value: '${c.name} · ${c.status}'),
                      InfoRow(icon: Icons.assignment_outlined, label: 'Applications sent', value: '${l.applications}'),
                      if (l.identities.length > 1)
                        for (final i in l.identities)
                          line('Linked: ${UserLoginInfo.providerLabel(i.provider)}${i.email.isEmpty ? '' : ' · ${i.email}'}',
                              sub: 'Last used ${when(i.lastSignInAt)}'),
                      const SizedBox(height: 8),
                      Text('Recent devices', style: context.text.labelLarge),
                      if (l.sessions.isEmpty)
                        Text('No active sessions. They are signed out everywhere.', style: context.text.bodySmall?.copyWith(color: muted))
                      else
                        for (final s in l.sessions)
                          line(describeUserAgent(s.userAgent),
                              sub: [
                                'Signed in ${when(s.createdAt)}',
                                if (s.lastActiveAt != null) 'last active ${Fmt.ago(s.lastActiveAt!)}',
                                if (s.ip.isNotEmpty) 'IP ${s.ip}',
                              ].join(' · ')),
                      const SizedBox(height: 6),
                      Text('Passwords are stored encrypted and can\'t be viewed by anyone, including admins. Viewing this section is recorded in the activity log.',
                          style: context.text.bodySmall?.copyWith(color: muted)),
                    ],
            )
        : [Text('Sign-in details are visible to admins and owners.', style: context.text.bodySmall?.copyWith(color: muted))];

    return AlertDialog(
      title: Row(children: [
        UserAvatar(initials: _initial(user.name.isEmpty ? user.email : user.name), photoBase64: user.photoBase64, size: 56),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user.name.isEmpty ? user.email : user.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            Text('${user.roleLabel} · ${user.email}', style: context.text.bodySmall?.copyWith(color: muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (user.suspended)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppSpacing.radius)),
                child: Text('Suspended: ${user.suspendedReason ?? 'No reason given'}', style: context.text.bodyMedium),
              ),
            section('Account and sign-in', login),
            section('Profile', [
              if (p == null)
                Text('This profile couldn\'t be read.', style: context.text.bodySmall?.copyWith(color: muted))
              else ...[
                Text('Profile ${p.completion}% complete', style: context.text.bodySmall?.copyWith(color: muted)),
                if (p.headline.isNotEmpty) InfoRow(icon: Icons.work_outline_rounded, label: 'Headline', value: p.headline),
                if (p.location.isNotEmpty) InfoRow(icon: Icons.place_outlined, label: 'Location', value: p.location),
                if (p.phone.isNotEmpty) InfoRow(icon: Icons.phone_outlined, label: 'Phone', value: p.phone),
                if (p.linkedinUrl.isNotEmpty) InfoRow(icon: Icons.link_rounded, label: 'LinkedIn', value: p.linkedinUrl),
                if (p.portfolioUrl.isNotEmpty) InfoRow(icon: Icons.language_rounded, label: 'Portfolio', value: p.portfolioUrl),
                InfoRow(
                  icon: Icons.description_outlined,
                  label: 'CV',
                  value: p.resume == null ? 'Not uploaded' : '${p.resume!.fileName} · ${Fmt.fileSize(p.resume!.sizeBytes)} · ${Fmt.date(p.resume!.uploadedAt)}',
                ),
                if (p.about.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(p.about, style: context.text.bodyMedium)),
              ],
            ]),
            if (p != null && p.experience.isNotEmpty)
              section('Experience', [
                for (final e in p.experience)
                  line('${e.title} · ${e.company}',
                      sub: '${Fmt.date(e.start)} – ${e.end == null ? 'present' : Fmt.date(e.end!)}${e.location.isEmpty ? '' : ' · ${e.location}'}'),
              ]),
            if (p != null && p.education.isNotEmpty)
              section('Education', [
                for (final e in p.education) line('${e.degree}${e.field.isEmpty ? '' : ', ${e.field}'}', sub: '${e.school} · ${years(e.startYear, e.endYear)}'),
              ]),
            if (p != null && p.skills.isNotEmpty)
              section('Skills', [Wrap(spacing: 6, runSpacing: 6, children: [for (final s in p.skills) TagChip(s, dense: true)])]),
            if (p != null && (p.languages.isNotEmpty || p.certifications.isNotEmpty))
              section('Languages and certifications', [
                for (final l in p.languages) line(l.name, sub: l.level),
                for (final c in p.certifications) line(c.name, sub: '${c.issuer} · ${c.year}'),
              ]),
            if (p != null && !p.preferences.isEmpty)
              section('Job preferences', [
                if (p.preferences.titles.isNotEmpty) InfoRow(icon: Icons.search_rounded, label: 'Roles', value: p.preferences.titles.join(', ')),
                if (p.preferences.industries.isNotEmpty)
                  InfoRow(icon: Icons.category_outlined, label: 'Industries', value: p.preferences.industries.map((i) => i.label).join(', ')),
                if (p.preferences.locations.isNotEmpty) InfoRow(icon: Icons.place_outlined, label: 'Locations', value: p.preferences.locations.join(', ')),
                if (p.preferences.salaryExpectation != null)
                  InfoRow(icon: Icons.payments_outlined, label: 'Salary expectation', value: 'SLE ${Fmt.money(p.preferences.salaryExpectation!)} / month'),
              ]),
            section('Applications (${apps.length})', [
              if (apps.isEmpty)
                Text('No applications.', style: context.text.bodySmall?.copyWith(color: muted))
              else
                for (final a in apps.take(20))
                  line('${a.job?.title ?? 'Removed job'}${a.job == null ? '' : ' · ${a.job!.companyName}'}',
                      sub: '${a.status.label} · applied ${Fmt.date(a.submittedAt)}'),
            ]),
            section('Account ID', [SelectableText(user.id, style: context.text.bodySmall?.copyWith(color: muted))]),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.name});
  final String name;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Suspend ${widget.name}?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('They can still sign in, but can\'t apply for jobs, post jobs or register a company until reinstated.'),
          const SizedBox(height: 12),
          TextField(controller: _c, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Reason (shown to the user)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, _c.text.trim().isEmpty ? 'Breach of the terms of use' : _c.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger, minimumSize: const Size(64, 44)),
            child: const Text('Suspend'),
          ),
        ],
      );
}

class _TypedConfirm extends StatefulWidget {
  const _TypedConfirm({required this.email});
  final String email;

  @override
  State<_TypedConfirm> createState() => _TypedConfirmState();
}

class _TypedConfirmState extends State<_TypedConfirm> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Delete this account?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${widget.email} and all their data will be permanently deleted. This can\'t be undone.'),
          const SizedBox(height: 12),
          TextField(controller: _c, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Type DELETE to confirm')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: _c.text.trim().toUpperCase() == 'DELETE' ? () => Navigator.pop(context, true) : null,
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger, minimumSize: const Size(64, 44)),
            child: const Text('Delete'),
          ),
        ],
      );
}

// ---- Applications tracking ---------------------------------------------------------------

class AdminApplicationsScreen extends ConsumerStatefulWidget {
  const AdminApplicationsScreen({super.key});

  @override
  ConsumerState<AdminApplicationsScreen> createState() => _AdminApplicationsScreenState();
}

class _AdminApplicationsScreenState extends ConsumerState<AdminApplicationsScreen> {
  ApplicationStatus? _status;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminApplicationsProvider);
    return EmployerPage(
      title: 'Applications',
      subtitle: 'Every application on the platform and where it stands.',
      onRefresh: () async => ref.invalidate(adminApplicationsProvider),
      children: [
        AdminAsync<List<JobApplication>>(
          value: async,
          onRetry: () => ref.invalidate(adminApplicationsProvider),
          builder: (all) {
            final q = _q.trim().toLowerCase();
            final list = all
                .where((a) => (_status == null || a.status == _status) &&
                    (q.isEmpty || '${a.applicant.fullName} ${a.applicant.email} ${a.job?.title ?? ''} ${a.job?.companyName ?? ''}'.toLowerCase().contains(q)))
                .toList();
            final stale = all.where((a) => a.status == ApplicationStatus.applied && DateTime.now().difference(a.submittedAt).inDays >= 14).length;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StatGrid(children: [
                StatTile(label: 'Total', value: '${all.length}', icon: Icons.inbox_outlined),
                StatTile(label: 'In progress', value: '${all.where((a) => a.status.isActive).length}', icon: Icons.pending_actions_outlined),
                StatTile(label: 'Interviews', value: '${all.where((a) => a.status == ApplicationStatus.interview).length}', icon: Icons.event_outlined),
                StatTile(label: 'Hired', value: '${all.where((a) => a.status == ApplicationStatus.hired).length}', icon: Icons.handshake_outlined),
                StatTile(label: 'Unopened 14+ days', value: '$stale', detail: 'Employers not responding', icon: Icons.hourglass_bottom_rounded, attention: stale > 0),
              ]),
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<ApplicationStatus?>(
                    initialValue: _status,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Stage', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All stages')),
                      for (final s in ApplicationStatus.values) DropdownMenuItem(value: s, child: Text('${s.label} (${all.where((a) => a.status == s).length})')),
                    ],
                    onChanged: (v) => setState(() => _status = v),
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: const InputDecoration(hintText: 'Search applicant, job or company', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              TableCard(
                empty: const EmptyState(icon: Icons.assignment_outlined, title: 'No applications match', message: 'Try another stage or search.'),
                columns: const [
                  DataColumn(label: Text('Applicant')),
                  DataColumn(label: Text('Job')),
                  DataColumn(label: Text('Company')),
                  DataColumn(label: Text('Stage')),
                  DataColumn(label: Text('Applied')),
                  DataColumn(label: Text('Last update')),
                  DataColumn(label: Text('Documents')),
                ],
                rows: [
                  for (final a in list)
                    DataRow(cells: [
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a.applicant.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(a.applicant.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
                        ]),
                      )),
                      DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: Text(a.job?.title ?? '—', maxLines: 2, overflow: TextOverflow.ellipsis))),
                      DataCell(Text(a.job?.companyName ?? '—')),
                      DataCell(StatusChip(a.status, dense: true)),
                      DataCell(Text(Fmt.dateShort(a.submittedAt))),
                      DataCell(Text(Fmt.ago(a.updatedAt))),
                      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'View CV: ${a.resume.fileName}',
                          icon: const Icon(Icons.description_outlined),
                          onPressed: () => viewDocument(context,
                              title: '${a.applicant.fullName} · CV',
                              fileName: a.resume.fileName,
                              format: a.resume.format,
                              storagePath: a.resume.storagePath,
                              loadUrl: ref.read(adminBackendProvider).documentUrl),
                        ),
                        if (a.coverLetter?.kind == CoverLetterKind.uploaded)
                          IconButton(
                            tooltip: 'View cover letter',
                            icon: const Icon(Icons.mail_outline_rounded),
                            onPressed: () => viewDocument(context,
                                title: '${a.applicant.fullName} · Cover letter',
                                fileName: a.coverLetter!.fileName ?? 'Cover letter',
                                format: a.coverLetter!.format,
                                storagePath: a.coverLetter!.storagePath,
                                loadUrl: ref.read(adminBackendProvider).documentUrl),
                          )
                        else if (a.coverLetter?.kind == CoverLetterKind.written)
                          IconButton(
                            tooltip: 'Read cover letter',
                            icon: const Icon(Icons.mail_outline_rounded),
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: Text('${a.applicant.fullName} · Cover letter'),
                                content: SizedBox(width: 560, child: SingleChildScrollView(child: SelectableText(a.coverLetter!.text ?? ''))),
                                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                              ),
                            ),
                          ),
                      ])),
                    ]),
                ],
              ),
            ]);
          },
        ),
      ],
    );
  }
}

// ---- Admin team --------------------------------------------------------------------------

class AdminTeamScreen extends ConsumerWidget {
  const AdminTeamScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(String, AdminRole)>(context: context, builder: (_) => const _AddMemberDialog());
    if (result == null || !context.mounted) return;
    await _act(context, '${result.$1} added as ${result.$2.label}',
        () => ref.read(adminActionsProvider).run((b) => b.addMember(result.$1, result.$2), refresh: [adminTeamProvider]));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminTeamProvider);
    final isOwner = adminCan(ref, AdminRole.owner);
    return EmployerPage(
      title: 'Admin team',
      subtitle: 'Who can use the admin dashboard, and what they can do.',
      onRefresh: () async => ref.invalidate(adminTeamProvider),
      actions: [
        if (isOwner)
          FilledButton.icon(
            onPressed: () => _add(context, ref),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add admin'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          ),
      ],
      children: [
        if (!isOwner)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('Only owners can add, change or remove admins.', style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
          ),
        AdminAsync<List<AdminMember>>(
          value: async,
          onRetry: () => ref.invalidate(adminTeamProvider),
          builder: (team) => TableCard(
            columns: const [
              DataColumn(label: Text('Admin')),
              DataColumn(label: Text('Role')),
              DataColumn(label: Text('Can')),
              DataColumn(label: Text('Added')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final m in team)
                DataRow(cells: [
                  DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.name.isEmpty ? m.email : m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (m.name.isNotEmpty) Text(m.email, style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
                  ])),
                  DataCell(isOwner
                      ? DropdownButtonHideUnderline(
                          child: DropdownButton<AdminRole>(
                            value: m.role,
                            items: [for (final r in AdminRole.values.reversed) DropdownMenuItem(value: r, child: Text(r.label))],
                            onChanged: (r) {
                              if (r == null || r == m.role) return;
                              _act(context, '${m.email} is now ${r.label}',
                                  () => ref.read(adminActionsProvider).run((b) => b.setMemberRole(m.userId, r), refresh: [adminTeamProvider, adminRoleProvider]));
                            },
                          ),
                        )
                      : Text(m.role.label)),
                  DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 260), child: Text(m.role.description, maxLines: 2, overflow: TextOverflow.ellipsis))),
                  DataCell(Text(Fmt.dateShort(m.createdAt))),
                  DataCell(isOwner
                      ? IconButton(
                          tooltip: 'Remove ${m.email}',
                          icon: const Icon(Icons.person_remove_outlined),
                          onPressed: () async {
                            if (!await confirmDialog(context, title: 'Remove ${m.email}?', message: 'They will lose access to the admin dashboard.', confirmLabel: 'Remove', destructive: true)) return;
                            if (!context.mounted) return;
                            await _act(context, '${m.email} removed',
                                () => ref.read(adminActionsProvider).run((b) => b.removeMember(m.userId), refresh: [adminTeamProvider, adminRoleProvider]));
                          },
                        )
                      : const SizedBox()),
                ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog();

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _email = TextEditingController();
  AdminRole _role = AdminRole.moderator;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add an admin'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('They must already have a Vocation SL account.'),
          const SizedBox(height: 12),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Their email')),
          const SizedBox(height: 12),
          RadioGroup<AdminRole>(
            groupValue: _role,
            onChanged: (r) => setState(() => _role = r ?? _role),
            child: Column(children: [
              for (final r in AdminRole.values.reversed)
                RadioListTile<AdminRole>(contentPadding: EdgeInsets.zero, value: r, title: Text(r.label), subtitle: Text(r.description)),
            ]),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (_email.text.trim().contains('@')) Navigator.pop(context, (_email.text.trim(), _role));
            },
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            child: const Text('Add'),
          ),
        ],
      );
}
