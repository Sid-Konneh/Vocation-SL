import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/common.dart';
import '../../widgets.dart';

/// Vocation SL's company information, how to pay invoices, and the company's
/// registration documents (NRA, CAC and the bank's confirmation letter).
class HowToPayScreen extends StatelessWidget {
  const HowToPayScreen({super.key});

  @override
  Widget build(BuildContext context) => EmployerPage(
        title: 'Company info & how to pay',
        subtitle: 'How to pay Vocation SL invoices, and our company details and registration documents.',
        children: const [
          HowToPayCard(),
          SizedBox(height: 16),
          _CompanyInfoCard(),
          SizedBox(height: 16),
          _DocumentsCard(),
        ],
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.children});
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: context.colors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.copy = false});
  final String label;
  final String value;
  final bool copy;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(width: 140, child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.palette.muted))),
          Expanded(child: SelectableText(value, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
          if (copy)
            IconButton(
              tooltip: 'Copy $label',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value.replaceAll(' ', '')));
                if (context.mounted) showSnack(context, '$label copied');
              },
            ),
        ]),
      );
}

/// Bank and Orange Money details. Also shown on the Invoices screen.
class HowToPayCard extends StatelessWidget {
  const HowToPayCard({super.key});

  @override
  Widget build(BuildContext context) => _Section(
        icon: Icons.payments_outlined,
        title: 'How to pay',
        children: [
          Text('Bank transfer (preferred)', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const _Line('Bank', AppConfig.payBankName),
          const _Line('Account name', AppConfig.payBankAccountName, copy: true),
          const _Line('Account number', AppConfig.payBankAccountNumber, copy: true),
          const _Line('BBAN', AppConfig.payBankBban, copy: true),
          const _Line('SWIFT', AppConfig.payBankSwift, copy: true),
          const SizedBox(height: 12),
          Text('Orange Money', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const _Line('Number', AppConfig.payOrangeMoney, copy: true),
          const SizedBox(height: 12),
          Text(
            'Quote your invoice number (for example VSL-2027-00001) as the reference when you pay. '
            'Questions: ${AppConfig.supportEmail}.',
            style: context.text.bodySmall?.copyWith(color: context.palette.muted),
          ),
        ],
      );
}

class _CompanyInfoCard extends StatelessWidget {
  const _CompanyInfoCard();

  @override
  Widget build(BuildContext context) => const _Section(
        icon: Icons.business_outlined,
        title: 'Vocation SL company information',
        children: [
          _Line('Company name', AppConfig.legalName),
          _Line('Address', AppConfig.companyAddress),
          _Line('Email', AppConfig.supportEmail),
          _Line('NRA TIN', AppConfig.taxId, copy: true),
          _Line('GST', 'Registered with the NRA'),
          _Line('CAC number', AppConfig.cacRegistration, copy: true),
          _Line('Incorporated', '5 February 2024 (Corporate Affairs Commission)'),
        ],
      );
}

class _Doc {
  const _Doc(this.title, this.file, this.icon);
  final String title;
  final String file;
  final IconData icon;
}

const _docs = [
  _Doc('NRA Certificate of Registration (TIN)', 'nra-tin-certificate.jpg', Icons.verified_outlined),
  _Doc('CAC Certificate of Registration', 'cac-certificate-of-registration.jpg', Icons.workspace_premium_outlined),
  _Doc('CAC Certificate of Incorporation', 'cac-certificate-of-incorporation.jpg', Icons.workspace_premium_outlined),
  _Doc('Ecobank confirmation of bank details', 'ecobank-bank-details-letter.pdf', Icons.account_balance_outlined),
];

class _DocumentsCard extends StatelessWidget {
  const _DocumentsCard();

  Future<void> _open(BuildContext context, _Doc d) async {
    try {
      // Private bucket: any signed-in user can read; links last 10 minutes.
      final url = await Supabase.instance.client.storage.from('company-documents').createSignedUrl(d.file, 600);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) showSnack(context, 'Could not open the document. Check your connection and try again.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => _Section(
        icon: Icons.folder_open_outlined,
        title: 'Registration documents',
        children: [
          for (final d in _docs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(d.icon, color: context.colors.primary),
              title: Text(d.title),
              trailing: const Icon(Icons.open_in_new_rounded, size: 20),
              onTap: AppConfig.useSupabase ? () => _open(context, d) : null,
            ),
        ],
      );
}
