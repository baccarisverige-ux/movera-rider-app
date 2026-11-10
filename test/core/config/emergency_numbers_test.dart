// v0.18.57 §79: the kept emergency list on the device (lib/core/config).
import 'package:flutter_test/flutter_test.dart';
import 'package:movera_rider/core/config/emergency_numbers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(EmergencyNumbers.reset);
  tearDown(EmergencyNumbers.reset);

  test('a broken kept list is ignored and 112 stays', () async {
    SharedPreferences.setMockInitialValues({
      EmergencyNumbers.prefsKey: '{not json',
    });
    await EmergencyNumbers.restore();
    expect(EmergencyNumbers.received, isFalse);
    expect(EmergencyNumbers.main.number, '112');
  });

  test('an empty kept list keeps 112', () async {
    SharedPreferences.setMockInitialValues({EmergencyNumbers.prefsKey: ''});
    await EmergencyNumbers.restore();
    expect(EmergencyNumbers.received, isFalse);
  });

  test('invalid rows are dropped; none valid keeps the list', () {
    expect(EmergencyNumbers.parse('x'), isNull);
    expect(EmergencyNumbers.parse(const []), isNull);
    expect(
      EmergencyNumbers.parse([
        'x',
        {
          'kind': 'nope',
          'number': '1',
          'label': {'en': 'A'},
        },
        {
          'kind': 'police',
          'number': 'abc',
          'label': {'en': 'A'},
        },
        {'kind': 'police', 'number': '17', 'label': 'A'},
        {
          'kind': 'police',
          'number': '17',
          'label': {'en': ' '},
        },
      ]),
      isNull,
    );
  });

  test('accepted list is kept and restored', () async {
    SharedPreferences.setMockInitialValues({});
    await EmergencyNumbers.accept([
      {
        'kind': 'police',
        'number': '17',
        'label': {'fr': 'Police'},
      },
    ]);
    EmergencyNumbers.reset();
    await EmergencyNumbers.restore();
    expect(EmergencyNumbers.received, isTrue);
    expect(EmergencyNumbers.main.number, '17');
    expect(EmergencyNumbers.main.localLabel, isNotEmpty);
    expect(EmergencyNumbers.others, isEmpty);
  });
}
