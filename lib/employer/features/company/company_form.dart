import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/models.dart';
import '../../../widgets/company_logo.dart';

const _sizes = ['1–10 employees', '11–50 employees', '51–200 employees', '201–500 employees', '501–1,000 employees', '1,000+ employees'];
const _brandColors = [0xFF1F6FEB, 0xFF0E7C66, 0xFF3F7A1F, 0xFF7A4CC2, 0xFFD1435B, 0xFFE8702A, 0xFF2D3A8C, 0xFF8A5A2B, 0xFF16808F, 0xFF14171A];

/// Edits every employer-writable company field. Call [CompanyFormState.build]
/// via a GlobalKey to validate and read the result.
class CompanyForm extends StatefulWidget {
  const CompanyForm({super.key, this.initial});
  final Company? initial;

  @override
  State<CompanyForm> createState() => CompanyFormState();
}

class CompanyFormState extends State<CompanyForm> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _about = TextEditingController(text: widget.initial?.about);
  late final _website = TextEditingController(text: widget.initial?.website);
  late final _email = TextEditingController(text: widget.initial?.email);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _address = TextEditingController(text: widget.initial?.address);
  late final _founded = TextEditingController(text: (widget.initial?.founded ?? 0) > 0 ? '${widget.initial!.founded}' : '');
  late Industry _industry = widget.initial?.industry ?? Industry.technology;
  late String _location = sierraLeoneLocations.contains(widget.initial?.location) ? widget.initial!.location : 'Freetown';
  late String _size = _sizes.contains(widget.initial?.size) ? widget.initial!.size : _sizes[1];
  late int _color = widget.initial?.brandColor ?? _brandColors.first;

  @override
  void dispose() {
    for (final c in [_name, _about, _website, _email, _phone, _address, _founded]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Validates and returns the edited company, or null if invalid.
  Company? result() {
    if (!(_key.currentState?.validate() ?? false)) return null;
    final base = widget.initial ??
        const Company(id: '', name: '', industry: Industry.technology, location: '', about: '', size: '', founded: 0, website: '', brandColor: 0);
    return base.copyWith(
      name: _name.text.trim(),
      industry: _industry,
      location: _location,
      about: _about.text.trim(),
      size: _size,
      founded: int.tryParse(_founded.text.trim()) ?? 0,
      website: _website.text.trim(),
      brandColor: _color,
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      address: _address.text.trim(),
    );
  }

  String? _required(String? v, String what) => (v ?? '').trim().isEmpty ? 'Enter $what' : null;

  @override
  Widget build(BuildContext context) {
    final preview = Company(
      id: 'preview',
      name: _name.text.isEmpty ? 'Your company' : _name.text,
      industry: _industry,
      location: _location,
      about: '',
      size: _size,
      founded: 0,
      website: '',
      brandColor: _color,
    );
    Widget gap() => const SizedBox(height: 14);
    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 12),
          child: Text(t, style: context.text.titleMedium),
        );

    return Form(
      key: _key,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CompanyLogo(company: preview, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in _brandColors)
                Semantics(
                  button: true,
                  selected: c == _color,
                  label: 'Logo colour',
                  child: InkWell(
                    onTap: () => setState(() => _color = c),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: c == _color ? context.colors.onSurface : Colors.transparent, width: 3),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
        heading('Company details'),
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Company name *'),
          onChanged: (_) => setState(() {}),
          validator: (v) => _required(v, 'your company name'),
        ),
        gap(),
        DropdownButtonFormField<Industry>(
          initialValue: _industry,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Industry *'),
          items: [for (final i in Industry.values) DropdownMenuItem(value: i, child: Text(i.label))],
          onChanged: (v) => setState(() => _industry = v ?? _industry),
        ),
        gap(),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _location,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Head office *'),
              items: [for (final l in sierraLeoneLocations) DropdownMenuItem(value: l, child: Text(l))],
              onChanged: (v) => setState(() => _location = v ?? _location),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _size,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Company size'),
              items: [for (final s in _sizes) DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _size = v ?? _size),
            ),
          ),
        ]),
        gap(),
        TextFormField(
          controller: _about,
          minLines: 4,
          maxLines: 8,
          maxLength: 1200,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'About the company *', alignLabelWithHint: true, hintText: 'What you do, where you work, and what it\'s like to work with you.'),
          validator: (v) => (v ?? '').trim().length < 40 ? 'Write at least 40 characters so candidates know who you are' : null,
        ),
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _website,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Website'),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: TextFormField(
              controller: _founded,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Founded'),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                final y = int.tryParse(t);
                return y == null || y < 1800 || y > DateTime.now().year ? 'Enter a year' : null;
              },
            ),
          ),
        ]),
        heading('Contact details'),
        Text('Used by our team when reviewing your account. Not shown to candidates.',
            style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
        gap(),
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Contact email *'),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone *', hintText: '+232 …'),
              validator: (v) => (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 8 ? 'Enter a phone number' : null,
            ),
          ),
        ]),
        gap(),
        TextFormField(
          controller: _address,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Business address *'),
          validator: (v) => _required(v, 'your business address'),
        ),
      ]),
    );
  }
}
