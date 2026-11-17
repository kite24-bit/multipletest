import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:testflutter/main.dart';

// Padanan Maestro: .maestro/flows/03_counter_setelah_background.yaml
void main() {
  patrolTest(
    'Counter tetap tersimpan setelah app ke background',
    tags: ['regression'],
    ($) async {
      await $.pumpWidgetAndSettle(const MyApp());

      await $(FloatingActionButton).tap();
      await $(FloatingActionButton).tap();
      expect($('2'), findsOneWidget);

      // Kirim app ke background lalu buka lagi tanpa mematikan proses.
      await $.platform.mobile.pressHome();
      await $.platform.mobile.openApp();
      await $.pumpAndSettle();

      expect($('2'), findsOneWidget);
    },
  );
}
