package com.example.bt_classic

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.Collections
import java.util.UUID

class BtClassicPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
  private lateinit var channel: MethodChannel

  private val requestPermissionsCode = 1001
  private val requestDiscoverableCode = 1003
  private val tag = "BtClassic"
  private val maxMessageBufferLength = 256 * 1024
  private val mainHandler = Handler(Looper.getMainLooper())
  private val myUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
  private val serviceName = "BtClassicService"

  private var bluetoothAdapter: BluetoothAdapter? = null
  private var bluetoothServerSocket: BluetoothServerSocket? = null
  private var activity: Activity? = null
  private var isServerRunning = false
  private var isServerStopping = false
  private var isCleaningUp = false
  private var receiverRegistered = false
  private var serverThread: Thread? = null

  private val connections =
      Collections.synchronizedMap(mutableMapOf<String, PeerConnection>())
  private val connectingAddresses =
      Collections.synchronizedSet(mutableSetOf<String>())

  private data class PeerConnection(
      val address: String,
      val endpoint: String,
      val socket: BluetoothSocket,
      val writeLock: Any = Any(),
  )

  private fun runOnMainThread(action: () -> Unit) {
    mainHandler.post(action)
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "bt_classic")
    channel.setMethodCallHandler(this)
    bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "requestPermissions" -> requestPermissions(result)
      "isBluetoothEnabled" -> result.success(bluetoothAdapter?.isEnabled ?: false)
      "sendMessage" -> {
        val message = call.argument<String>("message")
        val address = call.argument<String>("address")
        if (message != null) {
          sendMessage(address, message, result)
        } else {
          result.error("MISSING_PARAM", "Message is required", null)
        }
      }
      "sendFile" -> {
        val fileData = call.argument<ByteArray>("fileData")
        val fileName = call.argument<String>("fileName")
        val address = call.argument<String>("address")
        if (fileData != null && fileName != null) {
          sendFile(address, fileData, fileName, result)
        } else {
          result.error("MISSING_PARAM", "File data and filename are required", null)
        }
      }
      "disconnect" -> disconnect(call.argument<String>("address"), result)
      "isConnected" -> result.success(isConnectedTo(call.argument<String>("address")))
      "startDiscovery" -> startDiscovery(result)
      "stopDiscovery" -> stopDiscovery(result)
      "getPairedDevices" -> getPairedDevices(result)
      "connectToDevice" -> {
        val address = call.argument<String>("address")
        if (address != null) {
          connectToDevice(address, result)
        } else {
          result.error("MISSING_PARAM", "Device address is required", null)
        }
      }
      "makeDiscoverable" -> makeDiscoverable(result)
      "startServer" -> startServer(result)
      "stopServer" -> stopServer(result)
      "isServerRunning" -> result.success(isServerRunning)
      "getDeviceName" -> result.success(bluetoothAdapter?.name ?: "Unknown Device")
      else -> result.notImplemented()
    }
  }

  private fun requestPermissions(result: Result) {
    val hostActivity =
        this.activity ?: return result.error("NO_ACTIVITY", "Activity not available", null)

    val permissions = mutableListOf<String>()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      permissions.addAll(
          listOf(
              Manifest.permission.BLUETOOTH_ADVERTISE,
              Manifest.permission.BLUETOOTH_CONNECT,
              Manifest.permission.BLUETOOTH_SCAN,
          ),
      )
    } else {
      permissions.addAll(
          listOf(
              Manifest.permission.BLUETOOTH,
              Manifest.permission.BLUETOOTH_ADMIN,
          ),
      )
    }

    permissions.addAll(
        listOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ),
    )

    val missingPermissions =
        permissions.filter {
          ContextCompat.checkSelfPermission(hostActivity, it) != PackageManager.PERMISSION_GRANTED
        }

    if (missingPermissions.isNotEmpty()) {
      ActivityCompat.requestPermissions(
          hostActivity,
          missingPermissions.toTypedArray(),
          requestPermissionsCode,
      )
      result.success(false)
    } else {
      result.success(true)
    }
  }

  private fun hasBluetoothPermissions(): Boolean {
    val hostActivity = this.activity ?: return false
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      ContextCompat.checkSelfPermission(hostActivity, Manifest.permission.BLUETOOTH_ADVERTISE) ==
          PackageManager.PERMISSION_GRANTED &&
          ContextCompat.checkSelfPermission(hostActivity, Manifest.permission.BLUETOOTH_CONNECT) ==
              PackageManager.PERMISSION_GRANTED &&
          ContextCompat.checkSelfPermission(hostActivity, Manifest.permission.BLUETOOTH_SCAN) ==
              PackageManager.PERMISSION_GRANTED
    } else {
      ContextCompat.checkSelfPermission(hostActivity, Manifest.permission.BLUETOOTH) ==
          PackageManager.PERMISSION_GRANTED &&
          ContextCompat.checkSelfPermission(hostActivity, Manifest.permission.BLUETOOTH_ADMIN) ==
              PackageManager.PERMISSION_GRANTED
    }
  }

  private fun startDiscovery(result: Result) {
    if (!hasBluetoothPermissions()) {
      result.error("NO_PERMISSION", "Bluetooth permissions not granted", null)
      return
    }

    val hostActivity =
        this.activity ?: return result.error("NO_ACTIVITY", "Activity not available", null)

    ensureReceiverRegistered(hostActivity)
    if (bluetoothAdapter?.isDiscovering == true) {
      bluetoothAdapter?.cancelDiscovery()
    }

    val started = bluetoothAdapter?.startDiscovery() ?: false
    result.success(started)
  }

  private fun stopDiscovery(result: Result) {
    if (!hasBluetoothPermissions()) {
      result.error("NO_PERMISSION", "Bluetooth permissions not granted", null)
      return
    }

    result.success(bluetoothAdapter?.cancelDiscovery() ?: false)
  }

  private fun getPairedDevices(result: Result) {
    if (!hasBluetoothPermissions()) {
      result.error("NO_PERMISSION", "Bluetooth permissions not granted", null)
      return
    }

    val pairedDevices =
        bluetoothAdapter?.bondedDevices?.map { device ->
          mapOf(
              "name" to (device.name ?: "Unknown Device"),
              "address" to device.address,
          )
        } ?: emptyList()

    result.success(pairedDevices)
  }

  private fun connectToDevice(address: String, result: Result) {
    if (!hasBluetoothPermissions()) {
      result.error("NO_PERMISSION", "Bluetooth permissions not granted", null)
      return
    }

    val existingConnection = synchronized(connections) { connections[address] }
    if (existingConnection?.socket?.isConnected == true) {
      result.success(true)
      return
    }
    if (!connectingAddresses.add(address)) {
      result.success(false)
      return
    }

    Thread {
          try {
            bluetoothAdapter?.cancelDiscovery()

            val device =
                bluetoothAdapter?.getRemoteDevice(address)
                    ?: throw IOException("Bluetooth device not found.")
            val connectedSocket = connectSocket(device)
            registerSocket(connectedSocket, address, "client")

            runOnMainThread {
              result.success(true)
              channel.invokeMethod("onConnected", mapOf("address" to address))
            }
          } catch (error: Exception) {
            runOnMainThread { result.error("CONNECTION_FAILED", error.message, null) }
          } finally {
            connectingAddresses.remove(address)
          }
        }
        .start()
  }

  private fun connectSocket(device: BluetoothDevice): BluetoothSocket {
    val preferInsecure = device.bondState != BluetoothDevice.BOND_BONDED
    val attempts =
        if (preferInsecure) {
          listOf("insecure", "secure", "channel")
        } else {
          listOf("secure", "insecure", "channel")
        }
    var lastError: Exception? = null

    for (attempt in attempts) {
      var socket: BluetoothSocket? = null
      try {
        socket =
            when (attempt) {
              "secure" -> device.createRfcommSocketToServiceRecord(myUuid)
              "insecure" -> device.createInsecureRfcommSocketToServiceRecord(myUuid)
              else -> {
                val fallbackMethod =
                    device.javaClass.getMethod(
                        "createRfcommSocket",
                        Int::class.javaPrimitiveType,
                    )
                @Suppress("UNCHECKED_CAST")
                fallbackMethod.invoke(device, 1) as BluetoothSocket
              }
            }
        val candidateSocket = socket ?: throw IOException("Bluetooth socket was not created.")
        candidateSocket.connect()
        return candidateSocket
      } catch (error: Exception) {
        lastError = error
        try {
          socket?.close()
        } catch (_: IOException) {}
        Log.w(tag, "$attempt socket failed: ${error.message}")
      }
    }

    throw lastError ?: IOException("Bluetooth socket connection failed.")
  }

  private fun makeDiscoverable(result: Result) {
    if (!hasBluetoothPermissions()) {
      result.error("NO_PERMISSION", "Bluetooth permissions not granted", null)
      return
    }

    val hostActivity =
        this.activity ?: return result.error("NO_ACTIVITY", "Activity not available", null)

    val discoverableIntent =
        Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).apply {
          putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300)
        }
    hostActivity.startActivityForResult(discoverableIntent, requestDiscoverableCode)
    result.success(true)
  }

  private fun startServer(result: Result) {
    if (!hasBluetoothPermissions()) {
      result.error("NO_PERMISSION", "Bluetooth permissions not granted", null)
      return
    }

    if (isServerRunning) {
      result.success(true)
      return
    }

    Thread {
          try {
            isCleaningUp = false
            isServerStopping = false
            bluetoothServerSocket =
                try {
                  bluetoothAdapter?.listenUsingInsecureRfcommWithServiceRecord(serviceName, myUuid)
                } catch (error: IOException) {
                  Log.w(tag, "Insecure server socket failed, using secure socket: ${error.message}")
                  bluetoothAdapter?.listenUsingRfcommWithServiceRecord(serviceName, myUuid)
                }
            isServerRunning = true
            startAcceptLoop()

            runOnMainThread {
              result.success(true)
              channel.invokeMethod("onServerStarted", null)
            }
          } catch (error: IOException) {
            Log.e(tag, "Server socket failed", error)
            isServerRunning = false
            bluetoothServerSocket = null
            runOnMainThread { result.error("SERVER_FAILED", error.message, null) }
          }
        }
        .start()
  }

  private fun stopServer(result: Result) {
    try {
      isServerStopping = true
      isServerRunning = false
      bluetoothServerSocket?.close()
      bluetoothServerSocket = null
      serverThread = null
      result.success(true)
      channel.invokeMethod("onServerStopped", null)
    } catch (error: IOException) {
      result.error("STOP_FAILED", error.message, null)
    }
  }

  private fun sendMessage(address: String?, message: String, result: Result) {
    Thread {
          try {
            val connection = resolveConnection(address)
            synchronized(connection.writeLock) {
              val outputStream: OutputStream =
                  connection.socket.outputStream ?: throw IOException("No output stream.")
              outputStream.write((message + "\n").toByteArray())
              outputStream.flush()
            }
            Log.d(tag, "Sent frame to ${connection.address} (${message.length} chars)")
            runOnMainThread { result.success(true) }
          } catch (error: Exception) {
            Log.e(tag, "Send failed: ${error.message}", error)
            runOnMainThread { result.error("SEND_FAILED", error.message, null) }
          }
        }
        .start()
  }

  private fun sendFile(address: String?, fileData: ByteArray, fileName: String, result: Result) {
    Thread {
          try {
            val base64Data = Base64.encodeToString(fileData, Base64.NO_WRAP)
            val message = "FILE:$fileName:$base64Data"
            val connection = resolveConnection(address)
            synchronized(connection.writeLock) {
              val outputStream: OutputStream =
                  connection.socket.outputStream ?: throw IOException("No output stream.")
              outputStream.write((message + "\n").toByteArray())
              outputStream.flush()
            }
            runOnMainThread { result.success(true) }
          } catch (error: Exception) {
            Log.e(tag, "File send failed: ${error.message}", error)
            runOnMainThread { result.error("SEND_FAILED", error.message, null) }
          }
        }
        .start()
  }

  private fun disconnect(address: String?, result: Result) {
    try {
      if (address.isNullOrBlank()) {
        val snapshot = synchronized(connections) { connections.values.toList() }
        snapshot.forEach { closeConnection(it, notifyFlutter = true) }
      } else {
        val connection = synchronized(connections) { connections[address] }
        if (connection != null) {
          closeConnection(connection, notifyFlutter = true)
        }
      }
      result.success(true)
    } catch (error: Exception) {
      result.error("DISCONNECT_FAILED", error.message, null)
    }
  }

  private fun isConnectedTo(address: String?): Boolean {
    return synchronized(connections) {
      if (address.isNullOrBlank()) {
        connections.values.any { it.socket.isConnected }
      } else {
        connections[address]?.socket?.isConnected == true
      }
    }
  }

  private fun startAcceptLoop() {
    if (serverThread?.isAlive == true) {
      return
    }

    serverThread =
        Thread {
          while (isServerRunning && !isCleaningUp) {
            try {
              val serverSocket = bluetoothServerSocket ?: break
              val socket = serverSocket.accept() ?: continue
              val device = socket.remoteDevice
              val address = device?.address
              if (address.isNullOrBlank()) {
                socket.close()
                continue
              }

              registerSocket(socket, address, "host")
              runOnMainThread {
                channel.invokeMethod("onClientConnected", mapOf("address" to address))
              }
            } catch (error: IOException) {
              if (shouldIgnoreServerAcceptFailure()) {
                Log.i(tag, "Server socket closed while waiting for a connection")
                break
              }
              Log.e(tag, "Accept failed: ${error.message}", error)
              isServerRunning = false
              runOnMainThread {
                channel.invokeMethod(
                    "onError",
                    mapOf("error" to (error.message ?: "Server accept failed.")),
                )
                channel.invokeMethod("onServerStopped", null)
              }
              break
            }
          }
        }

    serverThread?.start()
  }

  private fun registerSocket(socket: BluetoothSocket, address: String, endpoint: String) {
    val newConnection = PeerConnection(address = address, endpoint = endpoint, socket = socket)
    val previous = synchronized(connections) { connections.put(address, newConnection) }
    if (previous != null && previous.socket != socket) {
      try {
        previous.socket.close()
      } catch (_: IOException) {}
    }
    startListening(newConnection)
  }

  private fun startListening(connection: PeerConnection) {
    Thread {
          val socket = connection.socket
          val inputStream: InputStream = socket.inputStream ?: return@Thread
          val buffer = ByteArray(4096)
          val messageBuffer = StringBuilder()

          while (socket.isConnected) {
            try {
              val bytes = inputStream.read(buffer)
              if (bytes <= 0) {
                break
              }
              messageBuffer.append(String(buffer, 0, bytes, Charsets.UTF_8))
              dispatchBufferedMessages(connection, messageBuffer)
            } catch (error: IOException) {
              if (!shouldIgnoreSocketReadFailure(connection)) {
                Log.e(tag, "Error reading from socket ${connection.address}", error)
              }
              break
            }
          }

          handleSocketClosed(connection)
        }
        .start()
  }

  private fun dispatchBufferedMessages(connection: PeerConnection, messageBuffer: StringBuilder) {
    while (true) {
      val delimiterIndex = messageBuffer.indexOf("\n")
      if (delimiterIndex == -1) {
        break
      }

      val message = messageBuffer.substring(0, delimiterIndex)
      messageBuffer.delete(0, delimiterIndex + 1)
      if (message.isNotBlank()) {
        dispatchIncomingMessage(connection, message)
      }
    }

    if (messageBuffer.length > maxMessageBufferLength) {
      Log.e(tag, "Inbound message exceeded buffer limit; clearing partial payload")
      messageBuffer.setLength(0)
      runOnMainThread {
        channel.invokeMethod(
            "onError",
            mapOf(
                "address" to connection.address,
                "error" to "Received message exceeded transport buffer size.",
            ),
        )
      }
    }
  }

  private fun dispatchIncomingMessage(connection: PeerConnection, message: String) {
    runOnMainThread {
      if (message.startsWith("FILE:")) {
        try {
          val parts = message.split(":", limit = 3)
          if (parts.size == 3) {
            val fileName = parts[1]
            val base64Data = parts[2]
            val fileData = Base64.decode(base64Data, Base64.NO_WRAP)
            channel.invokeMethod(
                "onFileReceived",
                mapOf(
                    "fileName" to fileName,
                    "fileData" to fileData,
                    "address" to connection.address,
                    "endpoint" to connection.endpoint,
                ),
            )
          } else {
            channel.invokeMethod(
                "onMessageReceived",
                mapOf(
                    "message" to message,
                    "address" to connection.address,
                    "endpoint" to connection.endpoint,
                ),
            )
          }
        } catch (error: Exception) {
          Log.e(tag, "Error processing file message: ${error.message}", error)
          channel.invokeMethod(
              "onMessageReceived",
              mapOf(
                  "message" to message,
                  "address" to connection.address,
                  "endpoint" to connection.endpoint,
              ),
          )
        }
      } else {
        channel.invokeMethod(
            "onMessageReceived",
            mapOf(
                "message" to message,
                "address" to connection.address,
                "endpoint" to connection.endpoint,
            ),
        )
      }
    }
  }

  private fun handleSocketClosed(connection: PeerConnection) {
    val removed =
        synchronized(connections) {
          val current = connections[connection.address]
          if (current?.socket == connection.socket) {
            connections.remove(connection.address)
            true
          } else {
            false
          }
        }

    try {
      connection.socket.close()
    } catch (_: IOException) {}

    if (!removed) {
      return
    }

    runOnMainThread {
      if (connection.endpoint == "host") {
        channel.invokeMethod("onClientDisconnected", mapOf("address" to connection.address))
      } else {
        channel.invokeMethod("onDisconnected", mapOf("address" to connection.address))
      }
    }
  }

  private fun closeConnection(connection: PeerConnection, notifyFlutter: Boolean) {
    val removed =
        synchronized(connections) {
          val current = connections[connection.address]
          if (current?.socket == connection.socket) {
            connections.remove(connection.address)
            true
          } else {
            false
          }
        }

    try {
      connection.socket.close()
    } catch (_: IOException) {}

    if (removed && notifyFlutter) {
      runOnMainThread {
        if (connection.endpoint == "host") {
          channel.invokeMethod("onClientDisconnected", mapOf("address" to connection.address))
        } else {
          channel.invokeMethod("onDisconnected", mapOf("address" to connection.address))
        }
      }
    }
  }

  private fun resolveConnection(address: String?): PeerConnection {
    val snapshot = synchronized(connections) { connections.toMap() }
    if (!address.isNullOrBlank()) {
      return snapshot[address] ?: throw IOException("No active Bluetooth socket for $address.")
    }
    if (snapshot.size == 1) {
      return snapshot.values.first()
    }
    if (snapshot.isEmpty()) {
      throw IOException("No active Bluetooth socket.")
    }
    throw IOException("Multiple Bluetooth peers are connected. Specify a target address.")
  }

  private fun shouldIgnoreServerAcceptFailure(): Boolean {
    return !isServerRunning || isServerStopping || isCleaningUp || bluetoothServerSocket == null
  }

  private fun shouldIgnoreSocketReadFailure(connection: PeerConnection): Boolean {
    return isCleaningUp ||
        (connection.endpoint == "host" && isServerStopping) ||
        synchronized(connections) { connections[connection.address]?.socket != connection.socket }
  }

  private fun ensureReceiverRegistered(hostActivity: Activity) {
    if (receiverRegistered) {
      return
    }

    val filter =
        IntentFilter().apply {
          addAction(BluetoothDevice.ACTION_FOUND)
          addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
    hostActivity.registerReceiver(discoveryReceiver, filter)
    receiverRegistered = true
  }

  private val discoveryReceiver =
      object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
          when (intent.action) {
            BluetoothDevice.ACTION_FOUND -> {
              val device: BluetoothDevice? =
                  if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                  } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                  }
              device?.let {
                if (hasBluetoothPermissions()) {
                  channel.invokeMethod(
                      "onDeviceFound",
                      mapOf(
                          "name" to (it.name ?: "Unknown Device"),
                          "address" to it.address,
                      ),
                  )
                }
              }
            }
            BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
              channel.invokeMethod("onDiscoveryFinished", null)
            }
          }
        }
      }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    cleanup()
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
    cleanup()
  }

  private fun cleanup() {
    try {
      isCleaningUp = true
      isServerStopping = true
      isServerRunning = false
      bluetoothServerSocket?.close()
      bluetoothServerSocket = null
      serverThread = null

      val snapshot = synchronized(connections) { connections.values.toList() }
      snapshot.forEach { closeConnection(it, notifyFlutter = false) }

      val hostActivity = activity
      if (receiverRegistered && hostActivity != null) {
        hostActivity.unregisterReceiver(discoveryReceiver)
        receiverRegistered = false
      }
    } catch (error: Exception) {
      Log.e(tag, "Error in cleanup", error)
    }
  }
}
