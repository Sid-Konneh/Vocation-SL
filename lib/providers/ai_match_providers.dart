import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'session_providers.dart';

/// AI job matching pilot (Nov 2026). The server turns every open job and every
/// job seeker's profile into an AI "embedding" of its meaning (gte-small, see
/// supabase/ai_matching.sql); these read how close they are, from 0 to 1.
/// Empty when offline, in the demo, or before the person's profile has one.
Future<Map<String, double>> aiSimilarities(String function, String idColumn) async {
  try {
    final rows = await sb.Supabase.instance.client.rpc(function) as List<dynamic>;
    return {
      for (final r in rows.cast<Map<String, dynamic>>())
        if (r[idColumn] != null && r['similarity'] != null) r[idColumn].toString(): (r['similarity'] as num).toDouble(),
    };
  } catch (_) {
    return const {};
  }
}

/// The signed-in job seeker's AI similarity to each open job, by job id.
final aiJobMatchesProvider = FutureProvider<Map<String, double>>((ref) {
  // Ask again when the profile changes (the server updates its embedding within a minute or two).
  ref.watch(profileProvider.select((p) => p.value?.data));
  return aiSimilarities('ai_job_matches', 'job_id');
});
