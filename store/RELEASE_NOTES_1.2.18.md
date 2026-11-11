# Vocation SL 1.2.18 (build 33), 11 November 2026

## What changed
- **Invoices show legal details.** Every invoice PDF (`lib/widgets/invoice_pdf.dart`) shows VOCATION (SL) LIMITED, the Bo address, NRA TIN 1001050525 and CAC registration no. SL050224VOCAT20623 in the header and footer. Values are in `AppConfig` (`legalName`, `companyAddress`, `taxId`, `cacRegistration`).
- **Job alert emails** (`supabase/functions/job-emails`, v9) link to the App Store as well as Google Play, in the HTML and plain-text versions.

## Release
- Web: 11 Nov 2026.
- Android: release/play/vocation-sl-1.2.18.aab (user uploads).
- iOS: ios.yml build 33, submitted to App Store review.
