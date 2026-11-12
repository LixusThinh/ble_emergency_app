package vn.emergency.ble_emergency_app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Address
import android.location.Geocoder
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
import java.security.SecureRandom
import java.util.Locale
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
                    "geocode" -> geocode(call.argument<Double>("latitude")!!, call.argument<Double>("longitude")!!, result)
                    "loadIdentity" -> result.success(loadIdentity())
                    "saveIdentity" -> { saveIdentity(call.argument<String>("value")!!); result.success(null) }
                    "databaseDirectory" -> result.success(getDatabasePath("emergency_mesh.db").parent)
                    "databaseKey" -> try { result.success(databaseKey(call.argument<Boolean>("reset") == true)) } catch (e: Exception) { result.error("KEY_LOST", e.message, null) }
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
    /**
     * Best position within 15 s: GPS and network fixes both count, the first
     * one good to 25 m wins, otherwise the most accurate one seen. With no
     * fix at all, a last known position under 10 minutes old is returned and
     * marked stale. Needs only approximate permission when that is all the
     * user granted, though then the fix is coarse.
     */
    @Suppress("MissingPermission")
    private fun locate(result: MethodChannel.Result) {
        val manager = getSystemService(LocationManager::class.java)
        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER).filter { runCatching { manager.isProviderEnabled(it) }.getOrDefault(false) }
        if (providers.isEmpty()) { result.error("GPS", "Hãy bật Vị trí (GPS) để gửi vị trí kèm SOS", null); return }
        var complete = false
        var best: Location? = null
        lateinit var listener: LocationListener
        fun reply(location: Location?, stale: Boolean) {
            if (complete) return
            complete = true; manager.removeUpdates(listener)
            if (location == null) { result.error("GPS_TIMEOUT", "Chưa bắt được vị trí sau 15 giây", null); return }
            result.success(mapOf("latitude" to location.latitude, "longitude" to location.longitude, "accuracy" to (if (location.hasAccuracy()) location.accuracy.toDouble() else null), "time" to location.time, "provider" to location.provider, "stale" to stale))
        }
        val timeout = Runnable {
            val fallback = best ?: providers.mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }.filter { System.currentTimeMillis() - it.time < 600_000 }.minByOrNull { if (it.hasAccuracy()) it.accuracy else Float.MAX_VALUE }
            reply(fallback, best == null && fallback != null)
        }
        listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (complete) return
                val b = best
                if (b == null || (location.hasAccuracy() && (!b.hasAccuracy() || location.accuracy < b.accuracy))) best = location
                if (location.hasAccuracy() && location.accuracy <= 25f) { handler.removeCallbacks(timeout); reply(location, false) }
            }
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
            @Deprecated("Legacy callback") override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }
        for (p in providers) runCatching { manager.requestLocationUpdates(p, 0L, 0f, listener, Looper.getMainLooper()) }
        handler.postDelayed(timeout, 15000)
    }
    /** Street address for a position, in Vietnamese, from the platform geocoder (needs Internet); null when it has none. */
    private fun geocode(lat: Double, lon: Double, result: MethodChannel.Result) {
        if (!Geocoder.isPresent()) { result.success(null); return }
        val geocoder = Geocoder(this, Locale.forLanguageTag("vi-VN"))
        fun line(list: List<Address>?): String? = list?.firstOrNull()?.let { a -> (0..a.maxAddressLineIndex).mapNotNull { a.getAddressLine(it) }.joinToString(", ").ifBlank { null } }
        if (Build.VERSION.SDK_INT >= 33) {
            geocoder.getFromLocation(lat, lon, 1, object : Geocoder.GeocodeListener {
                override fun onGeocode(addresses: MutableList<Address>) { handler.post { result.success(line(addresses)) } }
                override fun onError(errorMessage: String?) { handler.post { result.error("GEOCODE", errorMessage ?: "Không tra được địa chỉ", null) } }
            })
        } else {
            Thread {
                val value = runCatching { @Suppress("DEPRECATION") geocoder.getFromLocation(lat, lon, 1) }
                handler.post { value.fold({ result.success(line(it)) }, { result.error("GEOCODE", it.message, null) }) }
            }.start()
        }
    }
    private fun key(alias: String = "mesh-identity-v1"): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply { init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build()) }.generateKey()
    }
    /** 32 random bytes as hex, the SQLite encryption key. Stored wrapped by a Keystore key that never leaves the device; created on first use, or anew when [reset]. */
    private fun databaseKey(reset: Boolean): String {
        val prefs = getSharedPreferences("database", MODE_PRIVATE)
        val wrapped = prefs.getString("cipher", null)
        if (wrapped != null && !reset) {
            val iv = Base64.decode(prefs.getString("iv", null) ?: error("Missing database key IV"), Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key("mesh-database-v1"), GCMParameterSpec(128, iv)) }
            return String(cipher.doFinal(Base64.decode(wrapped, Base64.NO_WRAP)), Charsets.UTF_8)
        }
        val raw = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val hex = raw.joinToString("") { "%02x".format(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key("mesh-database-v1")) }
        val encrypted = cipher.doFinal(hex.toByteArray(Charsets.UTF_8))
        // commit(), not apply(): the key must be on disk before the database is encrypted with it.
        check(prefs.edit().putString("cipher", Base64.encodeToString(encrypted, Base64.NO_WRAP)).putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP)).commit()) { "Không lưu được khóa database" }
        return hex
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
