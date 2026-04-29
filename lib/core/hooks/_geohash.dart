/// Compact base32 geohash. Used by [MovementHooks.pushPing] so geo-indexed
/// queries can locate nearby pings without scanning the full collection.
///
/// Pure function — no I/O, no async, no Firebase dependency. Internal to the
/// hooks library; not exported.
String geohashFor(double latitude, double longitude, {int precision = 9}) {
  const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  final latRange = [-90.0, 90.0];
  final lonRange = [-180.0, 180.0];
  final hash = StringBuffer();
  var bit = 0;
  var ch = 0;
  var evenBit = true;

  while (hash.length < precision) {
    if (evenBit) {
      final mid = (lonRange[0] + lonRange[1]) / 2;
      if (longitude >= mid) {
        ch = (ch << 1) + 1;
        lonRange[0] = mid;
      } else {
        ch <<= 1;
        lonRange[1] = mid;
      }
    } else {
      final mid = (latRange[0] + latRange[1]) / 2;
      if (latitude >= mid) {
        ch = (ch << 1) + 1;
        latRange[0] = mid;
      } else {
        ch <<= 1;
        latRange[1] = mid;
      }
    }

    evenBit = !evenBit;
    if (++bit == 5) {
      hash.write(base32[ch]);
      bit = 0;
      ch = 0;
    }
  }

  return hash.toString();
}
