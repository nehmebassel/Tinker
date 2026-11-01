package my.otono.tinkerpush

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * TinkerPush: FCM token for the daily reminder.
 * GDScript:  var p = Engine.get_singleton("TinkerPush"); p.token_received.connect(...); p.requestToken()
 * Firebase is configured from resources generated at build time from the registered Firebase app
 * (google_app_id, google_api_key, gcm_defaultSenderId, project_id), so pushes also arrive while the
 * game is closed: the library's FirebaseMessagingService shows notification-payload messages itself.
 */
class TinkerPushPlugin(godot: Godot) : GodotPlugin(godot) {
    private val permissionRequest = 7301

    override fun getPluginName() = "TinkerPush"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("token_received", String::class.java),
        SignalInfo("push_error", String::class.java),
        SignalInfo("permission_result", java.lang.Boolean::class.java),
    )

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val ctx = activity ?: return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel("daily") == null) {
            nm.createNotificationChannel(NotificationChannel("daily", "Daily puzzle", NotificationManager.IMPORTANCE_DEFAULT))
        }
    }

    @UsedByGodot
    fun hasPermission(): Boolean {
        val ctx = activity ?: return false
        if (Build.VERSION.SDK_INT < 33) return true
        return ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    /** Asks for the notification permission if needed (Android 13+), then fetches the token. */
    @UsedByGodot
    fun requestToken() {
        val act = activity ?: return
        ensureChannel()
        if (!hasPermission()) {
            ActivityCompat.requestPermissions(act, arrayOf(Manifest.permission.POST_NOTIFICATIONS), permissionRequest)
            return
        }
        fetchToken()
    }

    /** Fetches the token without asking for anything (used at startup when already allowed). */
    @UsedByGodot
    fun fetchToken() {
        val ctx = activity ?: return
        try {
            if (FirebaseApp.getApps(ctx).isEmpty()) FirebaseApp.initializeApp(ctx)
            FirebaseMessaging.getInstance().token
                .addOnSuccessListener { t -> emitSignal("token_received", t) }
                .addOnFailureListener { e -> emitSignal("push_error", e.message ?: "token failed") }
        } catch (e: Exception) {
            emitSignal("push_error", e.message ?: e.toString())
        }
    }

    override fun onMainRequestPermissionsResult(requestCode: Int, permissions: Array<out String>?, grantResults: IntArray?) {
        super.onMainRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequest) return
        val ok = grantResults?.isNotEmpty() == true && grantResults[0] == PackageManager.PERMISSION_GRANTED
        emitSignal("permission_result", ok)
        if (ok) fetchToken()
    }
}
