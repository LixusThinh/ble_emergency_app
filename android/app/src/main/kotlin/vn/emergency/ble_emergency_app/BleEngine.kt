@file:Suppress("DEPRECATION", "MissingPermission")
package vn.emergency.ble_emergency_app

import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.ArrayDeque

/** Mutable state and GATT queues belong to the main looper. */
class BleEngine private constructor(private val context: Context) {
    companion object {
        private var instance: BleEngine? = null
        fun get(context: Context): BleEngine = instance ?: BleEngine(context.applicationContext).also { instance = it }
        val SERVICE: UUID = UUID.fromString("a8c10001-37d5-4b52-9c40-9ad6819b3000")
        val DATA: UUID = UUID.fromString("a8c10002-37d5-4b52-9c40-9ad6819b3000")
        val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
    var sink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())
    private val manager = context.getSystemService(BluetoothManager::class.java)
    private val adapter get() = manager.adapter
    private var server: BluetoothGattServer? = null
    private var dataCharacteristic: BluetoothGattCharacteristic? = null
    private var running = false
    private var scanning = false
    private var advertising = false
    private val clients = mutableMapOf<String, BluetoothGatt>()
    private val clientReady = mutableSetOf<String>()
    private val subscribed = mutableMapOf<String, BluetoothDevice>()
    private val rssi = mutableMapOf<String, Int>()
    private val mtu = mutableMapOf<String, Int>()
    private val readyMtu = mutableMapOf<String, Int>()
    private val retryAfter = mutableMapOf<String, Long>()
    private val connectionTimeouts = mutableMapOf<String, Runnable>()
    private data class Write(val id: String, val data: ByteArray, val result: MethodChannel.Result, var notification: Boolean = false)
    private val queue = ArrayDeque<Write>()
    private var active: Write? = null
    private var writeTimeout: Runnable? = null
    private fun event(value: Map<String, Any>) { sink?.success(value) }
    private fun reportError(message: String) { event(mapOf("type" to "error", "message" to message)) }
    private fun frame(device: BluetoothDevice, value: ByteArray) { event(mapOf("type" to "frame", "id" to device.address, "data" to value)) }
    private fun peer(id: String) {
        val effectiveMtu = if (clientReady.contains(id)) mtu[id] ?: 23 else mtu["s:$id"] ?: 23
        if (readyMtu[id] == effectiveMtu) return
        readyMtu[id] = effectiveMtu
        event(mapOf("type" to "peer", "id" to id, "rssi" to (rssi[id] ?: -65), "mtu" to effectiveMtu))
    }
    private fun lost(id: String) {
        if (clientReady.contains(id) || subscribed.containsKey(id)) { peer(id); return }
        if (readyMtu.remove(id) != null) event(mapOf("type" to "lost", "id" to id))
    }
    fun start() {
        if (running) return
        val a = adapter ?: throw IllegalStateException("Thiết bị không hỗ trợ Bluetooth")
        if (!a.isEnabled) throw IllegalStateException("Hãy bật Bluetooth trong cài đặt điện thoại")
        if (!a.isMultipleAdvertisementSupported || a.bluetoothLeAdvertiser == null) throw IllegalStateException("Điện thoại không hỗ trợ BLE peripheral/advertising")
        running = true
        try {
            server = manager.openGattServer(context, serverCallback) ?: throw IllegalStateException("Không mở được GATT server")
            val service = BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)
            dataCharacteristic = BluetoothGattCharacteristic(DATA, BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_INDICATE, BluetoothGattCharacteristic.PERMISSION_WRITE)
            dataCharacteristic!!.addDescriptor(BluetoothGattDescriptor(CCCD, BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE))
            service.addCharacteristic(dataCharacteristic)
            if (!server!!.addService(service)) throw IllegalStateException("Không thêm được GATT service")
            handler.post(scanCycle)
        } catch (e: Exception) { stop(); throw e }
    }
    private val scanCycle = object : Runnable {
        override fun run() {
            if (!running) return
            try {
                if (!adapter.isEnabled) { reportError("Bluetooth đã tắt. Mở lại mạng sau khi bật Bluetooth."); stop(); return }
                if (scanning) { adapter.bluetoothLeScanner?.stopScan(scanCallback); scanning = false; handler.postDelayed(this, 18000) }
                else {
                    adapter.bluetoothLeScanner?.startScan(listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE)).build()), ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), scanCallback)
                    scanning = true; handler.postDelayed(this, 12000)
                }
            } catch (e: Exception) { reportError("Lỗi quét BLE: ${e.message}"); handler.postDelayed(this, 30000) }
        }
    }
    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) { handler.post {
            if (!running) return@post
            val id = result.device.address; rssi[id] = result.rssi
            if (clients.containsKey(id) || clients.size >= 4 || subscribed.containsKey(id) || System.currentTimeMillis() < (retryAfter[id] ?: 0)) return@post
            try {
                clients[id] = result.device.connectGatt(context, false, clientCallback, BluetoothDevice.TRANSPORT_LE)
                val timeout = Runnable { if (!clientReady.contains(id)) closeClient(id) }
                connectionTimeouts[id] = timeout; handler.postDelayed(timeout, 18000)
            } catch (e: Exception) { retryAfter[id] = System.currentTimeMillis() + 30000; reportError("Kết nối BLE thất bại: ${e.message}") }
        } }
        override fun onScanFailed(errorCode: Int) { handler.post { scanning = false; reportError("Quét BLE thất bại ($errorCode)") } }
    }
    private fun advertise() {
        if (!running || advertising) return
        adapter.bluetoothLeAdvertiser.startAdvertising(AdvertiseSettings.Builder().setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY).setConnectable(true).setTimeout(0).build(), AdvertiseData.Builder().addServiceUuid(ParcelUuid(SERVICE)).setIncludeDeviceName(false).build(), advertiseCallback)
    }
    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) { handler.post { advertising = true } }
        override fun onStartFailure(errorCode: Int) { handler.post { reportError("BLE advertising thất bại ($errorCode). Tắt rồi bật lại mạng.") } }
    }
    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) { handler.post { if (running) { if (status == BluetoothGatt.GATT_SUCCESS) advertise() else reportError("Không tạo được GATT service ($status)") } } }
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) { handler.post { if (newState == BluetoothProfile.STATE_DISCONNECTED) { subscribed.remove(device.address); mtu.remove("s:${device.address}"); lost(device.address) } } }
        override fun onMtuChanged(device: BluetoothDevice, value: Int) { handler.post { mtu["s:${device.address}"] = value; if (subscribed.containsKey(device.address)) peer(device.address) } }
        override fun onDescriptorReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, descriptor: BluetoothGattDescriptor) { handler.post {
            val value = if (subscribed.containsKey(device.address)) BluetoothGattDescriptor.ENABLE_INDICATION_VALUE else BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
            server?.sendResponse(device, requestId, if (offset == 0) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_INVALID_OFFSET, offset, if (offset == 0) value else null)
        } }
        override fun onDescriptorWriteRequest(device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) { handler.post {
            val valid = running && descriptor.uuid == CCCD && !preparedWrite && offset == 0 && (value.contentEquals(BluetoothGattDescriptor.ENABLE_INDICATION_VALUE) || value.contentEquals(BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE))
            if (responseNeeded) server?.sendResponse(device, requestId, if (valid) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null)
            if (valid && value.contentEquals(BluetoothGattDescriptor.ENABLE_INDICATION_VALUE)) { subscribed[device.address] = device; peer(device.address) }
            else if (valid) { subscribed.remove(device.address); lost(device.address) }
        } }
        override fun onCharacteristicWriteRequest(device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) { handler.post {
            val valid = running && characteristic.uuid == DATA && !preparedWrite && offset == 0 && value.size <= (mtu["s:${device.address}"] ?: 23) - 3
            if (responseNeeded) server?.sendResponse(device, requestId, if (valid) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null)
            if (valid) frame(device, value)
        } }
        override fun onNotificationSent(device: BluetoothDevice, status: Int) { handler.post { if (active?.id == device.address && active?.notification == true) finish(status == BluetoothGatt.GATT_SUCCESS, "BLE indication lỗi $status") } }
    }
    private val clientCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) { handler.post {
            if (!running || clients[gatt.device.address] !== gatt) { gatt.close(); return@post }
            if (status != BluetoothGatt.GATT_SUCCESS || newState == BluetoothProfile.STATE_DISCONNECTED) closeClient(gatt.device.address)
            else if (newState == BluetoothProfile.STATE_CONNECTED) { if (!gatt.requestMtu(185)) gatt.discoverServices() }
        } }
        override fun onMtuChanged(gatt: BluetoothGatt, value: Int, status: Int) { handler.post { if (clients[gatt.device.address] === gatt) { mtu[gatt.device.address] = if (status == BluetoothGatt.GATT_SUCCESS) value else 23; gatt.discoverServices() } } }
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) { handler.post {
            if (clients[gatt.device.address] !== gatt) return@post
            val characteristic = gatt.getService(SERVICE)?.getCharacteristic(DATA); val descriptor = characteristic?.getDescriptor(CCCD)
            if (status != BluetoothGatt.GATT_SUCCESS || characteristic == null || descriptor == null) { closeClient(gatt.device.address); return@post }
            if (!gatt.setCharacteristicNotification(characteristic, true)) { closeClient(gatt.device.address); return@post }
            descriptor.value = BluetoothGattDescriptor.ENABLE_INDICATION_VALUE; if (!gatt.writeDescriptor(descriptor)) closeClient(gatt.device.address)
        } }
        override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) { handler.post {
            if (clients[gatt.device.address] !== gatt) return@post
            if (status == BluetoothGatt.GATT_SUCCESS) { connectionTimeouts.remove(gatt.device.address)?.let { handler.removeCallbacks(it) }; clientReady.add(gatt.device.address); peer(gatt.device.address) }
            else closeClient(gatt.device.address)
        } }
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            val bytes = characteristic.value?.clone() ?: return
            handler.post { if (running && clients[gatt.device.address] === gatt && characteristic.uuid == DATA) frame(gatt.device, bytes) }
        }
        override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) { handler.post { if (clients[gatt.device.address] === gatt && active?.id == gatt.device.address && active?.notification == false) finish(status == BluetoothGatt.GATT_SUCCESS, "BLE write lỗi $status") } }
    }
    private fun closeClient(id: String) {
        connectionTimeouts.remove(id)?.let { handler.removeCallbacks(it) }; clientReady.remove(id)
        clients.remove(id)?.let { it.disconnect(); it.close() }; mtu.remove(id); retryAfter[id] = System.currentTimeMillis() + 30000
        if (active?.id == id && active?.notification == false) finish(false, "Thiết bị đã ngắt kết nối")
        lost(id)
    }
    fun send(id: String, bytes: ByteArray, result: MethodChannel.Result) {
        if (!running) { result.error("STOPPED", "Mạng BLE chưa bật", null); return }
        if (queue.size >= 512) { result.error("QUEUE_FULL", "Hàng đợi BLE đầy", null); return }
        queue.add(Write(id, bytes, result)); pump()
    }
    private fun pump() {
        if (active != null || queue.isEmpty() || !running) return
        val w = queue.removeFirst(); active = w
        try {
            val gatt = clients[w.id]; val characteristic = gatt?.getService(SERVICE)?.getCharacteristic(DATA)
            if (w.data.size > (readyMtu[w.id] ?: 23) - 3) { finish(false, "Frame vượt MTU"); return }
            val submitted: Boolean
            if (clientReady.contains(w.id) && gatt != null && characteristic != null) {
                w.notification = false; characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT; characteristic.value = w.data; submitted = gatt.writeCharacteristic(characteristic)
            } else {
                val device = subscribed[w.id]; val data = dataCharacteristic
                if (device == null || data == null) { finish(false, "Không còn kết nối BLE"); return }
                w.notification = true; data.value = w.data; submitted = server?.notifyCharacteristicChanged(device, data, true) == true
            }
            if (!submitted) { finish(false, "BLE đang bận hoặc mất kết nối"); return }
            writeTimeout = Runnable { if (active === w) { finish(false, "BLE gửi quá thời gian"); closeClient(w.id); subscribed.remove(w.id)?.let { server?.cancelConnection(it) }; lost(w.id) } }.also { handler.postDelayed(it, 10000) }
        } catch (e: Exception) { finish(false, e.message ?: "BLE error") }
    }
    private fun finish(success: Boolean, message: String) {
        val w = active ?: return
        writeTimeout?.let { handler.removeCallbacks(it) }; writeTimeout = null; active = null
        if (success) w.result.success(null) else w.result.error("SEND_FAILED", message, null)
        handler.post { pump() }
    }
    fun stop() {
        if (!running && server == null) return
        running = false; handler.removeCallbacks(scanCycle); connectionTimeouts.values.forEach { handler.removeCallbacks(it) }; connectionTimeouts.clear()
        try { if (scanning) adapter.bluetoothLeScanner?.stopScan(scanCallback); adapter.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback) } catch (_: Exception) {}
        scanning = false; advertising = false; finish(false, "Mạng BLE đã tắt")
        while (queue.isNotEmpty()) queue.removeFirst().result.error("STOPPED", "Mạng BLE đã tắt", null)
        clients.values.forEach { try { it.disconnect(); it.close() } catch (_: Exception) {} }; clients.clear(); clientReady.clear()
        subscribed.clear(); server?.close(); server = null; dataCharacteristic = null; mtu.clear(); retryAfter.clear()
        readyMtu.keys.toList().forEach { event(mapOf("type" to "lost", "id" to it)) }; readyMtu.clear()
    }
}
