// Turns a latitude/longitude into a short text "geohash" - a code where nearby
// places share a similar start. That lets the app find pings near a spot
// quickly instead of scanning every location. Plain math, no internet needed.
//
// How it works: it keeps splitting the world in half (left/right, then
// top/bottom, over and over), writing a 1 or 0 each time for which half the
// point is in, and packs every 5 of those bits into one letter/number.
String geohashFor(double latitude, double longitude, {int precision = 9}) {
  const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  final latRange = [-90.0, 90.0];
  final lonRange = [-180.0, 180.0];
  final hash = StringBuffer();
  var bit = 0;
  var ch = 0;
  var evenBit = true;

  // Keep splitting until the code is long enough (more letters = more precise).
  while (hash.length < precision) {
    // Alternate: even steps split left/right (longitude), odd steps split
    // top/bottom (latitude). Add a 1 if the point is in the upper half, else 0,
    // and shrink the range to that half.
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
    // Every 5 bits makes one character - write it out and start the next one.
    if (++bit == 5) {
      hash.write(base32[ch]);
      bit = 0;
      ch = 0;
    }
  }

  return hash.toString();
}
