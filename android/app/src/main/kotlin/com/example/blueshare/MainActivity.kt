package com.example.blueshare

import android.Manifest
import android.content.ContentValues
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.media.MediaScannerConnection
import android.net.Uri
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.URLConnection

class MainActivity : FlutterActivity() {
    private val methodChannelName = "blueshare/native_bluetooth"
    private val eventChannelName = "blueshare/native_bluetooth/events"

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var eventSink: EventChannel.EventSink? = null
    private var receiverRegistered = false

    private val discoveryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device = bluetoothDeviceFromIntent(intent)
                    val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE)
                    device?.let {
                        emitEvent(
                            mapOf(
                                "event" to "device",
                                "name" to (it.name ?: ""),
                                "address" to it.address,
                                "rssi" to if (rssi == Short.MIN_VALUE) null else rssi.toInt(),
                                "bonded" to (it.bondState == BluetoothDevice.BOND_BONDED),
                                "deviceClass" to it.bluetoothClass?.deviceClass,
                                "majorDeviceClass" to it.bluetoothClass?.majorDeviceClass,
                            ),
                        )
                    }
                }

                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    emitEvent(mapOf("event" to "finished"))
                }

                BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                    val device = bluetoothDeviceFromIntent(intent)
                    device?.let {
                        emitEvent(
                            mapOf(
                                "event" to "bond_state",
                                "name" to (it.name ?: ""),
                                "address" to it.address,
                                "bonded" to (it.bondState == BluetoothDevice.BOND_BONDED),
                                "deviceClass" to it.bluetoothClass?.deviceClass,
                                "majorDeviceClass" to it.bluetoothClass?.majorDeviceClass,
                            ),
                        )
                    }
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isBluetoothEnabled" -> {
                    result.success(bluetoothAdapter?.isEnabled ?: false)
                }

                "getAndroidSdkInt" -> {
                    result.success(Build.VERSION.SDK_INT)
                }

                "startDiscovery" -> startDiscovery(result)
                "stopDiscovery" -> stopDiscovery(result)
                "getBondedDevices" -> result.success(getBondedDevices())
                "pairDevice" -> pairDevice(call, result)
                "unpairDevice" -> unpairDevice(call, result)
                "publishReceivedFile" -> publishReceivedFile(call, result)
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            eventChannelName,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    ensureReceiverRegistered()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )
    }

    private fun startDiscovery(result: MethodChannel.Result) {
        if (!hasBluetoothPermissions()) {
            result.error("NO_PERMISSION", "Bluetooth permissions not granted.", null)
            return
        }

        ensureReceiverRegistered()
        if (bluetoothAdapter?.isDiscovering == true) {
            bluetoothAdapter?.cancelDiscovery()
        }
        result.success(bluetoothAdapter?.startDiscovery() ?: false)
    }

    private fun stopDiscovery(result: MethodChannel.Result) {
        if (!hasBluetoothPermissions()) {
            result.error("NO_PERMISSION", "Bluetooth permissions not granted.", null)
            return
        }
        result.success(bluetoothAdapter?.cancelDiscovery() ?: false)
    }

    private fun getBondedDevices(): List<Map<String, Any?>> {
        if (!hasBluetoothPermissions()) {
            return emptyList()
        }

        return bluetoothAdapter?.bondedDevices?.map {
            mapOf(
                "name" to (it.name ?: ""),
                "address" to it.address,
                "deviceClass" to it.bluetoothClass?.deviceClass,
                "majorDeviceClass" to it.bluetoothClass?.majorDeviceClass,
            )
        } ?: emptyList()
    }

    private fun pairDevice(call: MethodCall, result: MethodChannel.Result) {
        if (!hasBluetoothPermissions()) {
            result.error("NO_PERMISSION", "Bluetooth permissions not granted.", null)
            return
        }

        val address = call.argument<String>("address")
        if (address.isNullOrBlank()) {
            result.error("MISSING_ADDRESS", "Device address is required.", null)
            return
        }

        ensureReceiverRegistered()
        val device = bluetoothAdapter?.getRemoteDevice(address)
        result.success(device?.createBond() ?: false)
    }

    private fun unpairDevice(call: MethodCall, result: MethodChannel.Result) {
        if (!hasBluetoothPermissions()) {
            result.error("NO_PERMISSION", "Bluetooth permissions not granted.", null)
            return
        }

        val address = call.argument<String>("address")
        if (address.isNullOrBlank()) {
            result.error("MISSING_ADDRESS", "Device address is required.", null)
            return
        }

        val device = bluetoothAdapter?.getRemoteDevice(address)
        if (device == null) {
            result.error("NO_DEVICE", "Bluetooth device not found.", null)
            return
        }

        try {
            val method = device.javaClass.getMethod("removeBond")
            result.success(method.invoke(device) as? Boolean ?: false)
        } catch (error: Exception) {
            result.error("UNPAIR_FAILED", error.message, null)
        }
    }

    private fun publishReceivedFile(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType") ?: URLConnection.guessContentTypeFromName(fileName)

        if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
            result.error("MISSING_FILE", "Source path and file name are required.", null)
            return
        }

        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) {
            result.error("SOURCE_NOT_FOUND", "Received file was not found.", null)
            return
        }

        try {
            val publishedLocation =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    publishWithMediaStore(sourceFile, fileName, mimeType)
                } else {
                    publishLegacy(sourceFile, fileName, mimeType)
                }
            result.success(publishedLocation)
        } catch (error: Exception) {
            result.error("PUBLISH_FAILED", error.message, null)
        }
    }

    private fun ensureReceiverRegistered() {
        if (receiverRegistered) {
            return
        }

        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        }
        registerReceiver(discoveryReceiver, filter)
        receiverRegistered = true
    }

    private fun hasBluetoothPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_SCAN,
            ) == PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.BLUETOOTH_CONNECT,
                ) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH,
            ) == PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.ACCESS_FINE_LOCATION,
                ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun publishWithMediaStore(
        sourceFile: File,
        fileName: String,
        mimeType: String?,
    ): String {
        val resolver = applicationContext.contentResolver
        val (collection, relativePath) = resolveMediaCollection(mimeType)

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType ?: "application/octet-stream")
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val targetUri =
            resolver.insert(collection, values)
                ?: throw IllegalStateException("Unable to create MediaStore item.")

        resolver.openOutputStream(targetUri)?.use { output ->
            sourceFile.inputStream().use { input ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Unable to open MediaStore output stream.")

        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(targetUri, values, null, null)
        return targetUri.toString()
    }

    private fun publishLegacy(
        sourceFile: File,
        fileName: String,
        mimeType: String?,
    ): String {
        val rootDirectory =
            when {
                mimeType?.startsWith("image/") == true ->
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
                mimeType?.startsWith("video/") == true ->
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
                else -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            }

        val targetDirectory = File(rootDirectory, "BlueShare")
        if (!targetDirectory.exists()) {
            targetDirectory.mkdirs()
        }

        val targetFile = File(targetDirectory, fileName)
        sourceFile.copyTo(targetFile, overwrite = true)
        MediaScannerConnection.scanFile(
            this,
            arrayOf(targetFile.absolutePath),
            arrayOf(mimeType ?: "application/octet-stream"),
            null,
        )
        return targetFile.absolutePath
    }

    private fun resolveMediaCollection(mimeType: String?): Pair<Uri, String> {
        return when {
            mimeType?.startsWith("image/") == true ->
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI to "Pictures/BlueShare"
            mimeType?.startsWith("video/") == true ->
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI to "Movies/BlueShare"
            else -> MediaStore.Downloads.EXTERNAL_CONTENT_URI to "Download/BlueShare"
        }
    }

    private fun emitEvent(payload: Map<String, Any?>) {
        runOnUiThread {
            eventSink?.success(payload)
        }
    }

    @Suppress("DEPRECATION")
    private fun bluetoothDeviceFromIntent(intent: Intent): BluetoothDevice? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }
    }

    override fun onDestroy() {
        if (receiverRegistered) {
            unregisterReceiver(discoveryReceiver)
            receiverRegistered = false
        }
        super.onDestroy()
    }
}
