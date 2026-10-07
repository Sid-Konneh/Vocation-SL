import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/dev_settings.dart';
import 'core/network/connectivity_service.dart';
import 'core/storage/local_store.dart';
import 'data/backend/backend.dart';
import 'data/backend/demo_backend.dart';
import 'data/backend/supabase_backend.dart';
import 'providers/core_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await LocalStore.open();
  final connectivity = ConnectivityService();
  await connectivity.init(simulateOffline: DevSettings.load(store).simulateOffline);

  final VocationBackend backend;
  if (AppConfig.useSupabase) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseKey);
    backend = SupabaseBackend(Supabase.instance.client);
  } else {
    backend = DemoBackend(store: store, connectivity: connectivity, devSettings: () => DevSettings.load(store));
  }

  runApp(ProviderScope(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      connectivityServiceProvider.overrideWithValue(connectivity),
      backendProvider.overrideWithValue(backend),
    ],
    child: const VocationApp(),
  ));
}
