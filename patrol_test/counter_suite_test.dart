import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:testflutter/main.dart';

/// Test suite untuk fitur counter di halaman utama.
///
/// Setiap `patrolTest` di bawah ini menjadi satu test case native yang
/// terpisah, sehingga bisa dibagi (shard) ke beberapa device dan dijalankan
/// secara paralel. Lihat `scripts/run_patrol_parallel.sh`.
void main() {
  group('Counter test suite', () {
    patrolTest('menampilkan judul dan counter awal bernilai 0', ($) async {
      await $.pumpWidgetAndSettle(const MyApp());

      expect($('Flutter Demo Home Page'), findsOneWidget);
      expect($('You have pushed the button this many times:'), findsOneWidget);
      expect($('0'), findsOneWidget);
    });

    patrolTest('menambah counter setiap kali tombol + ditekan', ($) async {
      await $.pumpWidgetAndSettle(const MyApp());

      for (var i = 1; i <= 3; i++) {
        await $(FloatingActionButton).tap();
        expect($('$i'), findsOneWidget);
      }

      // Pastikan aplikasi tetap di foreground (cek via native automator).
      await $.platform.mobile.pressHome();
      await $.platform.mobile.openApp();
      expect($('3'), findsOneWidget);
    });
  });
}
