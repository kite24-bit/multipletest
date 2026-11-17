import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:testflutter/main.dart';

// Padanan Maestro: .maestro/flows/02_tambah_counter.yaml
void main() {
  patrolTest('Tombol + menambah counter', tags: ['regression'], ($) async {
    await $.pumpWidgetAndSettle(const MyApp());
    expect($('0'), findsOneWidget);

    await $(FloatingActionButton).tap();
    expect($('1'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await $(FloatingActionButton).tap();
    }
    expect($('5'), findsOneWidget);
  });
}
