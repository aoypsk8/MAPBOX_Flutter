import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';

class TrafficRouteLineExample extends StatefulWidget {
  @override
  State createState() => TrafficRouteLineExampleState();
}

class TrafficRouteLineExampleState extends State<TrafficRouteLineExample> {
  late MapboxMap mapboxMap;
  final _vientianeCoordinates = Position(102.6000, 17.9757);
  final _bangkokCoordinates = Position(100.5018, 13.7563);
  final _routeCenter = Point(coordinates: Position(101.5509, 15.8660));

  List<Position> _routeCoordinates = [];
  List<Map<String, dynamic>> _steps = [];
  bool _routeLoaded = false;
  bool _is3DMode = false;
  bool _isAnimating = false;

  // Use a double for smooth animation instead of integer index
  double _currentPathPercentage = 0.0;

  Timer? _animationTimer;

  // Animation settings for smooth motion
  final int _animationFps = 30; // Higher FPS for smoother animation
  final double _animationSpeed =
      0.0001; // Lower value = slower, higher = faster

  // Car marker as a widget overlay
  final GlobalKey _mapKey = GlobalKey();
  Offset _carPosition = Offset.zero;
  double _carRotation = 0.0;
  bool _showCar = false;

  final String _mapboxAccessToken =
      'pk.eyJ1IjoiYW95cHNrOCIsImEiOiJjbHlkdDZwbzUwOHRsMmxvajN3dTZhZjZmIn0.KH6ARraUJpu9WpV-_sK7kw';

  _onMapCreated(MapboxMap mapboxMap) async {
    this.mapboxMap = mapboxMap;
  }

  _onStyleLoadedCallback(StyleLoadedEventData data) async {
    await _fetchRoute();

    if (_routeLoaded) {
      await _addRouteToMap();
      await _addTurnInstructions();
      await _addCityMarkers();

      // Initialize car position
      if (_routeCoordinates.isNotEmpty) {
        _updateCarPosition(0.0);
      }
    }
  }

  Future<void> _fetchRoute() async {
    try {
      // Format coordinates for the API request
      final String coordinates =
          "${_vientianeCoordinates.lng},${_vientianeCoordinates.lat};" +
              "${_bangkokCoordinates.lng},${_bangkokCoordinates.lat}";
      final String url =
          'https://api.mapbox.com/directions/v5/mapbox/driving/$coordinates?alternatives=false&geometries=geojson&overview=full&steps=true&access_token=$_mapboxAccessToken';

      // Make the API request
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final route = data['routes'][0];
        final geometry = route['geometry'];
        final List<dynamic> coordinates = geometry['coordinates'];

        // Convert to Position objects
        _routeCoordinates = coordinates
            .map((coord) => Position(coord[0].toDouble(), coord[1].toDouble()))
            .toList();

        // Extract turn-by-turn instructions
        final List<dynamic> legs = route['legs'];
        if (legs.isNotEmpty) {
          final List<dynamic> apiSteps = legs[0]['steps'];
          _steps = apiSteps
              .map((step) => {
                    'location': Position(
                        step['maneuver']['location'][0].toDouble(),
                        step['maneuver']['location'][1].toDouble()),
                    'instruction': step['maneuver']['instruction'],
                    'type': step['maneuver']['type'],
                    'modifier': step['maneuver'].containsKey('modifier')
                        ? step['maneuver']['modifier']
                        : '',
                    'distance': step['distance'],
                    'duration': step['duration']
                  })
              .cast<Map<String, dynamic>>()
              .toList();
        }

        _routeLoaded = true;
      } else {
        print('Failed to load route: ${response.statusCode}');
        _createSimpleRoute();
      }
    } catch (e) {
      print('Error fetching route: $e');
      _createSimpleRoute();
    }
  }

  void _createSimpleRoute() {
    // Create a simple direct route as fallback
    _routeCoordinates = [
      _vientianeCoordinates,
      Position(102.0000, 16.5000),
      Position(101.5000, 15.5000),
      Position(101.0000, 14.5000),
      _bangkokCoordinates
    ];
    _routeLoaded = true;
  }

  Future<void> _addRouteToMap() async {
    // Convert route coordinates to GeoJSON
    final routeFeature = {
      "type": "Feature",
      "properties": {},
      "geometry": {
        "type": "LineString",
        "coordinates":
            _routeCoordinates.map((pos) => [pos.lng, pos.lat]).toList()
      }
    };

    final featureCollection = {
      "type": "FeatureCollection",
      "features": [routeFeature]
    };

    // Add source for the route
    await mapboxMap.style.addSource(
        GeoJsonSource(id: "route-source", data: jsonEncode(featureCollection)));

    // Add casing for the route line (add this first so it appears behind the main line)
    await mapboxMap.style.addLayer(LineLayer(
        id: "route-casing-layer",
        sourceId: "route-source",
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineWidth: 10.0,
        lineColor: Colors.black.value,
        lineOpacity: 0.5));

    // Add the route line layer
    await mapboxMap.style.addLayer(LineLayer(
        id: "route-layer",
        sourceId: "route-source",
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineWidth: 6.0,
        lineColor: Colors.blue.value));

    // Fit the map to show the entire route
    await _fitRouteOnScreen();
  }

  Future<void> _addTurnInstructions() async {
    if (_steps.isEmpty) return;

    // Create a feature collection for the turn points
    final List<Map<String, dynamic>> features = _steps
        .map((step) => {
              "type": "Feature",
              "properties": {
                "instruction": step['instruction'],
                "type": step['type'],
                "modifier": step['modifier'],
                "distance": step['distance'],
                "duration": step['duration']
              },
              "geometry": {
                "type": "Point",
                "coordinates": [
                  (step['location'] as Position).lng,
                  (step['location'] as Position).lat
                ]
              }
            })
        .toList();

    final featureCollection = {
      "type": "FeatureCollection",
      "features": features
    };

    // Add source for turn instructions
    await mapboxMap.style.addSource(
        GeoJsonSource(id: "turns-source", data: jsonEncode(featureCollection)));

    // Add a circle layer for turn points
    await mapboxMap.style.addLayer(CircleLayer(
        id: "turns-circle-layer",
        sourceId: "turns-source",
        circleRadius: 5.0,
        circleColor: Colors.red.value,
        circleStrokeWidth: 1.0,
        circleStrokeColor: Colors.white.value));

    // Add a symbol layer for labels (optional)
    await mapboxMap.style.addLayer(SymbolLayer(
        id: "turns-symbol-layer",
        sourceId: "turns-source",
        iconImage: "marker-15", // This uses a built-in Mapbox icon
        iconSize: 1.5,
        iconAllowOverlap: true,
        textSize: 12.0,
        textOffset: [0, 2.0],
        textAnchor: TextAnchor.TOP,
        textColor: Colors.black.value,
        textHaloColor: Colors.white.value,
        textHaloWidth: 1.0,
        textAllowOverlap: false,
        textIgnorePlacement: false,
        textOptional: true,
        textMaxWidth: 8.0));
  }

  Future<void> _addCityMarkers() async {
    // Add source for city markers
    await mapboxMap.style.addSource(GeoJsonSource(
        id: "city-markers",
        data: jsonEncode({
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "properties": {
                "name": "Vientiane",
                "description": "Capital of Laos"
              },
              "geometry": {
                "type": "Point",
                "coordinates": [
                  _vientianeCoordinates.lng,
                  _vientianeCoordinates.lat
                ]
              }
            },
            {
              "type": "Feature",
              "properties": {
                "name": "Bangkok",
                "description": "Capital of Thailand"
              },
              "geometry": {
                "type": "Point",
                "coordinates": [
                  _bangkokCoordinates.lng,
                  _bangkokCoordinates.lat
                ]
              }
            }
          ]
        })));

    // Add circle layer for city markers
    await mapboxMap.style.addLayer(CircleLayer(
        id: "city-circle-layer",
        sourceId: "city-markers",
        circleRadius: 8.0,
        circleColor: Colors.green.value,
        circleStrokeWidth: 2.0,
        circleStrokeColor: Colors.white.value));

    // Add symbol layer for city labels
    await mapboxMap.style.addLayer(SymbolLayer(
        id: "city-label-layer",
        sourceId: "city-markers",
        textField: "{name}", // Use template syntax instead of expression
        textSize: 14.0,
        textOffset: [0, 1.5],
        textAnchor: TextAnchor.TOP,
        textColor: Colors.black.value,
        textHaloColor: Colors.white.value,
        textHaloWidth: 1.0));
  }

  // Calculate a position along the path based on percentage
  Position _getPositionAlongPath(double percentage) {
    if (_routeCoordinates.isEmpty) return _vientianeCoordinates;

    if (percentage >= 1.0) return _routeCoordinates.last;
    if (percentage <= 0.0) return _routeCoordinates.first;

    // Calculate the total path length
    double totalLength = 0;
    List<double> segmentLengths = [];

    for (int i = 0; i < _routeCoordinates.length - 1; i++) {
      double length =
          _calculateDistance(_routeCoordinates[i], _routeCoordinates[i + 1]);
      segmentLengths.add(length);
      totalLength += length;
    }

    // Find the position based on percentage along the total path
    double targetDistance = percentage * totalLength;
    double coveredDistance = 0;

    for (int i = 0; i < segmentLengths.length; i++) {
      if (coveredDistance + segmentLengths[i] >= targetDistance) {
        // This is the segment where our target position lies
        double segmentPercentage =
            (targetDistance - coveredDistance) / segmentLengths[i];

        // Interpolate between the two points
        return _interpolatePosition(
            _routeCoordinates[i], _routeCoordinates[i + 1], segmentPercentage);
      }
      coveredDistance += segmentLengths[i];
    }

    // Fallback (shouldn't reach here)
    return _routeCoordinates.last;
  }

  // Calculate distance between two positions in meters
  double _calculateDistance(Position pos1, Position pos2) {
    var lat1 = pos1.lat.toDouble();
    var lon1 = pos1.lng.toDouble();
    var lat2 = pos2.lat.toDouble();
    var lon2 = pos2.lng.toDouble();

    var p = 0.017453292519943295; // Math.PI / 180
    var c = math.cos;
    var a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;

    return 12742 * math.asin(math.sqrt(a)); // 2 * R; R = 6371 km
  }

  // Interpolate between two positions
  Position _interpolatePosition(
      Position start, Position end, double percentage) {
    return Position(start.lng + (end.lng - start.lng) * percentage,
        start.lat + (end.lat - start.lat) * percentage);
  }

  // Update car position using widget overlay approach with smooth animation
  Future<void> _updateCarPosition(double pathPercentage) async {
    if (_routeCoordinates.isEmpty) return;

    // Get interpolated position along the path
    final Position currentPos = _getPositionAlongPath(pathPercentage);

    // Calculate bearing (direction) for the car - look ahead slightly
    double bearing = 0;
    double lookAheadPercentage = math.min(pathPercentage + 0.01, 1.0);
    Position nextPos = _getPositionAlongPath(lookAheadPercentage);
    bearing = _calculateBearing(currentPos, nextPos);

    try {
      // Convert geo coordinates to screen coordinates
      final screenPos =
          await mapboxMap.pixelForCoordinate(Point(coordinates: currentPos));

      setState(() {
        _carPosition = Offset(screenPos.x, screenPos.y);
        _carRotation = bearing;
        _showCar = true;
      });

      // Follow the car by updating the camera - but do this less frequently
      // to avoid jerky movement
      if (_isAnimating && (pathPercentage * 100).floor() % 2 == 0) {
        await mapboxMap.flyTo(
            CameraOptions(
                center: Point(coordinates: currentPos),
                zoom: 12.0,
                bearing: bearing,
                pitch: _is3DMode ? 60.0 : 0.0),
            MapAnimationOptions(duration: 200));
      }
    } catch (e) {
      print("Error updating car position: $e");
    }
  }

  // Calculate bearing between two positions (in degrees)
  double _calculateBearing(Position start, Position end) {
    var startLat = _degreesToRadians(start.lat.toDouble());
    var startLng = _degreesToRadians(start.lng.toDouble());
    var endLat = _degreesToRadians(end.lat.toDouble());
    var endLng = _degreesToRadians(end.lng.toDouble());

    var dLng = endLng - startLng;

    var y = math.sin(dLng) * math.cos(endLat);
    var x = math.cos(startLat) * math.sin(endLat) -
        math.sin(startLat) * math.cos(endLat) * math.cos(dLng);

    var bearing = math.atan2(y, x);
    bearing = _radiansToDegrees(bearing);
    bearing = (bearing + 360) % 360;

    return bearing;
  }

  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }

  double _radiansToDegrees(double radians) {
    return radians * 180.0 / math.pi;
  }

  // Start the car animation with smooth movement
  void _startAnimation() {
    if (_isAnimating || _routeCoordinates.isEmpty) return;

    setState(() {
      _isAnimating = true;
    });

    // Calculate frame duration based on FPS
    final frameDuration =
        Duration(milliseconds: (1000 / _animationFps).round());

    // Update car position every frame
    _animationTimer = Timer.periodic(frameDuration, (timer) {
      if (_currentPathPercentage < 1.0) {
        _updateCarPosition(_currentPathPercentage);
        _currentPathPercentage += _animationSpeed;
      } else {
        // End of route
        _updateCarPosition(1.0); // Ensure we reach the final position
        _stopAnimation();
      }
    });
  }

  // Stop the car animation
  void _stopAnimation() {
    if (!_isAnimating) return;

    _animationTimer?.cancel();
    setState(() {
      _isAnimating = false;
    });
  }

  // Reset the animation to the start
  void _resetAnimation() {
    _stopAnimation();
    setState(() {
      _currentPathPercentage = 0.0;
    });
    _updateCarPosition(0.0);
  }

  Future<void> _fitRouteOnScreen() async {
    if (_routeCoordinates.isEmpty) return;

    // Calculate the bounds of the route
    double minLng = double.infinity;
    double maxLng = -double.infinity;
    double minLat = double.infinity;
    double maxLat = -double.infinity;

    for (var coord in _routeCoordinates) {
      minLng = math.min(minLng, coord.lng.toDouble());
      maxLng = math.max(maxLng, coord.lng.toDouble());
      minLat = math.min(minLat, coord.lat.toDouble());
      maxLat = math.max(maxLat, coord.lat.toDouble());
    }

    // Fly to a position that encompasses the entire route
    await mapboxMap.flyTo(
        CameraOptions(
            center: _routeCenter,
            zoom: 5.0, // Adjust based on route length
            padding: MbxEdgeInsets(left: 50, top: 50, right: 50, bottom: 50),
            pitch: _is3DMode ? 60.0 : 0.0),
        MapAnimationOptions(duration: 1500));
  }

  Future<void> _toggle3DMode() async {
    _is3DMode = !_is3DMode;

    await mapboxMap.flyTo(
        CameraOptions(
            center: _routeCenter, zoom: 5.0, pitch: _is3DMode ? 60.0 : 0.0),
        MapAnimationOptions(duration: 1000));
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Road Trip: Vientiane to Bangkok'),
        backgroundColor: Colors.blue,
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Car animation controls
          FloatingActionButton(
            heroTag: "start-animation",
            child: Icon(_isAnimating ? Icons.pause : Icons.play_arrow),
            backgroundColor: Colors.green,
            onPressed: _isAnimating ? _stopAnimation : _startAnimation,
          ),
          SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "reset-animation",
            child: Icon(Icons.replay),
            backgroundColor: Colors.orange,
            onPressed: _resetAnimation,
          ),
          SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "fit-route",
            child: Icon(Icons.fit_screen),
            backgroundColor: Colors.purple,
            onPressed: _fitRouteOnScreen,
          ),
          SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "3d-view",
            child: Icon(Icons.view_in_ar),
            backgroundColor: Colors.blue,
            onPressed: _toggle3DMode,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map widget
          MapWidget(
              key: _mapKey,
              cameraOptions: CameraOptions(center: _routeCenter, zoom: 5.0),
              styleUri: MapboxStyles.MAPBOX_STREETS,
              textureView: true,
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: _onStyleLoadedCallback),

          // Car marker overlay
          if (_showCar)
            Positioned(
              left: _carPosition.dx - 15, // Adjust for car icon size
              top: _carPosition.dy - 15, // Adjust for car icon size
              child: Transform.rotate(
                angle: _carRotation * math.pi / 180,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Icon(
                    Icons.directions_car,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),

          // Progress indicator at the bottom
          if (_routeCoordinates.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: FractionallySizedBox(
                  widthFactor: _currentPathPercentage,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
