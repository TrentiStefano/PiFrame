import 'package:flutter_test/flutter_test.dart';
import 'package:pi_frame/data/terminal/terminal_settings.dart';

void main() {
  test('parseWslPath splits a wsl.localhost UNC path into distro and Linux path', () {
    expect(parseWslPath(r'\\wsl.localhost\Ubuntu\home\me\project\'), {
      'distro': 'Ubuntu',
      'linuxPath': '/home/me/project',
    });
  });

  test('parseWslPath accepts the legacy wsl\$ host and forward slashes', () {
    expect(parseWslPath(r'//wsl$/Debian/srv/app'), {'distro': 'Debian', 'linuxPath': '/srv/app'});
  });

  test('parseWslPath returns the distro root as a single slash', () {
    expect(parseWslPath(r'\\wsl.localhost\Ubuntu'), {'distro': 'Ubuntu', 'linuxPath': '/'});
  });

  test('parseWslPath returns null for a Windows or POSIX path', () {
    expect(parseWslPath(r'C:\Users\me\project'), isNull);
    expect(parseWslPath('/home/me/project'), isNull);
  });
}
