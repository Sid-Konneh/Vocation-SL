import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../employer/widgets.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
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

// ---- Content: announcements + pages -------------------------------------------------------

class AdminContentScreen extends ConsumerWidget {
  const AdminContentScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [Announcement? a]) async {
    final result = await showDialog<Announcement>(context: context, builder: (_) => _AnnouncementDialog(initial: a));
    if (result == null || !context.mounted) return;
    await _act(context, a == null ? 'Announcement published' : 'Announcement updated',
        () => ref.read(adminActionsProvider).run((b) => b.saveAnnouncement(result), refresh: [adminAnnouncementsProvider, announcementsProvider]));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ann = ref.watch(adminAnnouncementsProvider);
    final pages = ref.watch(adminPagesProvider);
    final canEdit = adminCan(ref, AdminRole.admin);
    final now = DateTime.now();
    return EmployerPage(
      title: 'Content',
      subtitle: 'Announcements shown in the app, and the help and policy pages.',
      onRefresh: () async {
        ref.invalidate(adminAnnouncementsProvider);
        ref.invalidate(adminPagesProvider);
      },
      actions: [
        if (canEdit)
          FilledButton.icon(
            onPressed: () => _edit(context, ref),
            icon: const Icon(Icons.campaign_outlined),
            label: const Text('New announcement'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          ),
      ],
      children: [
        SectionCard(
          title: 'Announcements',
          child: AdminAsync<List<Announcement>>(
            value: ann,
            onRetry: () => ref.invalidate(adminAnnouncementsProvider),
            builder: (list) => list.isEmpty
                ? Text('No announcements. Use them for news, outages or tips; they appear at the top of the home screen.', style: context.text.bodyMedium)
                : Column(children: [
                    for (final a in list)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          switch (a.level) { AnnouncementLevel.warning => Icons.warning_amber_rounded, AnnouncementLevel.success => Icons.celebration_outlined, _ => Icons.info_outline_rounded },
                          color: a.isLiveAt(now) ? context.colors.primary : context.palette.muted,
                        ),
                        title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${a.audience.label} · ${a.isLiveAt(now) ? 'Showing now' : (a.active ? 'Scheduled or ended' : 'Hidden')}'
                          '${a.endsAt != null ? ' · until ${Fmt.date(a.endsAt!)}' : ''}',
                        ),
                        trailing: canEdit
                            ? Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(context, ref, a)),
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  onPressed: () async {
                                    if (!await confirmDialog(context, title: 'Delete announcement?', message: '"${a.title}" will be removed.', confirmLabel: 'Delete', destructive: true)) return;
                                    if (!context.mounted) return;
                                    await _act(context, 'Announcement deleted',
                                        () => ref.read(adminActionsProvider).run((b) => b.deleteAnnouncement(a.id), refresh: [adminAnnouncementsProvider, announcementsProvider]));
                                  },
                                ),
                              ])
                            : null,
                      ),
                  ]),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Pages',
          child: AdminAsync<List<SitePage>>(
            value: pages,
            onRetry: () => ref.invalidate(adminPagesProvider),
            builder: (list) => Column(children: [
              for (final p in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.article_outlined),
                  title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(p.body.trim().isEmpty
                      ? 'Not written yet. Users see "This page hasn\'t been published yet."'
                      : 'Updated ${p.updatedAt == null ? '' : Fmt.ago(p.updatedAt!)} · ${p.body.length} characters'),
                  trailing: canEdit ? const Icon(Icons.edit_outlined) : null,
                  onTap: canEdit
                      ? () async {
                          final body = await showDialog<(String, String)>(context: context, builder: (_) => _PageDialog(page: p));
                          if (body == null || !context.mounted) return;
                          await _act(context, '${body.$1} saved',
                              () => ref.read(adminActionsProvider).run((b) => b.savePage(p.slug, body.$1, body.$2), refresh: [adminPagesProvider, sitePageProvider(p.slug)]));
                        }
                      : null,
                ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text('Terms and privacy text should be reviewed by someone qualified in Sierra Leonean law before publishing.',
            style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
      ],
    );
  }
}

class _AnnouncementDialog extends StatefulWidget {
  const _AnnouncementDialog({this.initial});
  final Announcement? initial;

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _body = TextEditingController(text: widget.initial?.body);
  late AnnouncementAudience _audience = widget.initial?.audience ?? AnnouncementAudience.all;
  late AnnouncementLevel _level = widget.initial?.level ?? AnnouncementLevel.info;
  late bool _active = widget.initial?.active ?? true;
  late DateTime? _ends = widget.initial?.endsAt;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.initial == null ? 'New announcement' : 'Edit announcement'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: _title, maxLength: 80, decoration: const InputDecoration(labelText: 'Title')),
              TextField(controller: _body, minLines: 2, maxLines: 5, maxLength: 300, decoration: const InputDecoration(labelText: 'Message')),
              DropdownButtonFormField<AnnouncementAudience>(
                initialValue: _audience,
                decoration: const InputDecoration(labelText: 'Show to'),
                items: [for (final a in AnnouncementAudience.values) DropdownMenuItem(value: a, child: Text(a.label))],
                onChanged: (v) => setState(() => _audience = v ?? _audience),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AnnouncementLevel>(
                initialValue: _level,
                decoration: const InputDecoration(labelText: 'Style'),
                items: [for (final l in AnnouncementLevel.values) DropdownMenuItem(value: l, child: Text(l.label))],
                onChanged: (v) => setState(() => _level = v ?? _level),
              ),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show now'), value: _active, onChanged: (v) => setState(() => _active = v)),
              Row(children: [
                Expanded(child: Text(_ends == null ? 'No end date' : 'Ends ${Fmt.date(_ends!)}')),
                TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: _ends ?? DateTime.now().add(const Duration(days: 7)));
                    if (d != null) setState(() => _ends = DateTime(d.year, d.month, d.day, 23, 59));
                  },
                  child: const Text('Set end date'),
                ),
                if (_ends != null) TextButton(onPressed: () => setState(() => _ends = null), child: const Text('Clear')),
              ]),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (_title.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                Announcement(
                  id: widget.initial?.id ?? '',
                  title: _title.text.trim(),
                  body: _body.text.trim(),
                  audience: _audience,
                  level: _level,
                  active: _active,
                  startsAt: widget.initial?.startsAt,
                  endsAt: _ends,
                ),
              );
            },
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            child: const Text('Save'),
          ),
        ],
      );
}

class _PageDialog extends StatefulWidget {
  const _PageDialog({required this.page});
  final SitePage page;

  @override
  State<_PageDialog> createState() => _PageDialogState();
}

class _PageDialogState extends State<_PageDialog> {
  late final _title = TextEditingController(text: widget.page.title);
  late final _body = TextEditingController(text: widget.page.body);

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Edit ${widget.page.title}'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'Page title')),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                minLines: 12,
                maxLines: 24,
                decoration: const InputDecoration(
                  labelText: 'Page text',
                  alignLabelWithHint: true,
                  helperText: 'Plain text. Leave a blank line between paragraphs. Lines starting with "# " become headings.',
                ),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (_title.text.trim().isEmpty ? widget.page.title : _title.text.trim(), _body.text)),
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            child: const Text('Publish'),
          ),
        ],
      );
}

// ---- Platform settings -------------------------------------------------------------------

class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  PlatformSettings? _draft;
  final _message = TextEditingController();
  final _email = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final d = _draft!.copyWith(maintenanceMessage: _message.text.trim(), supportEmail: _email.text.trim());
    if (!d.supportEmail.contains('@')) {
      showSnack(context, 'Enter a valid support email.', error: true);
      return;
    }
    setState(() => _saving = true);
    await _act(context, 'Platform settings saved',
        () => ref.read(adminActionsProvider).run((b) => b.saveSettings(d), refresh: [adminSettingsProvider, platformSettingsProvider]));
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminSettingsProvider);
    final canEdit = adminCan(ref, AdminRole.admin);
    return EmployerPage(
      title: 'Platform settings',
      subtitle: 'Rules and switches that apply to everyone.',
      actions: [
        if (canEdit && _draft != null)
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save settings'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          ),
      ],
      children: [
        AdminAsync<PlatformSettings>(
          value: async,
          onRetry: () => ref.invalidate(adminSettingsProvider),
          builder: (s) {
            if (_draft == null) {
              _draft = s;
              _message.text = s.maintenanceMessage;
              _email.text = s.supportEmail;
            }
            final d = _draft!;
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(children: [
                SectionCard(
                  title: 'Employers',
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Approve new companies before their jobs go live'),
                    subtitle: const Text('Recommended. When off, new companies are approved automatically and their jobs publish immediately.'),
                    value: d.requireCompanyApproval,
                    onChanged: canEdit ? (v) => setState(() => _draft = d.copyWith(requireCompanyApproval: v)) : null,
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Maintenance mode',
                  child: Column(children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show a maintenance notice to everyone'),
                      subtitle: const Text('The app keeps working; users see your message at the top of the screen.'),
                      value: d.maintenanceEnabled,
                      onChanged: canEdit ? (v) => setState(() => _draft = d.copyWith(maintenanceEnabled: v)) : null,
                    ),
                    TextField(
                      controller: _message,
                      enabled: canEdit,
                      maxLength: 200,
                      decoration: const InputDecoration(labelText: 'Message', hintText: 'e.g. Some features may be slow on Saturday from 10:00 to 12:00.'),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Support',
                  child: TextField(
                    controller: _email,
                    enabled: canEdit,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Support email', helperText: 'Shown in suspension notices and the help page.'),
                  ),
                ),
                if (!canEdit)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('Only Admins and Owners can change settings.', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
                  ),
              ]),
            );
          },
        ),
      ],
    );
  }
}

// ---- Activity log ------------------------------------------------------------------------

class AdminActivityScreen extends ConsumerStatefulWidget {
  const AdminActivityScreen({super.key});

  @override
  ConsumerState<AdminActivityScreen> createState() => _AdminActivityScreenState();
}

class _AdminActivityScreenState extends ConsumerState<AdminActivityScreen> {
  String? _type;
  String _q = '';

  static const _types = {
    'companies': 'Companies',
    'jobs': 'Jobs',
    'profiles': 'Users',
    'users': 'Deleted users',
    'reports': 'Reports',
    'announcements': 'Announcements',
    'site_pages': 'Pages',
    'platform_settings': 'Settings',
    'admins': 'Admin team',
  };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminActivityProvider);
    return EmployerPage(
      title: 'Activity log',
      subtitle: 'Every change made by an admin, newest first.',
      onRefresh: () async => ref.invalidate(adminActivityProvider),
      children: [
        AdminAsync<List<AuditEntry>>(
          value: async,
          onRetry: () => ref.invalidate(adminActivityProvider),
          builder: (all) {
            final q = _q.trim().toLowerCase();
            final list = all
                .where((e) => (_type == null || e.targetType == _type) && (q.isEmpty || '${e.summary} ${e.actorEmail}'.toLowerCase().contains(q)))
                .toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Area', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Everything')),
                      for (final e in _types.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() => _type = v),
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: const InputDecoration(hintText: 'Search changes or admin email', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              TableCard(
                empty: const EmptyState(icon: Icons.history_rounded, title: 'No activity yet', message: 'Admin changes are recorded here automatically.'),
                columns: const [
                  DataColumn(label: Text('When')),
                  DataColumn(label: Text('Admin')),
                  DataColumn(label: Text('Area')),
                  DataColumn(label: Text('Change')),
                ],
                rows: [
                  for (final e in list)
                    DataRow(cells: [
                      DataCell(Tooltip(message: Fmt.dateTime(e.createdAt), child: Text(Fmt.ago(e.createdAt)))),
                      DataCell(Text(e.actorEmail.isEmpty ? 'System' : e.actorEmail)),
                      DataCell(TagChip(_types[e.targetType] ?? e.targetType, dense: true)),
                      DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: Text(e.summary, maxLines: 2, overflow: TextOverflow.ellipsis))),
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
