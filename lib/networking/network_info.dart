import 'dart:convert';
import 'dart:io';

/// Every local IPv4 address (across all network interfaces, excluding
/// loopback) -- shown to the hosting player so they can tell their opponent
/// which one to join. Only reachable by other devices on the same LAN.
Future<List<String>> localIPv4Addresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  return [
    for (final interface in interfaces)
      for (final addr in interface.addresses) addr.address,
  ];
}

/// The host's internet-facing IPv4 address, as seen by an external lookup
/// service -- what a player joining over the internet (as opposed to the
/// same LAN) actually needs to connect to, since [localIPv4Addresses] only
/// reports addresses on the host's own interfaces, which typically sit
/// behind a router's NAT. Returns null if it can't be determined (no
/// internet access, the lookup service is unreachable, etc.) so callers can
/// fall back to telling the host to look it up themselves.
Future<String?> fetchPublicIPv4() async {
  final client = HttpClient();
  try {
    return await _requestPublicIPv4(client).timeout(const Duration(seconds: 5));
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<String?> _requestPublicIPv4(HttpClient client) async {
  final request = await client.getUrl(Uri.https('api.ipify.org', ''));
  final response = await request.close();
  if (response.statusCode != 200) return null;
  final body = await response.transform(utf8.decoder).join();
  // Reject anything that isn't actually an IPv4 address -- a captive portal
  // or transparent proxy can return 200 with an HTML page instead of
  // ipify's plain-text response.
  final trimmed = body.trim();
  final parsed = InternetAddress.tryParse(trimmed);
  return parsed?.type == InternetAddressType.IPv4 ? trimmed : null;
}
