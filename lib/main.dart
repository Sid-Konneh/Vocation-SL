import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin/admin_providers.dart';
import 'admin/data/admin_backend.dart';
import 'admin/data/demo_admin_backend.dart';
import 'admin/data/supabase_admin_backend.dart';
import 'app.dart';
import 'core/config/app_config.dart';
import 'core/dev_settings.dart';
import 'core/network/connectivity_service.dart';
import 'core/storage/local_store.dart';
import 'data/backend/backend.dart';
import 'data/backend/demo_backend.dart';
import 'data/backend/message_backend.dart';
import 'data/backend/supabase_backend.dart';
import 'employer/data/demo_employer_backend.dart';
import 'employer/data/employer_backend.dart';
import 'employer/data/supabase_employer_backend.dart';
import 'employer/providers.dart';
import 'models/models.dart';
import 'providers/core_providers.dart';
import 'providers/message_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await LocalStore.open();

  // Returning from Google sign-in on the web: the login choice arrives in the
  // URL (?role=seeker|employer). Save it before Supabase finishes sign-in.
  final returnedRole = Uri.base.queryParameters['role'];
  final freshSignIn = Uri.base.queryParameters.containsKey('code');
  if (kIsWeb && freshSignIn && UserRole.values.any((r) => r.name == returnedRole)) {
    await store.setSetting('pending_role', returnedRole);
  }
  final connectivity = ConnectivityService();
  await connectivity.init(simulateOffline: DevSettings.load(store).simulateOffline);

  final VocationBackend backend;
  final EmployerBackend employerBackend;
  final AdminBackend adminBackend;
  final MessageBackend messageBackend;
  if (AppConfig.useSupabase) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseKey);
    backend = SupabaseBackend(Supabase.instance.client);
    employerBackend = SupabaseEmployerBackend(Supabase.instance.client);
    adminBackend = SupabaseAdminBackend(Supabase.instance.client);
    messageBackend = SupabaseMessageBackend(Supabase.instance.client);
  } else {
    backend = DemoBackend(store: store, connectivity: connectivity, devSettings: () => DevSettings.load(store));
    employerBackend = DemoEmployerBackend();
    adminBackend = DemoAdminBackend();
    messageBackend = DemoMessageBackend();
  }

  runApp(ProviderScope(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      connectivityServiceProvider.overrideWithValue(connectivity),
      backendProvider.overrideWithValue(backend),
      employerBackendProvider.overrideWithValue(employerBackend),
      adminBackendProvider.overrideWithValue(adminBackend),
      messageBackendProvider.overrideWithValue(messageBackend),
    ],
    child: const VocationApp(),
  ));
}
