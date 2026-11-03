package my.otono.tinkerpush

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
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
        SignalInfo("billing_connected"),
        SignalInfo("billing_disconnected"),
        SignalInfo("billing_purchase", String::class.java, String::class.java),
        SignalInfo("billing_error", Integer::class.java, String::class.java),
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

    /**
     * The recipient id ("rcpt") of the notification that opened the app, once (then cleared), or "".
     * FCM puts a tapped notification's data payload into the launch intent's extras.
     */
    @UsedByGodot
    fun launchData(): String {
        val i = activity?.intent ?: return ""
        val r = i.getStringExtra("rcpt") ?: return ""
        i.removeExtra("rcpt")
        return r
    }

    // ------------------------------------------------------------------ Google Play Billing
    // The game never trusts the client: a purchase token goes to the server (POST /purchase/google),
    // which verifies it with the Play Developer API, consumes it and credits the wallet. Purchases not
    // yet verified (app closed mid-way) are re-sent on the next connect via queryPurchasesAsync.
    private var billing: BillingClient? = null

    private fun emitPurchases(purchases: List<Purchase>?) {
        for (p in purchases ?: emptyList()) {
            if (p.purchaseState == Purchase.PurchaseState.PURCHASED && p.products.isNotEmpty()) {
                emitSignal("billing_purchase", p.products[0], p.purchaseToken)
            }
        }
    }

    @UsedByGodot
    fun billingConnect() {
        val act = activity ?: return
        val c = billing ?: BillingClient.newBuilder(act)
            .setListener { r, purchases ->
                when (r.responseCode) {
                    BillingClient.BillingResponseCode.OK -> emitPurchases(purchases)
                    BillingClient.BillingResponseCode.USER_CANCELED -> emitSignal("billing_error", r.responseCode, "cancelled")
                    else -> emitSignal("billing_error", r.responseCode, r.debugMessage)
                }
            }
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .build().also { billing = it }
        if (c.isReady) { emitSignal("billing_connected"); return }
        c.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(r: BillingResult) {
                if (r.responseCode == BillingClient.BillingResponseCode.OK) {
                    emitSignal("billing_connected")
                    c.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()) { _, list -> emitPurchases(list) }
                } else emitSignal("billing_error", r.responseCode, r.debugMessage)
            }
            override fun onBillingServiceDisconnected() { emitSignal("billing_disconnected") }
        })
    }

    @UsedByGodot
    fun billingReady(): Boolean = billing?.isReady == true

    /** Starts the Play purchase sheet for an in-app product (id as created in Play Console). */
    @UsedByGodot
    fun billingBuy(productId: String) {
        val c = billing
        if (c == null || !c.isReady) { emitSignal("billing_error", -1, "Google Play is not connected"); return }
        val q = QueryProductDetailsParams.newBuilder().setProductList(listOf(
            QueryProductDetailsParams.Product.newBuilder().setProductId(productId).setProductType(BillingClient.ProductType.INAPP).build())).build()
        c.queryProductDetailsAsync(q) { r, result ->
            val pd = result.productDetailsList.firstOrNull()
            if (pd == null) { emitSignal("billing_error", r.responseCode, "product $productId is not set up in Play Console"); return@queryProductDetailsAsync }
            val params = BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(
                BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(pd).build())).build()
            val act = activity ?: return@queryProductDetailsAsync
            act.runOnUiThread { c.launchBillingFlow(act, params) }
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
