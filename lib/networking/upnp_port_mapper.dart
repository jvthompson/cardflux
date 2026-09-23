import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A router's UPnP Internet Gateway Device control endpoint, once
/// discovered -- the SOAP control URL to send `AddPortMapping`/
/// `DeletePortMapping` requests to, plus which of the two WAN service types
/// it answered to (needed in every SOAP request's namespace/action header).
class _GatewayService {
  _GatewayService({required this.controlUrl, required this.serviceType});

  final Uri controlUrl;
  final String serviceType;
}

/// Best-effort automatic port forwarding via UPnP IGD (Internet Gateway
/// Device) -- so a PC hosting a game doesn't need a manual router rule
/// pointed permanently at its LAN IP, which is what makes hosting from a
/// *second* PC on the same LAN impossible (a router rule for a port can only
/// point at one internal IP at a time; see `HostServer`). Talks directly to
/// the router over SSDP + SOAP instead of depending on a pub package --
/// the handful of Dart UPnP packages are either Android-only plugins or
/// unmaintained, and the protocol surface actually needed here (discover
/// the WANIPConnection/WANPPPConnection service, `AddPortMapping`,
/// `DeletePortMapping`) is small enough to own directly.
///
/// Every step is best-effort: no UPnP-capable gateway, UPnP disabled on the
/// router, or a router that refuses the mapping all just resolve to
/// `false`/no-op rather than throwing -- callers fall back to telling the
/// host to forward the port manually (see `HostSetupScreen`).
class UpnpPortMapper {
  _GatewayService? _gateway;
  int? _mappedPort;

  /// True once [requestMapping] has confirmed the router accepted the
  /// mapping.
  bool get isMapped => _mappedPort != null;

  /// Discovers the LAN's UPnP gateway and asks it to forward external
  /// [port] (TCP) to this machine's [port], both external and internal port
  /// kept equal so the address a host shares (`ip:port`) stays meaningful
  /// either way. Returns whether the router actually accepted the mapping.
  Future<bool> requestMapping({required int port, String description = 'FlutterDeck'}) async {
    final gateway = await _discoverGateway();
    if (gateway == null) return false;
    final gatewayAddress = await _resolveHost(gateway.controlUrl.host);
    if (gatewayAddress == null) return false;
    final internalClient = await _bestLocalAddressFor(gatewayAddress);
    if (internalClient == null) return false;
    final ok = await _sendPortMappingRequest(
      gateway: gateway,
      action: 'AddPortMapping',
      extraFields:
          '<NewRemoteHost></NewRemoteHost>'
          '<NewExternalPort>$port</NewExternalPort>'
          '<NewProtocol>TCP</NewProtocol>'
          '<NewInternalPort>$port</NewInternalPort>'
          '<NewInternalClient>$internalClient</NewInternalClient>'
          '<NewEnabled>1</NewEnabled>'
          '<NewPortMappingDescription>$description</NewPortMappingDescription>'
          '<NewLeaseDuration>0</NewLeaseDuration>',
    );
    if (ok) {
      _gateway = gateway;
      _mappedPort = port;
    }
    return ok;
  }

  /// Removes the mapping [requestMapping] created, if any -- e.g. when the
  /// host stops hosting. Silently does nothing if there's no active mapping
  /// (including if [requestMapping] is still in flight or never succeeded).
  Future<void> releaseMapping() async {
    final gateway = _gateway;
    final port = _mappedPort;
    if (gateway == null || port == null) return;
    _gateway = null;
    _mappedPort = null;
    await _sendPortMappingRequest(
      gateway: gateway,
      action: 'DeletePortMapping',
      extraFields: '<NewRemoteHost></NewRemoteHost>'
          '<NewExternalPort>$port</NewExternalPort>'
          '<NewProtocol>TCP</NewProtocol>',
    );
  }

  Future<bool> _sendPortMappingRequest({
    required _GatewayService gateway,
    required String action,
    required String extraFields,
  }) async {
    final body =
        '<?xml version="1.0"?>'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
        '<s:Body>'
        '<u:$action xmlns:u="${gateway.serviceType}">$extraFields</u:$action>'
        '</s:Body>'
        '</s:Envelope>';
    final client = HttpClient();
    try {
      final request = await client.postUrl(gateway.controlUrl).timeout(const Duration(seconds: 4));
      request.headers.set(HttpHeaders.contentTypeHeader, 'text/xml; charset="utf-8"');
      request.headers.set('SOAPACTION', '"${gateway.serviceType}#$action"');
      request.add(utf8.encode(body));
      final response = await request.close().timeout(const Duration(seconds: 4));
      // A router that refuses the mapping (e.g. a conflicting entry, or UPnP
      // control disabled) answers with a SOAP Fault under HTTP 500 rather
      // than a network-level failure -- draining without checking the body
      // is enough, only the status code matters here.
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Multicasts an SSDP `M-SEARCH` and returns the first responding
  /// device's WANIPConnection/WANPPPConnection control URL, if any --
  /// listens for the whole [timeout] window (rather than returning on the
  /// first reply) since the first device to answer isn't necessarily an
  /// internet gateway (e.g. a smart-TV or printer also speaking SSDP on the
  /// same LAN), so every reply's device description needs a chance to be
  /// checked.
  Future<_GatewayService?> _discoverGateway({Duration timeout = const Duration(seconds: 3)}) async {
    final locations = <String>{};
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      const message = 'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 2\r\n'
          'ST: upnp:rootdevice\r\n\r\n';
      socket.send(utf8.encode(message), InternetAddress('239.255.255.250'), 1900);
      final sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        final response = utf8.decode(datagram.data, allowMalformed: true);
        final location = RegExp(r'LOCATION:\s*(\S+)', caseSensitive: false).firstMatch(response)?.group(1)?.trim();
        if (location != null) locations.add(location);
      });
      await Future<void>.delayed(timeout);
      await sub.cancel();
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
    for (final location in locations) {
      final service = await _fetchControlUrl(location);
      if (service != null) return service;
    }
    return null;
  }

  /// Fetches the device description XML at [location] and, if it advertises
  /// a WANIPConnection or WANPPPConnection service (the two IGD service
  /// types that expose `AddPortMapping`), resolves that service's
  /// `controlURL` (which the spec allows to be relative to [location])
  /// into the [_GatewayService] to send SOAP requests to.
  Future<_GatewayService?> _fetchControlUrl(String location) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(location);
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 3));
      final response = await request.close().timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      for (final serviceType in const [
        'urn:schemas-upnp-org:service:WANIPConnection:1',
        'urn:schemas-upnp-org:service:WANPPPConnection:1',
      ]) {
        // Device descriptions list several <service> blocks -- scope the
        // controlURL lookup to the block whose <serviceType> actually
        // matches, rather than grabbing the first controlURL in the whole
        // document (which could belong to an unrelated service, e.g.
        // WANCommonInterfaceConfig).
        final serviceBlock = RegExp(
          '<service>(?:(?!</service>)[\\s\\S])*?<serviceType>$serviceType</serviceType>(?:(?!</service>)[\\s\\S])*?</service>',
        ).firstMatch(body);
        if (serviceBlock == null) continue;
        final controlUrlStr = RegExp(
          r'<controlURL>(.*?)</controlURL>',
          dotAll: true,
        ).firstMatch(serviceBlock.group(0)!)?.group(1)?.trim();
        if (controlUrlStr == null) continue;
        return _GatewayService(controlUrl: uri.resolve(controlUrlStr), serviceType: serviceType);
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<InternetAddress?> _resolveHost(String host) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return literal;
    try {
      final results = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
      return results.isEmpty ? null : results.first;
    } catch (_) {
      return null;
    }
  }

  /// Picks which of this machine's own IPv4 addresses to hand the router as
  /// `NewInternalClient` -- the address it should actually forward traffic
  /// to. Dart's `dart:io` has no portable way to ask "which local address
  /// would the OS route through to reach X" (no UDP `connect()`, and
  /// `HttpClient` doesn't surface the socket's local address), so this
  /// approximates it: on a typical home LAN, the gateway and the correct
  /// outbound interface share the same /24, so prefer whichever local
  /// address matches the gateway's first three octets, falling back to
  /// just the first non-loopback address found.
  Future<String?> _bestLocalAddressFor(InternetAddress gateway) async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    final gatewayOctets = gateway.address.split('.');
    String? fallback;
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        fallback ??= addr.address;
        final octets = addr.address.split('.');
        if (octets.length == 4 &&
            gatewayOctets.length == 4 &&
            octets[0] == gatewayOctets[0] &&
            octets[1] == gatewayOctets[1] &&
            octets[2] == gatewayOctets[2]) {
          return addr.address;
        }
      }
    }
    return fallback;
  }
}
