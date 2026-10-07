import 'package:flutter/material.dart';

import '../models/models.dart';

/// A generated logo: the company's initials on its brand colour.
/// Swap for a network image when the backend provides logo URLs.
class CompanyLogo extends StatelessWidget {
  const CompanyLogo({super.key, required this.company, this.size = 48, this.name});
  final Company? company;
  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(company?.brandColor ?? 0xFF656C64);
    final initials = company?.initials ?? (name?.isNotEmpty == true ? name!.substring(0, 1).toUpperCase() : '?');
    return Semantics(
      label: '${company?.name ?? name ?? 'Company'} logo',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, Color.lerp(color, Colors.black, 0.25)!],
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.36, letterSpacing: -0.5),
        ),
      ),
    );
  }
}
