package vn.emergency.ble_emergency_app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    companion object { private var retainedEngine: FlutterEngine? = null }
    private var permissionResult: MethodChannel.Result? = null
    private var permissionAction: (() -> Unit)? = null
    private var permissionRequired: Array<String> = emptyArray()
    private val handler = Handler(Looper.getMainLooper())
    override fun provideFlutterEngine(context: Context): FlutterEngine? = retainedEngine
    override fun shouldDestroyEngineWithHost(): Boolean = false
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        if (retainedEngine == null) super.configureFlutterEngine(flutterEngine)
        retainedEngine = flutterEngine
        val engine = BleEngine.get(applicationContext)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "vn.emergency/ble_events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { engine.sink = events }
            override fun onCancel(arguments: Any?) { engine.sink = null }
        })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vn.emergency/ble").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        val required = if (Build.VERSION.SDK_INT >= 31) arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT) else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
                        // Notifications show the foreground service on Android 13+; BLE still starts if the user declines.
                        val optional = if (Build.VERSION.SDK_INT >= 33) arrayOf(Manifest.permission.POST_NOTIFICATIONS) else emptyArray()
                        withPermissions(required, result, optional) { engine.start(); startForegroundService(Intent(this, MeshService::class.java)); result.success(null) }
                    }
                    "stop" -> { engine.stop(); stopService(Intent(this, MeshService::class.java)); result.success(null) }
                    "send" -> engine.send(call.argument<String>("id")!!, call.argument<ByteArray>("data")!!, result)
                    "location" -> withPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), result) { locate(result) }
                    "loadIdentity" -> result.success(loadIdentity())
                    "saveIdentity" -> { saveIdentity(call.argument<String>("value")!!); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("BLE_ERROR", e.message, null) }
        }
    }
    private fun withPermissions(required: Array<String>, result: MethodChannel.Result, optional: Array<String> = emptyArray(), action: () -> Unit) {
        val missing = (required + optional).filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) { action(); return }
        if (permissionResult != null) { result.error("BUSY", "Đang xin quyền", null); return }
        permissionResult = result; permissionAction = action; permissionRequired = required; requestPermissions(missing.toTypedArray(), 704)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 704) return
        val result = permissionResult; val action = permissionAction; val required = permissionRequired
        permissionResult = null; permissionAction = null; permissionRequired = emptyArray()
        val locationRequest = permissions.any { it == Manifest.permission.ACCESS_COARSE_LOCATION || it == Manifest.permission.ACCESS_FINE_LOCATION }
        val allowed = if (locationRequest && Build.VERSION.SDK_INT >= 31) checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED || checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED else required.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
        if (allowed) { try { action?.invoke() } catch (e: Exception) { result?.error("BLE_ERROR", e.message, null) } }
        else result?.error("PERMISSION", "Chưa cấp quyền. Mở Cài đặt ứng dụng để cấp quyền Bluetooth/vị trí.", null)
    }
    @Suppress("MissingPermission")
    private fun locate(result: MethodChannel.Result) {
        val manager = getSystemService(LocationManager::class.java)
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED || !manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) { result.error("GPS", "Cần vị trí chính xác và bật GPS để lấy vị trí ngoại tuyến", null); return }
        var complete = false
        lateinit var listener: LocationListener
        val timeout = Runnable { if (!complete) { complete = true; manager.removeUpdates(listener); result.error("GPS_TIMEOUT", "Chưa có GPS sau 12 giây", null) } }
        listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (complete) return
                complete = true; manager.removeUpdates(this); handler.removeCallbacks(timeout)
                result.success(mapOf("latitude" to location.latitude, "longitude" to location.longitude, "accuracy" to location.accuracy))
            }
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
            @Deprecated("Legacy callback") override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }
        manager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 0L, 0f, listener, Looper.getMainLooper()); handler.postDelayed(timeout, 12000)
    }
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("mesh-identity-v1", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply { init(KeyGenParameterSpec.Builder("mesh-identity-v1", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build()) }.generateKey()
    }
    private fun saveIdentity(value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        getSharedPreferences("identity", MODE_PRIVATE).edit().putString("cipher", Base64.encodeToString(encrypted, Base64.NO_WRAP)).putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP)).apply()
    }
    private fun loadIdentity(): String? {
        val prefs = getSharedPreferences("identity", MODE_PRIVATE); val value = prefs.getString("cipher", null) ?: return null
        val iv = Base64.decode(prefs.getString("iv", null) ?: error("Missing identity IV"), Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv)) }
        return String(cipher.doFinal(Base64.decode(value, Base64.NO_WRAP)), Charsets.UTF_8)
    }
}
