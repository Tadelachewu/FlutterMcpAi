// Guards the debug-only cleartext exceptions: release builds must never allow HTTP.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _withoutAts(String plist) => plist
    .replaceAll(String.fromCharCode(13), '')
    .replaceAll(RegExp(r'<!--.*?-->\s*', dotAll: true), '')
    .replaceAll(
      RegExp(r'\t<key>NSAppTransportSecurity</key>\s*<dict>.*?\n\t</dict>\n', dotAll: true),
      '',
    )
    .replaceAll('\r\n', '\n');

void main() {
  test('iOS: only the Debug configuration uses the plist with the ATS exception', () {
    final release = File('ios/Runner/Info.plist').readAsStringSync();
    final debug = File('ios/Runner/Info-Debug.plist').readAsStringSync();
    for (final path in ['ios/Runner/Info.plist', 'ios/Runner/Info-Debug.plist']) {
      expect(
        File(path).readAsBytesSync().take(5),
        '<?xml'.codeUnits,
        reason: '$path must start with <?xml (no BOM)',
      );
    }
    expect(release, isNot(contains('NSAppTransportSecurity')));
    expect(debug, contains('NSExceptionAllowsInsecureHTTPLoads'));
    expect(
      _withoutAts(debug),
      _withoutAts(release),
      reason: 'Info-Debug.plist drifted from Info.plist',
    );

    final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect('INFOPLIST_FILE = "Runner/Info-Debug.plist"'.allMatches(project), hasLength(1));
  });

  test('Android: cleartext is configured in the debug source set only', () {
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      isNot(contains('networkSecurityConfig')),
    );
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('android.permission.INTERNET'),
    );
    expect(
      File('android/app/src/debug/AndroidManifest.xml').readAsStringSync(),
      contains('@xml/network_security_config'),
    );
    expect(File('android/app/src/main/res/xml/network_security_config.xml').existsSync(), isFalse);
  });
}
