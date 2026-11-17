import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:testflutter/main.dart';

// Padanan Maestro: .maestro/flows/01_tampilan_awal.yaml
void main() {
  patrolTest('Tampilan awal menampilkan judul dan counter 0', tags: ['smoke'], (
    $,
  ) async {
    await $.pumpWidgetAndSettle(const MyApp());

    expect($('Flutter Demo Home Page'), findsOneWidget);
    expect($('You have pushed the button this many times:'), findsOneWidget);
    expect($('0'), findsOneWidget);
    expect(find.byTooltip('Increment'), findsOneWidget);
  });
}
