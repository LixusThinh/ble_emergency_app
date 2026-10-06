package vn.emergency.ble_emergency_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder

class MeshService : Service() {
    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel("mesh", "Mạng BLE ngoại tuyến", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        startForeground(704, Notification.Builder(this, "mesh").setSmallIcon(android.R.drawable.stat_sys_data_bluetooth).setContentTitle("SOS Mesh đang hoạt động").setContentText("Đang quét và chuyển tiếp tin qua Bluetooth. Chạm để mở.").setOngoing(true).setContentIntent(open).build())
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() { BleEngine.get(applicationContext).stop(); super.onDestroy() }
}
