import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart'; // <— add this
import 'dart:io'; // <— for File class
// import 'package:path_provider/path_provider.dart';
// import 'package:open_file/open_file.dart';

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
        onPayLoadRecieved: onPayloadReceived,
        // ✅ ADD THIS LINE - Handle transfer updates here:
        onPayloadTransferUpdate:
            (String endpointId, PayloadTransferUpdate update) {
              addLog(
                "Transfer update: id=${update.id} status=${update.status} "
                "bytesTransferred=${update.bytesTransferred}/${update.totalBytes}",
              );
            },
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
  void onPayloadReceived(String endpointId, Payload payload) async {
    if (payload.type == PayloadType.BYTES) {
      String message = String.fromCharCodes(payload.bytes!);
      addLog("📨 Received from $endpointId: '$message'");
    } else if (payload.type == PayloadType.FILE) {
      // Temporary file location
      String? tempPath = payload.uri;
      addLog("📥 File payload received from $endpointId. Temp path: $tempPath");

      // Move it or open it as needed:
      // For example, move to Downloads folder:
      if (tempPath != null) {
        // Ask for storage permission (Android 10+)
        if (await Permission.manageExternalStorage.request().isGranted ||
            await Permission.storage.request().isGranted) {
          // Public Downloads directory
          Directory downloadsDir = Directory("/storage/emulated/0/Download");

          // Give it a visible name
          String fileName = "received_file_${payload.id}";
          String newPath = "${downloadsDir.path}/$fileName";

          // Copy from temp to Downloads
          File savedFile = await File(tempPath).copy(newPath);
          addLog("✅ File saved to Downloads: ${savedFile.path}");

          // Optional: open it automatically
          // await OpenFile.open(savedFile.path);
        } else {
          addLog("❌ Storage permission denied, cannot save file");
        }
      }
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

  /// Send a file (PDF/photo/video) to the connected device
  Future<void> sendFile() async {
    if (connectedEndpointId == null) return;

    // Pick a file using file_picker
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null && result.files.single.path != null) {
      String filePath = result.files.single.path!;
      addLog("Preparing to send file: $filePath");

      try {
        await Nearby().sendFilePayload(connectedEndpointId!, filePath);
        addLog("📤 File payload sent!");
      } catch (e) {
        addLog("Error sending file: $e");
      }
    } else {
      addLog("No file selected");
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

  // ====== CHANGE 1: Updated AppBar (around line 340) ======
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✅ CHANGED: Title and color scheme
      appBar: AppBar(
        title: const Text('P2P Sharing'),
        backgroundColor: const Color(0xFF2196F3), // Blue color like in image
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      // ✅ CHANGED: Background color to match image
      backgroundColor: const Color(0xFFF5F5F5), // Light gray background
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ====== CHANGE 2: Updated Device info card (around line 350) ======
            // ✅ CHANGED: Card styling to match image
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device: $userName',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Status: ${_getStatusText()}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF666666),
                      ),
                    ),
                    if (connectedEndpointId != null)
                      Text(
                        'Connected to: $connectedEndpointId',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF666666),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ====== CHANGE 3: Updated Control buttons (around line 380) ======
            // ✅ CHANGED: Button styling to match blue/white theme
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: isAdvertising
                        ? stopAdvertising
                        : startAdvertising,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isAdvertising
                          ? const Color(0xFF2196F3)
                          : Colors.white,
                      foregroundColor: isAdvertising
                          ? Colors.white
                          : const Color(0xFF2196F3),
                      side: const BorderSide(
                        color: Color(0xFF2196F3),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          25,
                        ), // More rounded like image
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: isAdvertising ? 2 : 0,
                    ),
                    child: Text(
                      isAdvertising ? 'Stop Advertising' : 'Start Advertising',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: isDiscovering ? stopDiscovery : startDiscovery,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDiscovering
                          ? const Color(0xFF2196F3)
                          : Colors.white,
                      foregroundColor: isDiscovering
                          ? Colors.white
                          : const Color(0xFF2196F3),
                      side: const BorderSide(
                        color: Color(0xFF2196F3),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: isDiscovering ? 2 : 0,
                    ),
                    child: Text(
                      isDiscovering ? 'Stop Discovery' : 'Start Discovery',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ====== CHANGE 4: Updated Disconnect button (around line 430) ======
            if (isConnected) ...[
              const SizedBox(height: 16),
              // ✅ CHANGED: Disconnect button styling
              ElevatedButton(
                onPressed: disconnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(
                    0xFFFF5722,
                  ), // Orange-red for disconnect
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 2,
                ),
                child: const Text(
                  'Disconnect',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ====== CHANGE 5: Updated Message input section (around line 450) ======
            if (isConnected) ...[
              // ✅ CHANGED: Message input styling
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: messageController,
                            decoration: InputDecoration(
                              hintText: 'Type a message...',
                              hintStyle: const TextStyle(
                                color: Color(0xFF999999),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE0E0E0),
                                  width: 1,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: const BorderSide(
                                  color: Color(0xFF2196F3),
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            onSubmitted: (_) => sendMessage(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: sendMessage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2196F3),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          child: const Text(
                            'Send',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // ✅ CHANGED: Send File button styling
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: sendFile,
                        icon: const Icon(Icons.attach_file, size: 20),
                        label: const Text(
                          'Send File',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF2196F3),
                          side: const BorderSide(
                            color: Color(0xFF2196F3),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ====== CHANGE 6: Updated Logs section (around line 520) ======
            // ✅ CHANGED: Logs section styling
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Activity Logs',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFE0E0E0),
                        width: 1,
                      ),
                    ),
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            logs[index],
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Color(0xFF555555),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
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
