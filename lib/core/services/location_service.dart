// location_service.dart - GPS location and compass heading for walking games.

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:io' show Platform;

// One location reading: GPS position and optional compass heading.
class LocationData {
  final Position position;
  final double? heading;

  LocationData({required this.position, this.heading});
}

// Provides a live GPS position stream for games.
class LocationDispatcher {
  // GPS accuracy settings. Android gets more granular control.
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

  // Returns a fresh GPS stream per caller. Previously a shared broadcast stream,
  // but the shared source was torn down when the first walk ended, so all
  // subsequent walks got no GPS and logged 0 distance. Each caller now gets
  // its own stream.
  static Stream<Position> get stream =>
      Geolocator.getPositionStream(locationSettings: _settings);
}

// Get the current location once. Asks for permission if needed.
// Returns an error with a plain message if location is off or blocked.
Future<LocationData> determineLocationData() async
{
  // Location services must be on at the system level.
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled)
  {
    return Future.error('Location services are disabled globally. Please enable them.');
  }

  // Check current permission level.
  LocationPermission permission = await Geolocator.checkPermission();
  
  // Not granted? Ask.
  if(permission == LocationPermission.denied)
  {
    permission = await Geolocator.requestPermission();

    // Still denied after asking.
    if(permission == LocationPermission.denied)
    {
      return Future.error('This application requires location permission to function.');
    }
  }

  // Permanently denied; can't ask again.
  if (permission == LocationPermission.deniedForever)
  {
    return Future.error('Location permissions are permanently denied. Please adjust app permissions in settings if you would like to change this.');
  }

  // Get the GPS fix.
  Position position = await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high);

  // Get the compass heading if available.
  double? heading;
  try {
    CompassEvent compassEvent = await FlutterCompass.events!.first;
    heading = compassEvent.heading;
  } catch (e) {
    heading = null; // Device doesn't have a compass sensor
  }

  return LocationData(position: position, heading: heading);
}