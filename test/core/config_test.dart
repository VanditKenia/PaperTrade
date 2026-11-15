import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/core/config.dart';

void main() {
  group('parseProxyUri', () {
    test('accepts a bare https URL, with or without a trailing slash', () {
      expect(
        parseProxyUri('https://papertrade-proxy.me.workers.dev'),
        Uri.https('papertrade-proxy.me.workers.dev'),
      );
      expect(parseProxyUri(' https://p.example/ ')?.authority, 'p.example');
      expect(parseProxyUri('https://p.example:8443')?.port, 8443);
    });

    test('rejects missing, non-https and anything beyond the host', () {
      for (final bad in [
        '',
        'p.example',
        'http://p.example',
        'wss://p.example',
        'https://',
        'https://p.example/api',
        'https://p.example?x=1',
        'https://p.example#x',
        'https://user:pw@p.example',
      ]) {
        expect(parseProxyUri(bad), isNull, reason: bad);
      }
    });
  });

  test('tests run without PROXY_BASE_URL, so no proxy', () {
    expect(hasProxy, isFalse);
  });
}
