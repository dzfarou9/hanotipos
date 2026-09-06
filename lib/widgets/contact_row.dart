// lib/widgets/contact_row.dart

import 'package:flutter/material.dart';
import '../helpers/contact_actions.dart';

/// صف قابل للنقر يعرض قناة تواصل (بريد/واتساب/موقع) ويفتحها عند الضغط.
class ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  const ContactRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: () => onTap(),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: accentColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                  decorationColor: accentColor.withValues(alpha: 0.4),
                ),
              ),
            ),
            Icon(Icons.open_in_new_rounded,
                color: accentColor.withValues(alpha: 0.6), size: 16),
          ],
        ),
      ),
    );
  }
}

/// صف جاهز لمراسلة الدعم عبر البريد.
class ContactEmailRow extends StatelessWidget {
  const ContactEmailRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const ContactRow(
      icon: Icons.email_rounded,
      label: ContactInfo.email,
      onTap: ContactActions.sendEmail,
    );
  }
}

/// صف جاهز لفتح محادثة الواتساب.
class ContactWhatsAppRow extends StatelessWidget {
  const ContactWhatsAppRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const ContactRow(
      icon: Icons.chat_rounded,
      label: ContactInfo.whatsapp,
      onTap: ContactActions.openWhatsApp,
    );
  }
}

/// صف جاهز لفتح الموقع الإلكتروني.
class ContactWebsiteRow extends StatelessWidget {
  const ContactWebsiteRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const ContactRow(
      icon: Icons.language_rounded,
      label: ContactInfo.website,
      onTap: ContactActions.openWebsite,
    );
  }
}