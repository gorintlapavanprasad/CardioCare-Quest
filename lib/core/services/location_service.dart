// location_service.dart - gets the phone's GPS location (and compass heading).
// Used by the walking games to track where the player goes and how far they walk.

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:io' show Platform;

// Holds one location reading: where the phone is (position) and which way it
// points (heading, if the phone has a compass).
class LocationData {
  final Position position;
  final double? heading;

  LocationData({required this.position, this.heading});
}

// Hands out a live stream of GPS positions that games can listen to.
class LocationDispatcher {
  // How accurate/how often we want GPS updates. Android lets us tune it more.
  static LocationSettings get _settings => Platform.isAndroid
      ? AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,
          intervalDuration: const Duration(milliseconds: 1000),
          forceLocationManager: true,
        )
      : const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 2,
        ); // iOS does not allow fine-grained Location Provider control

  /// A FRESH position stream per subscription.
  ///
  /// This used to be one process-lifetime `asBroadcastStream()`. The problem:
  /// a default broadcast wrapper over a single-subscription source cancels
  /// that source once its last listener unsubscribes. Every game cancels its
  /// subscription in `_endGame`/`dispose`, so the *second* walk in the same
  /// app run (a resume, "do another quest", or a second participant logging
  /// in without a cold restart) re-listened to an already-torn-down stream,
  /// got a StateError that was swallowed, and received no GPS fixes at all -
  /// which is why distance logged as ZERO for essentially every account after
  /// the first walk. Handing back a new `getPositionStream` per call gives
  /// every walk its own live source. Each caller subscribes exactly once.
  // Give each caller its OWN fresh GPS stream (see the long note above for why).
  static Stream<Position> get stream =>
      Geolocator.getPositionStream(locationSettings: _settings);
}

// Get the phone's location right now, one time. Asks for permission if needed,
// and errors out with a friendly message if location is off or blocked.
Future<LocationData> determineLocationData() async
{
  // Check if Location Services are enabled
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled)
  {
    return Future.error('Location services are disabled globally. Please enable them.');
  }

  // check the level of location permissions available to the app
  LocationPermission permission = await Geolocator.checkPermission();
  
  // If permission hasn't been granted, ask for it
  if(permission == LocationPermission.denied)
  {
    permission = await Geolocator.requestPermission();

    // If permission is denied again
    if(permission == LocationPermission.denied)
    {
      return Future.error('This application requires location permission to function.');
    }
  }

  // If permission is permantently denied, we simply can't ask again.
  if (permission == LocationPermission.deniedForever)
  {
    return Future.error('Location permissions are permanently denied. Please adjust app permissions in settings if you would like to change this.');
  }

  // Grab the current position
  Position position = await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high);

  // get the current heading
  double? heading;
  try {
    CompassEvent compassEvent = await FlutterCompass.events!.first;
    heading = compassEvent.heading;
  } catch (e) {
    heading = null; // Device doesn't have a compass sensor
  }

  return LocationData(position: position, heading: heading);
}