import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/models.dart';

/// The company's uploaded logo, or its initials on its brand colour when it
/// has none (or the image fails to load).
class CompanyLogo extends StatelessWidget {
  const CompanyLogo({super.key, required this.company, this.size = 48, this.name});
  final Company? company;
  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.28);
    final fallback = _Initials(company: company, name: name, size: size, radius: radius);
    final url = company?.logoUrl;
    Widget child = fallback;
    if (url != null && url.isNotEmpty) {
      Widget image;
      if (url.startsWith('data:')) {
        try {
          image = Image.memory(base64Decode(url.substring(url.indexOf(',') + 1)), fit: BoxFit.cover, gaplessPlayback: true);
        } catch (_) {
          image = fallback;
        }
      } else {
        image = Image.network(
          url,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => fallback,
          loadingBuilder: (_, child, progress) => progress == null ? child : fallback,
        );
      }
      child = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          border: Border.all(color: const Color(0x14000000)),
        ),
        clipBehavior: Clip.antiAlias,
        child: image,
      );
    }
    return Semantics(label: '${company?.name ?? name ?? 'Company'} logo', image: true, child: child);
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.company, required this.name, required this.size, required this.radius});
  final Company? company;
  final String? name;
  final double size;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final color = Color(company?.brandColor ?? 0xFF656C64);
    final initials = company?.initials ?? (name?.isNotEmpty == true ? name!.substring(0, 1).toUpperCase() : '?');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
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
    );
  }
}
