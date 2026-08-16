import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Phase 5 keeps runtime and surface contracts independently injectable',
      () {
    final interfaces = File(
      'lib/src/platform/platform_interfaces.dart',
    ).readAsStringSync();
    final service = File(
      'lib/src/services/player/player_service.dart',
    ).readAsStringSync();
    final bootstrap = File(
      'lib/src/composition/local_tag_player_bootstrap.dart',
    ).readAsStringSync();

    expect(
      interfaces,
      contains('abstract interface class PlayerRuntimeBackend'),
    );
    expect(
      interfaces,
      contains('abstract interface class PlayerSurfaceRenderer'),
    );
    expect(service, contains('PlayerRuntimeBackend? runtimeBackend'));
    expect(service, contains('PlayerSurfaceRenderer? surfaceRenderer'));
    expect(bootstrap, contains('runtimeBackend: backend'));
    expect(bootstrap, contains('surfaceRenderer: backend'));
  });
}
