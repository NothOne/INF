import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A DLNA MediaRenderer found on the local network.
class CastDevice {
  const CastDevice({required this.name, required this.controlUrl, required this.location});

  final String name;
  final String controlUrl;
  final String location;
}

/// Minimal DLNA/UPnP AVTransport client. It intentionally does not depend on
/// Chromecast: most TVs and TV boxes in China expose a MediaRenderer over SSDP.
class DlnaCast {
  static const _serviceType = 'urn:schemas-upnp-org:service:AVTransport:1';

  static Future<List<CastDevice>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? sub;
    final locations = <String>{};
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        final text = utf8.decode(datagram.data, allowMalformed: true);
        final location = _header(text, 'location');
        if (location != null && location.isNotEmpty) locations.add(location);
      });
      final request = 'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 2\r\n'
          'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
          '\r\n';
      socket.send(utf8.encode(request), InternetAddress('239.255.255.250'), 1900);
      await Future<void>.delayed(timeout);
    } catch (_) {
      return const [];
    } finally {
      await sub?.cancel();
      socket?.close();
    }
    final result = <CastDevice>[];
    for (final location in locations.take(10)) {
      try {
        final device = await _readDevice(location);
        if (device != null) result.add(device);
      } catch (_) {}
    }
    return result;
  }

  static Future<void> play(CastDevice device, String videoUrl) async {
    final setUri = _envelope(
      'SetAVTransportURI',
      '<InstanceID>0</InstanceID>'
      '<CurrentURI>${_xml(videoUrl)}</CurrentURI>'
      '<CurrentURIMetaData></CurrentURIMetaData>',
    );
    await _soap(device.controlUrl, 'SetAVTransportURI', setUri);
    final play = _envelope('Play', '<InstanceID>0</InstanceID><Speed>1</Speed>');
    await _soap(device.controlUrl, 'Play', play);
  }

  static Future<CastDevice?> _readDevice(String location) async {
    final body = await _get(location);
    final name = RegExp(r'<friendlyName>(.*?)</friendlyName>', dotAll: true)
            .firstMatch(body)
            ?.group(1)
            ?.trim() ??
        '电视';
    final services = RegExp(r'<service>(.*?)</service>', dotAll: true, caseSensitive: false);
    for (final match in services.allMatches(body)) {
      final block = match.group(1) ?? '';
      if (!block.contains('AVTransport:1')) continue;
      final control = RegExp(r'<controlURL>(.*?)</controlURL>', dotAll: true)
          .firstMatch(block)
          ?.group(1)
          ?.trim();
      if (control == null || control.isEmpty) continue;
      final controlUrl = Uri.parse(location).resolve(control).toString();
      return CastDevice(name: _unescape(name), controlUrl: controlUrl, location: location);
    }
    return null;
  }

  static Future<String> _get(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'INF/0.4');
      final response = await request.close();
      return await utf8.decoder.bind(response).join();
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _soap(String url, String action, String body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
      request.headers.set('SOAPACTION', '"$_serviceType#$action"');
      request.write(body);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('DLNA $action failed: ${response.statusCode}');
      }
    } finally {
      client.close(force: true);
    }
  }

  static String _envelope(String action, String inner) => '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<s:Body>
<u:$action xmlns:u="$_serviceType">$inner</u:$action>
</s:Body>
</s:Envelope>''';

  static String? _header(String text, String name) {
    for (final line in text.split('\r\n')) {
      final index = line.indexOf(':');
      if (index <= 0) continue;
      if (line.substring(0, index).trim().toLowerCase() == name) {
        return line.substring(index + 1).trim();
      }
    }
    return null;
  }

  static String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _unescape(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"');
}
