package com.phonelifai.lifeopt

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.Calendar

class MainActivity : FlutterActivity() {
    private val channelName = "com.phonelifai.lifeopt/usage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSignals" -> result.success(buildSignalsJson())
                "hasUsageAccess" -> result.success(hasUsageStatsPermission())
                "openUsageSettings" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun buildSignalsJson(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return baseJson(0, 0, 0, 0, 0.0, "Usage stats require Android 5+.")
        }
        if (!hasUsageStatsPermission()) {
            return baseJson(0, 0, 0, 0, 0.0, "Enable usage access for this app in system settings.")
        }

        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = System.currentTimeMillis()
        val start = end - 36L * 60 * 60 * 1000
        val events = usm.queryEvents(start, end)

        val rows = mutableListOf<EventRow>()
        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            if (e.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                val pkg = e.packageName ?: continue
                rows.add(EventRow(e.timeStamp, pkg))
            }
        }
        rows.sortBy { it.time }

        val day24 = end - 24L * 60 * 60 * 1000
        val recent = rows.filter { it.time >= day24 }

        var switches = 0
        var lastPkg: String? = null
        val distinct = mutableSetOf<String>()
        var deliveryOpens = 0
        for (row in recent) {
            distinct.add(row.pkg)
            if (lastPkg != null && lastPkg != row.pkg) switches++
            lastPkg = row.pkg
            if (isFoodDelivery(row.pkg)) deliveryOpens++
        }

        val nightMinutes = estimateNightScreenMinutes(rows)
        val sleepH = estimateSleepHours(rows)

        return baseJsonObject(nightMinutes, switches, distinct.size, deliveryOpens, sleepH, "").toString()
    }

    private data class EventRow(val time: Long, val pkg: String)

    private fun isFoodDelivery(pkg: String): Boolean {
        val p = pkg.lowercase()
        return listOf(
            "swiggy",
            "zomato",
            "ubereats",
            "uber.eats",
            "doordash",
            "grubhub",
            "foodpanda",
            "eat24",
            "deliveryhero",
            "seamless",
        ).any { p.contains(it) }
    }

    private fun estimateNightScreenMinutes(rows: List<EventRow>): Int {
        if (rows.isEmpty()) return 0
        val cal = Calendar.getInstance()
        var opens = 0
        for (r in rows) {
            cal.timeInMillis = r.time
            val h = cal.get(Calendar.HOUR_OF_DAY)
            if (h >= 22 || h < 6) opens++
        }
        return (opens * 4).coerceAtMost(300)
    }

    private fun estimateSleepHours(rows: List<EventRow>): Double {
        if (rows.size < 2) return 0.0
        val cal = Calendar.getInstance()
        var bestGap = 0L
        for (i in 0 until rows.size - 1) {
            val gap = rows[i + 1].time - rows[i].time
            if (gap < 90 * 60_000) continue
            val mid = (rows[i].time + rows[i + 1].time) / 2
            cal.timeInMillis = mid
            val h = cal.get(Calendar.HOUR_OF_DAY)
            val inSleepWindow = h <= 10 || h >= 21
            if (inSleepWindow && gap > bestGap) bestGap = gap
        }
        return (bestGap / 3600000.0).coerceIn(0.0, 11.0)
    }

    private fun hasUsageStatsPermission(): Boolean {
        val aom = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            aom.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            aom.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName,
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun baseJson(
        night: Int,
        switches: Int,
        unique: Int,
        delivery: Int,
        sleepH: Double,
        note: String,
    ): String = baseJsonObject(night, switches, unique, delivery, sleepH, note).toString()

    private fun baseJsonObject(
        night: Int,
        switches: Int,
        unique: Int,
        delivery: Int,
        sleepH: Double,
        note: String,
    ): JSONObject = JSONObject().apply {
        put("nightScreenMinutes", night)
        put("appSwitchCount24h", switches)
        put("uniqueApps24h", unique)
        put("foodDeliveryOpens24h", delivery)
        put("sleepHoursEstimate", sleepH)
        put("note", note)
    }
}
