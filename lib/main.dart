import 'package:flutter/material.dart';
import 'nearby_connections_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key}); // Add const constructor with super.key

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nearby Connections Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const NearbyConnectionsScreen(), // Add const here too
    );
  }
}