import 'dart:io';

/// Every local IPv4 address (across all network interfaces, excluding
/// loopback) -- shown to the hosting player so they can tell their opponent
/// which one to join.
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
