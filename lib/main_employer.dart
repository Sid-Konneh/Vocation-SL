import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/network/connectivity_service.dart';
import 'core/storage/local_store.dart';
import 'data/backend/supabase_backend.dart';
import 'employer/data/supabase_employer_backend.dart';
import 'employer/employer_app.dart';
import 'employer/providers.dart';
import 'providers/core_providers.dart';

/// Entry point for "Vocation SL for Employers".
/// Requires Supabase (SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY dart-defines).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.isEmployerApp = true;
  AppConfig.mobileAuthRedirect = AppConfig.employerAuthRedirect;

  if (!AppConfig.useSupabase) {
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'The employer app needs a Supabase project.\nBuild with --dart-define=SUPABASE_URL=… and --dart-define=SUPABASE_PUBLISHABLE_KEY=…',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ));
    return;
  }

  final store = await LocalStore.open();
  final connectivity = ConnectivityService();
  await connectivity.init();
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseKey);
  final client = Supabase.instance.client;

  runApp(ProviderScope(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      connectivityServiceProvider.overrideWithValue(connectivity),
      backendProvider.overrideWithValue(SupabaseBackend(client)),
      employerBackendProvider.overrideWithValue(SupabaseEmployerBackend(client)),
    ],
    child: const EmployerApp(),
  ));
}
