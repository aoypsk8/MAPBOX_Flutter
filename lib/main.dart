import 'package:flutter/material.dart';
import 'package:mapbox_flutter/traffic_route_line_example.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

void main() {
  runApp(MyApp());
}

const String MAPBOX_ACCESS_TOKEN =
    'pk.eyJ1IjoiYW95cHNrOCIsImEiOiJjbHlkdDZwbzUwOHRsMmxvajN3dTZhZjZmIn0.KH6ARraUJpu9WpV-_sK7kw';
const String MAPBOX_STYLE = MapboxStyles.MAPBOX_STREETS;

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: TrafficRouteLineExample()),
    );
  }
}
