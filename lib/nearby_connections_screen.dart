import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

class NearbyConnectionsScreen extends StatefulWidget {
  const NearbyConnectionsScreen({super.key});

  @override
  State<NearbyConnectionsScreen> createState() =>
      _NearbyConnectionsScreenState();
}

class _NearbyConnectionsScreenState extends State<NearbyConnectionsScreen> {
  // Fixed service ID for both advertiser and discoverer
  static const String serviceId = "com.pkmnapps.nearby_connections";

  // Device info
  late String userName;
  String? connectedEndpointId;

  // UI state
  bool isAdvertising = false;
  bool isDiscovering = false;
  bool isConnected = false;
  List<String> logs = [];
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    userName = "User${Random().nextInt(9999).toString().padLeft(4, '0')}";
    requestPermissions();
  }

  @override
  void dispose() {
    messageController.dispose();
    scrollController.dispose();
    // Stop all connections when leaving the screen
    Nearby().stopAllEndpoints();
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    super.dispose();
  }

  /// Request all necessary permissions for Android 12+
  Future<void> requestPermissions() async {
    addLog("Requesting permissions...");

    // Required permissions for Nearby Connections on Android 12+
    List<Permission> permissions = [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices, // For Android 13+
    ];

    Map<Permission, PermissionStatus> statuses = await permissions.request();

    bool allGranted = true;
    for (var entry in statuses.entries) {
      if (entry.value != PermissionStatus.granted) {
        addLog("Permission ${entry.key} denied");
        allGranted = false;
      }
    }

    if (allGranted) {
      addLog("All permissions granted!");
    } else {
      addLog("Some permissions denied. App may not work properly.");
    }
  }

  /// Add a log message and update UI
  void addLog(String message) {
    setState(() {
      logs.add("${DateTime.now().toLocal()}: $message");
    });
    debugPrint('Message: $message'); // Also print to console

    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Start advertising this device
  Future<void> startAdvertising() async {
    try {
      bool result = await Nearby().startAdvertising(
        userName,
        Strategy.P2P_CLUSTER,
        serviceId: serviceId,
        onConnectionInitiated: onConnectionInitiated,
        onConnectionResult: onConnectionResult,
        onDisconnected: onDisconnected,
      );

      if (result) {
        setState(() {
          isAdvertising = true;
        });
        addLog("Started advertising as '$userName'");
      } else {
        addLog("Failed to start advertising");
      }
    } catch (e) {
      addLog("Error starting advertising: $e");
    }
  }

  /// Start discovering nearby devices
  Future<void> startDiscovery() async {
    try {
      bool result = await Nearby().startDiscovery(
        serviceId,
        Strategy.P2P_CLUSTER,
        onEndpointFound: onEndpointFound,
        onEndpointLost: onEndpointLost,
      );

      if (result) {
        setState(() {
          isDiscovering = true;
        });
        addLog("Started discovering devices...");
      } else {
        addLog("Failed to start discovery");
      }
    } catch (e) {
      addLog("Error starting discovery: $e");
    }
  }

  /// Called when discovery finds an advertising device
  void onEndpointFound(
    String endpointId,
    String endpointName,
    String serviceId,
  ) {
    addLog("Found endpoint: $endpointName ($endpointId)");

    // Automatically request connection to found device
    requestConnection(endpointId, endpointName);
  }

  /// Called when a previously found endpoint is lost
  void onEndpointLost(String? endpointId) {
    addLog("Lost endpoint: $endpointId");
  }

  /// Request connection to a discovered endpoint
  Future<void> requestConnection(String endpointId, String endpointName) async {
    try {
      bool result = await Nearby().requestConnection(
        userName,
        endpointId,
        onConnectionInitiated: onConnectionInitiated,
        onConnectionResult: onConnectionResult,
        onDisconnected: onDisconnected,
      );

      if (result) {
        addLog("Requested connection to $endpointName");
      } else {
        addLog("Failed to request connection to $endpointName");
      }
    } catch (e) {
      addLog("Error requesting connection: $e");
    }
  }

  /// Called when a connection is initiated (either as advertiser or discoverer)
  void onConnectionInitiated(String endpointId, ConnectionInfo connectionInfo) {
    addLog(
      "Connection initiated with ${connectionInfo.endpointName} ($endpointId)",
    );

    // Automatically accept the connection
    acceptConnection(endpointId);
  }

  /// Accept an incoming connection
  Future<void> acceptConnection(String endpointId) async {
    try {
      bool result = await Nearby().acceptConnection(
        endpointId,
        onPayLoadRecieved:
            onPayloadReceived, // Note: typo in plugin method name
      );

      if (result) {
        addLog("Accepted connection to $endpointId");
      } else {
        addLog("Failed to accept connection to $endpointId");
      }
    } catch (e) {
      addLog("Error accepting connection: $e");
    }
  }

  /// Called when connection result is available
  void onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      setState(() {
        isConnected = true;
        connectedEndpointId = endpointId;
        // Stop advertising/discovery once connected
        isAdvertising = false;
        isDiscovering = false;
      });
      addLog("Successfully connected to $endpointId!");

      // Stop advertising and discovery
      Nearby().stopAdvertising();
      Nearby().stopDiscovery();
    } else {
      addLog("Connection failed with status: ${status.toString()}");
    }
  }

  /// Called when a device disconnects
  void onDisconnected(String endpointId) {
    setState(() {
      isConnected = false;
      connectedEndpointId = null;
    });
    addLog("Disconnected from $endpointId");
  }

  /// Called when payload (message) is received
  void onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type == PayloadType.BYTES) {
      String message = String.fromCharCodes(payload.bytes!);
      addLog("📨 Received from $endpointId: '$message'");
    }
  }

  /// Send a text message to the connected device
  Future<void> sendMessage() async {
    if (connectedEndpointId == null || messageController.text.trim().isEmpty) {
      return;
    }

    String message = messageController.text.trim();
    Uint8List bytes = Uint8List.fromList(utf8.encode(message));

    try {
      await Nearby().sendBytesPayload(connectedEndpointId!, bytes);
      addLog("📤 Sent: '$message'");
      messageController.clear();
    } catch (e) {
      addLog("Error sending message: $e");
    }
  }

  /// Stop advertising
  Future<void> stopAdvertising() async {
    await Nearby().stopAdvertising();
    setState(() {
      isAdvertising = false;
    });
    addLog("Stopped advertising");
  }

  /// Stop discovery
  Future<void> stopDiscovery() async {
    await Nearby().stopDiscovery();
    setState(() {
      isDiscovering = false;
    });
    addLog("Stopped discovery");
  }

  /// Disconnect from current endpoint
  Future<void> disconnect() async {
    if (connectedEndpointId != null) {
      await Nearby().disconnectFromEndpoint(connectedEndpointId!);
      addLog("Disconnected from $connectedEndpointId");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Connections Demo'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Device info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device: $userName',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('Status: ${_getStatusText()}'),
                    if (connectedEndpointId != null)
                      Text('Connected to: $connectedEndpointId'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Control buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: isAdvertising
                        ? stopAdvertising
                        : startAdvertising,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isAdvertising
                          ? Colors.red
                          : Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      isAdvertising ? 'Stop Advertising' : 'Start Advertising',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: isDiscovering ? stopDiscovery : startDiscovery,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDiscovering ? Colors.red : Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      isDiscovering ? 'Stop Discovery' : 'Start Discovery',
                    ),
                  ),
                ),
              ],
            ),

            if (isConnected) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: disconnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Disconnect'),
              ),
            ],

            const SizedBox(height: 16),

            // Message input (only show when connected)
            if (isConnected) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: sendMessage,
                    child: const Text('Send'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Logs section
            const Text(
              'Logs:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        logs[index],
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Get current status text for display
  String _getStatusText() {
    if (isConnected) return 'Connected ✅';
    if (isAdvertising) return 'Advertising 📡';
    if (isDiscovering) return 'Discovering 🔍';
    return 'Idle 💤';
  }
}
