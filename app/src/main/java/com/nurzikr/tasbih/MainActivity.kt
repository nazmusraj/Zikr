package com.nurzikr.tasbih

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.core.view.WindowCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : ComponentActivity() {

    private lateinit var webView: WebView
    private lateinit var cloudBridge: NurZikrCloudBridge
    private var pageReady = false
    private var pendingAuthUri: Uri? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)

        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = false
            settings.cacheMode = WebSettings.LOAD_DEFAULT
            settings.allowContentAccess = false
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                    val destination = request?.url ?: return true
                    if (destination.scheme == "file" || destination.scheme == "data" || destination.scheme == "blob") return false
                    runCatching { startActivity(Intent(Intent.ACTION_VIEW, destination)) }
                    return true
                }

                override fun onPageFinished(view: WebView?, url: String?) {
                    pageReady = true
                    pendingAuthUri?.let {
                        pendingAuthUri = null
                        cloudBridge.handleOAuthCallback(it)
                    }
                }
            }
            webChromeClient = WebChromeClient()
            setBackgroundColor(Color.rgb(7, 13, 23))
            addJavascriptInterface(AndroidHapticBridge(this@MainActivity), "AndroidBridge")
        }
        cloudBridge = NurZikrCloudBridge(this, webView)
        webView.addJavascriptInterface(cloudBridge, "NurZikrCloud")
        webView.loadUrl("file:///android_asset/index.html")

        setContentView(webView)
        handleAuthCallback(intent)

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (webView.canGoBack()) webView.goBack() else {
                    isEnabled = false
                    onBackPressedDispatcher.onBackPressed()
                }
            }
        })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAuthCallback(intent)
    }

    private fun handleAuthCallback(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme == "nurzikr" && uri.host == "auth") {
            if (pageReady) cloudBridge.handleOAuthCallback(uri) else pendingAuthUri = uri
        }
    }

    override fun onDestroy() {
        cloudBridge.close()
        webView.destroy()
        super.onDestroy()
    }
}

private data class ApiResponse(val status: Int, val body: String) {
    val successful: Boolean get() = status in 200..299
}

class NurZikrCloudBridge(
    private val activity: MainActivity,
    private val webView: WebView
) {
    companion object {
        private const val SUPABASE_URL = "https://opdrhpyooeeafluuzdgm.supabase.co"
        private const val SUPABASE_KEY = "sb_publishable_0sP53uXhFZSn4wmqApBqpg_OkdMmeq4"
        private const val REDIRECT_URI = "nurzikr://auth/callback"
        private const val PREFS_NAME = "nur_zikr_cloud"
        private const val ACCESS_TOKEN = "access_token"
        private const val REFRESH_TOKEN = "refresh_token"
        private const val EXPIRES_AT = "expires_at"
        private const val USER_JSON = "user_json"
        private const val CODE_VERIFIER = "oauth_code_verifier"
        private const val DEVICE_ID = "sync_device_id"
        private const val SYNC_SEQUENCE = "sync_sequence"
        private const val PENDING_OPERATION = "pending_operation"
        private const val PENDING_SEQUENCE = "pending_sequence"
    }

    private val prefs = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val executor = Executors.newSingleThreadExecutor()

    @JavascriptInterface
    fun requestSession() {
        executor.execute {
            val token = ensureAccessToken()
            if (token == null) notifySession(false) else {
                updateProfileTimezone(token)
                notifySession(true)
            }
        }
    }

    @JavascriptInterface
    fun signInWithGoogle() {
        try {
            val random = ByteArray(48).also { SecureRandom().nextBytes(it) }
            val verifier = Base64.encodeToString(random, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
            val digest = MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII))
            val challenge = Base64.encodeToString(digest, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
            prefs.edit().putString(CODE_VERIFIER, verifier).apply()
            val url = "$SUPABASE_URL/auth/v1/authorize" +
                "?provider=google" +
                "&redirect_to=${encoded(REDIRECT_URI)}" +
                "&code_challenge=${encoded(challenge)}" +
                "&code_challenge_method=s256"
            activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } catch (error: Exception) {
            notifyError("Could not open Google sign-in: ${error.message ?: "unknown error"}")
        }
    }

    fun handleOAuthCallback(uri: Uri) {
        val error = uri.getQueryParameter("error_description") ?: uri.getQueryParameter("error")
        if (!error.isNullOrBlank()) {
            notifyError(error)
            return
        }
        val code = uri.getQueryParameter("code") ?: return
        val verifier = prefs.getString(CODE_VERIFIER, null)
        if (verifier.isNullOrBlank()) {
            notifyError("The sign-in request expired. Please try again.")
            return
        }
        executor.execute {
            val body = JSONObject()
                .put("auth_code", code)
                .put("code_verifier", verifier)
            val response = apiRequest("/auth/v1/token?grant_type=pkce", "POST", body.toString(), null)
            if (response.successful && saveSession(response.body)) {
                prefs.edit().remove(CODE_VERIFIER).apply()
                ensureAccessToken()?.let { updateProfileTimezone(it) }
                notifySession(true)
                callJs("window.NurZikrNative.onAuthComplete", JSONObject().put("success", true).toString())
            } else {
                notifyError(errorMessage(response, "Google sign-in failed"))
            }
        }
    }

    @JavascriptInterface
    fun signOut() {
        executor.execute {
            val token = prefs.getString(ACCESS_TOKEN, null)
            if (!token.isNullOrBlank()) apiRequest("/auth/v1/logout", "POST", "{}", token)
            clearSession()
            notifySession(false)
        }
    }

    @JavascriptInterface
    fun syncProgress(
        operationId: String,
        zikrId: String,
        progressDate: String,
        tapDelta: Long,
        manualDelta: Long
    ) {
        executor.execute {
            val token = ensureAccessToken()
            if (token == null) {
                notifySync(operationId, false, "Sign in to sync progress")
                return@execute
            }
            val pendingId = prefs.getString(PENDING_OPERATION, null)
            if (!pendingId.isNullOrBlank() && pendingId != operationId) {
                notifySync(operationId, false, "Another progress batch is still syncing")
                return@execute
            }
            val sequence = if (pendingId == operationId) {
                prefs.getLong(PENDING_SEQUENCE, prefs.getLong(SYNC_SEQUENCE, 0L) + 1L)
            } else {
                prefs.getLong(SYNC_SEQUENCE, 0L) + 1L
            }
            prefs.edit().putString(PENDING_OPERATION, operationId).putLong(PENDING_SEQUENCE, sequence).apply()

            val deviceId = prefs.getString(DEVICE_ID, null) ?: UUID.randomUUID().toString().also {
                prefs.edit().putString(DEVICE_ID, it).apply()
            }
            val body = JSONObject()
                .put("p_device_id", deviceId)
                .put("p_sequence", sequence)
                .put("p_zikr_id", zikrId)
                .put("p_progress_date", progressDate)
                .put("p_tap_delta", tapDelta)
                .put("p_manual_delta", manualDelta)
            val response = authenticatedRequest("/rest/v1/rpc/sync_progress", "POST", body.toString())
            if (response.successful) {
                prefs.edit()
                    .putLong(SYNC_SEQUENCE, sequence)
                    .remove(PENDING_OPERATION)
                    .remove(PENDING_SEQUENCE)
                    .apply()
                notifySync(operationId, true, response.body)
            } else {
                notifySync(operationId, false, errorMessage(response, "Progress sync failed"))
            }
        }
    }

    @JavascriptInterface
    fun loadLeaderboard(period: String, groupId: String) {
        executor.execute {
            if (ensureAccessToken() == null) {
                callJs("window.NurZikrNative.onLeaderboard", JSONObject().put("error", "Sign in to view the leaderboard").toString())
                return@execute
            }
            val group = groupId.toLongOrNull()
            val leaderboardFunction = if (group == null) "get_global_leaderboard" else "get_group_leaderboard"
            val rankFunction = if (group == null) "get_my_global_rank" else "get_my_group_rank"
            val leaderboardBody = JSONObject().put("p_period", period).put("p_limit", 50)
            val rankBody = JSONObject().put("p_period", period)
            if (group != null) {
                leaderboardBody.put("p_group_id", group)
                rankBody.put("p_group_id", group)
            }
            val leaders = authenticatedRequest("/rest/v1/rpc/$leaderboardFunction", "POST", leaderboardBody.toString())
            val myRank = authenticatedRequest("/rest/v1/rpc/$rankFunction", "POST", rankBody.toString())
            val payload = JSONObject().put("period", period).put("groupId", groupId)
            if (leaders.successful && myRank.successful) {
                payload.put("rows", JSONArray(leaders.body.ifBlank { "[]" }))
                payload.put("myRank", JSONArray(myRank.body.ifBlank { "[]" }).optJSONObject(0))
            } else {
                payload.put("error", errorMessage(if (!leaders.successful) leaders else myRank, "Could not load leaderboard"))
            }
            callJs("window.NurZikrNative.onLeaderboard", payload.toString())
        }
    }

    @JavascriptInterface
    fun loadGroups() {
        executor.execute {
            val response = authenticatedRequest(
                "/rest/v1/groups?select=id,name,invite_code,owner_id&order=created_at.desc",
                "GET",
                null
            )
            val payload = JSONObject()
            if (response.successful) payload.put("groups", JSONArray(response.body.ifBlank { "[]" }))
            else payload.put("error", errorMessage(response, "Could not load groups"))
            callJs("window.NurZikrNative.onGroups", payload.toString())
        }
    }

    @JavascriptInterface
    fun loadCloudProgress() {
        executor.execute {
            if (ensureAccessToken() == null) {
                callJs("window.NurZikrNative.onCloudProgress", JSONObject().put("error", "Sign in to restore progress").toString())
                return@execute
            }
            val lifetime = authenticatedRequest(
                "/rest/v1/zikr_progress?select=zikr_id,total_count&order=zikr_id.asc",
                "GET",
                null
            )
            val cutoffCalendar = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -89) }
            val cutoff = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(cutoffCalendar.time)
            val recent = authenticatedRequest(
                "/rest/v1/daily_progress?select=progress_date,zikr_id,total_count&progress_date=gte.${encoded(cutoff)}&order=progress_date.asc&limit=10000",
                "GET",
                null
            )
            val payload = JSONObject()
            if (lifetime.successful && recent.successful) {
                payload.put("lifetime", JSONArray(lifetime.body.ifBlank { "[]" }))
                payload.put("recent", JSONArray(recent.body.ifBlank { "[]" }))
            } else {
                payload.put("error", errorMessage(if (!lifetime.successful) lifetime else recent, "Could not restore progress"))
            }
            callJs("window.NurZikrNative.onCloudProgress", payload.toString())
        }
    }

    @JavascriptInterface
    fun createGroup(name: String) = groupAction(
        "created",
        "create_group",
        JSONObject().put("p_name", name.trim())
    )

    @JavascriptInterface
    fun joinGroup(inviteCode: String) = groupAction(
        "joined",
        "join_group",
        JSONObject().put("p_invite_code", inviteCode.trim().uppercase())
    )

    @JavascriptInterface
    fun leaveGroup(groupId: String) {
        val id = groupId.toLongOrNull() ?: return notifyError("Invalid group")
        groupAction("left", "leave_group", JSONObject().put("p_group_id", id))
    }

    @JavascriptInterface
    fun deleteGroup(groupId: String) {
        val id = groupId.toLongOrNull() ?: return notifyError("Invalid group")
        groupAction("deleted", "delete_group", JSONObject().put("p_group_id", id))
    }

    private fun groupAction(action: String, function: String, body: JSONObject) {
        executor.execute {
            val response = authenticatedRequest("/rest/v1/rpc/$function", "POST", body.toString())
            val payload = JSONObject().put("action", action).put("success", response.successful)
            if (response.successful) payload.put("data", parseJson(response.body))
            else payload.put("error", errorMessage(response, "Group action failed"))
            callJs("window.NurZikrNative.onGroupAction", payload.toString())
        }
    }

    private fun parseJson(value: String): Any = try {
        if (value.trim().startsWith("[")) JSONArray(value) else if (value.isBlank()) JSONObject.NULL else JSONObject(value)
    } catch (_: Exception) { value }

    private fun authenticatedRequest(path: String, method: String, body: String?): ApiResponse {
        var token = ensureAccessToken() ?: return ApiResponse(401, "Not signed in")
        var response = apiRequest(path, method, body, token)
        if (response.status == 401) {
            token = refreshSession(force = true) ?: return response
            response = apiRequest(path, method, body, token)
        }
        return response
    }

    private fun ensureAccessToken(): String? {
        val token = prefs.getString(ACCESS_TOKEN, null) ?: return null
        val expiresAt = prefs.getLong(EXPIRES_AT, 0L)
        return if (expiresAt > System.currentTimeMillis() / 1000L + 60L) token else refreshSession(force = true)
    }

    private fun refreshSession(force: Boolean = false): String? {
        if (!force) return ensureAccessToken()
        val refresh = prefs.getString(REFRESH_TOKEN, null) ?: return null
        val response = apiRequest(
            "/auth/v1/token?grant_type=refresh_token",
            "POST",
            JSONObject().put("refresh_token", refresh).toString(),
            null
        )
        if (!response.successful || !saveSession(response.body)) {
            clearSession()
            return null
        }
        return prefs.getString(ACCESS_TOKEN, null)
    }

    private fun saveSession(body: String): Boolean {
        return try {
            val json = JSONObject(body)
            val access = json.getString("access_token")
            val refresh = json.getString("refresh_token")
            val expiresIn = json.optLong("expires_in", 3600L)
            val user = json.optJSONObject("user")
                ?: prefs.getString(USER_JSON, null)?.let { JSONObject(it) }
                ?: return false
            prefs.edit()
                .putString(ACCESS_TOKEN, access)
                .putString(REFRESH_TOKEN, refresh)
                .putLong(EXPIRES_AT, System.currentTimeMillis() / 1000L + expiresIn)
                .putString(USER_JSON, user.toString())
                .apply()
            true
        } catch (_: Exception) { false }
    }

    private fun clearSession() {
        prefs.edit().remove(ACCESS_TOKEN).remove(REFRESH_TOKEN).remove(EXPIRES_AT).remove(USER_JSON)
            .remove(PENDING_OPERATION).remove(PENDING_SEQUENCE).apply()
    }

    private fun updateProfileTimezone(token: String) {
        val user = prefs.getString(USER_JSON, null)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return
        val id = user.optString("id")
        if (id.isBlank()) return
        val zone = runCatching { TimeZone.getDefault().id }.getOrDefault("UTC")
        apiRequest(
            "/rest/v1/profiles?user_id=eq.${encoded(id)}",
            "PATCH",
            JSONObject().put("timezone", zone).toString(),
            token
        )
    }

    private fun notifySession(signedIn: Boolean) {
        val payload = JSONObject().put("signedIn", signedIn)
        if (signedIn) {
            val user = prefs.getString(USER_JSON, null)?.let { runCatching { JSONObject(it) }.getOrNull() }
            if (user != null) {
                val metadata = user.optJSONObject("user_metadata") ?: JSONObject()
                payload.put("id", user.optString("id"))
                payload.put("email", user.optString("email"))
                payload.put("displayName", metadata.optString("full_name", metadata.optString("name", "Zikr User")))
                payload.put("avatarUrl", metadata.optString("avatar_url", ""))
            }
        }
        callJs("window.NurZikrNative.onSession", payload.toString())
    }

    private fun notifySync(operationId: String, success: Boolean, detail: String) {
        val payload = JSONObject().put("operationId", operationId).put("success", success).put("detail", detail)
        callJs("window.NurZikrNative.onSyncResult", payload.toString())
    }

    private fun notifyError(message: String) {
        callJs("window.NurZikrNative.onError", JSONObject().put("message", message).toString())
    }

    private fun callJs(functionName: String, payload: String) {
        activity.runOnUiThread {
            webView.evaluateJavascript("$functionName(${JSONObject.quote(payload)});", null)
        }
    }

    private fun apiRequest(path: String, method: String, body: String?, authToken: String?): ApiResponse {
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL(SUPABASE_URL + path).openConnection() as HttpURLConnection).apply {
                requestMethod = method
                connectTimeout = 15_000
                readTimeout = 20_000
                setRequestProperty("apikey", SUPABASE_KEY)
                setRequestProperty("Accept", "application/json")
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("X-Client-Info", "nur-zikr-android/1.1.0")
                if (!authToken.isNullOrBlank()) setRequestProperty("Authorization", "Bearer $authToken")
                if (method == "PATCH") setRequestProperty("Prefer", "return=minimal")
                if (body != null) {
                    doOutput = true
                    outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                }
            }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val responseBody = stream?.bufferedReader()?.use(BufferedReader::readText).orEmpty()
            ApiResponse(status, responseBody)
        } catch (error: Exception) {
            ApiResponse(0, error.message ?: "Network unavailable")
        } finally {
            connection?.disconnect()
        }
    }

    private fun errorMessage(response: ApiResponse, fallback: String): String = try {
        val json = JSONObject(response.body)
        json.optString("msg", json.optString("message", json.optString("error_description", fallback)))
    } catch (_: Exception) {
        response.body.takeIf { it.isNotBlank() } ?: fallback
    }

    private fun encoded(value: String): String = URLEncoder.encode(value, Charsets.UTF_8.name())

    fun close() = executor.shutdownNow()
}

class AndroidHapticBridge(private val context: Context) {
    @JavascriptInterface
    fun vibrate(durationMs: Long) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(durationMs.coerceIn(1, 500), VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(durationMs.coerceIn(1, 500))
        }
    }
}
