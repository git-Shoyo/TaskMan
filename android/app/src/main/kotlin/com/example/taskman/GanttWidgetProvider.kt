package com.example.taskman

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Bundle
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.time.LocalDate
import java.util.Date
import java.util.Locale
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

open class GanttWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        updateWidgets(context, appWidgetManager, appWidgetIds)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        updateAll(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        updateWidgets(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            updateWidgets(context, manager, allInstalledWidgetIds(context, manager).toIntArray())
        }

        fun hasInstalledWidget(context: Context): Boolean {
            val manager = AppWidgetManager.getInstance(context)
            return allInstalledWidgetIds(context, manager).isNotEmpty()
        }

        fun selectedProviderComponent(context: Context): ComponentName {
            val providerClass = when (AndroidGanttWidgetStore.loadSize(context)) {
                GanttWidgetSize(columns = 4, rows = 4) -> GanttWidgetProvider4x4::class.java
                GanttWidgetSize(columns = 4, rows = 5) -> GanttWidgetProvider4x5::class.java
                GanttWidgetSize(columns = 5, rows = 5) -> GanttWidgetProvider5x5::class.java
                else -> GanttWidgetProvider::class.java
            }
            return ComponentName(context, providerClass)
        }

        fun sizeForWidget(context: Context, appWidgetId: Int): GanttWidgetSize? {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            return providerSizeEntries(context).firstOrNull { entry ->
                appWidgetManager.getAppWidgetIds(entry.component).contains(appWidgetId)
            }?.size
        }

        private fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray,
        ) {
            val allWidgetIds = allInstalledWidgetIds(context, appWidgetManager)
            val primaryWidgetId = allWidgetIds.firstOrNull()
            val idsToUpdate = if (appWidgetIds.isEmpty()) {
                allWidgetIds
            } else {
                appWidgetIds.toList()
            }

            for (appWidgetId in idsToUpdate) {
                val isDuplicate = primaryWidgetId != null && appWidgetId != primaryWidgetId
                val views = RemoteViews(
                    context.packageName,
                    R.layout.taskman_gantt_widget,
                )
                views.setImageViewBitmap(
                    R.id.gantt_widget_canvas,
                    TaskManGanttWidgetRenderer.render(
                        context = context,
                        appWidgetId = appWidgetId,
                        isDuplicate = isDuplicate,
                    ),
                )
                views.setOnClickPendingIntent(
                    R.id.gantt_widget_root,
                    launchAppPendingIntent(context),
                )
                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
        }

        private fun allProviderComponents(context: Context): List<ComponentName> {
            return providerSizeEntries(context).map { it.component }
        }

        private fun allInstalledWidgetIds(
            context: Context,
            appWidgetManager: AppWidgetManager,
        ): List<Int> {
            return allProviderComponents(context)
                .flatMap { appWidgetManager.getAppWidgetIds(it).toList() }
                .sorted()
        }

        private fun launchAppPendingIntent(context: Context): PendingIntent {
            val intent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)

            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun providerSizeEntries(context: Context): List<ProviderSizeEntry> {
            return listOf(
                ProviderSizeEntry(
                    component = ComponentName(context, GanttWidgetProvider::class.java),
                    size = GanttWidgetSize(columns = 5, rows = 4),
                ),
                ProviderSizeEntry(
                    component = ComponentName(context, GanttWidgetProvider4x4::class.java),
                    size = GanttWidgetSize(columns = 4, rows = 4),
                ),
                ProviderSizeEntry(
                    component = ComponentName(context, GanttWidgetProvider4x5::class.java),
                    size = GanttWidgetSize(columns = 4, rows = 5),
                ),
                ProviderSizeEntry(
                    component = ComponentName(context, GanttWidgetProvider5x5::class.java),
                    size = GanttWidgetSize(columns = 5, rows = 5),
                ),
            )
        }
    }
}

private data class ProviderSizeEntry(
    val component: ComponentName,
    val size: GanttWidgetSize,
)

class GanttWidgetProvider4x4 : GanttWidgetProvider()

class GanttWidgetProvider4x5 : GanttWidgetProvider()

class GanttWidgetProvider5x5 : GanttWidgetProvider()

object AndroidGanttWidgetStore {
    private const val PREFS_NAME = "taskman_android_gantt_widget"
    private const val KEY_TASKS = "tasks"
    private const val KEY_UPDATED_AT = "updated_at"
    private const val KEY_COLUMNS = "columns"
    private const val KEY_ROWS = "rows"
    private const val DEFAULT_COLUMNS = 5
    private const val DEFAULT_ROWS = 4

    fun saveTasks(context: Context, arguments: Any?) {
        val tasks = arguments as? List<*> ?: emptyList<Any?>()
        val encodedTasks = JSONArray()

        for (task in tasks) {
            val taskMap = task as? Map<*, *> ?: continue
            val taskJson = JSONObject()
            for ((key, value) in taskMap) {
                val name = key as? String ?: continue
                taskJson.put(name, value ?: JSONObject.NULL)
            }
            encodedTasks.put(taskJson)
        }

        prefs(context).edit()
            .putString(KEY_TASKS, encodedTasks.toString())
            .putLong(KEY_UPDATED_AT, System.currentTimeMillis())
            .apply()
    }

    fun hasCachedTasks(context: Context): Boolean {
        return prefs(context).contains(KEY_TASKS)
    }

    fun loadTasks(context: Context): List<GanttWidgetTask> {
        val rawTasks = prefs(context).getString(KEY_TASKS, null) ?: return emptyList()
        val tasks = mutableListOf<GanttWidgetTask>()

        try {
            val array = JSONArray(rawTasks)
            for (index in 0 until array.length()) {
                val taskJson = array.optJSONObject(index) ?: continue
                tasks.add(GanttWidgetTask.fromJson(taskJson))
            }
        } catch (_: Exception) {
            return emptyList()
        }

        return tasks
    }

    fun updatedAt(context: Context): Long? {
        val value = prefs(context).getLong(KEY_UPDATED_AT, 0L)
        return if (value == 0L) null else value
    }

    fun loadSize(context: Context): GanttWidgetSize {
        val prefs = prefs(context)
        return GanttWidgetSize(
            columns = prefs.getInt(KEY_COLUMNS, DEFAULT_COLUMNS).coerceIn(4, 5),
            rows = prefs.getInt(KEY_ROWS, DEFAULT_ROWS).coerceIn(4, 6),
        )
    }

    fun saveSize(context: Context, arguments: Any?): GanttWidgetSize {
        val values = arguments as? Map<*, *>
        val columns = (values?.get("columns") as? Number)
            ?.toInt()
            ?.coerceIn(4, 5)
            ?: DEFAULT_COLUMNS
        val rows = (values?.get("rows") as? Number)
            ?.toInt()
            ?.coerceIn(4, 6)
            ?: DEFAULT_ROWS
        val size = GanttWidgetSize(columns = columns, rows = rows)

        prefs(context).edit()
            .putInt(KEY_COLUMNS, size.columns)
            .putInt(KEY_ROWS, size.rows)
            .apply()

        return size
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}

data class GanttWidgetSize(
    val columns: Int,
    val rows: Int,
) {
    fun toMethodChannelMap(): Map<String, Int> {
        return mapOf("columns" to columns, "rows" to rows)
    }
}

data class GanttWidgetTask(
    val title: String,
    val label: String,
    val startOffset: Int,
    val endOffset: Int,
    val startEpochDay: Long?,
    val endEpochDay: Long?,
    val deadlineEpochDay: Long?,
    val completionPercent: Int,
    val priority: Int,
    val isDone: Boolean,
    val isOverdue: Boolean,
) {
    fun overlaps(todayEpochDay: Long): Boolean {
        val start = startEpochDay
        val end = endEpochDay
        if (start == null || end == null) {
            return true
        }

        return end >= todayEpochDay && start <= todayEpochDay + 6
    }

    fun effectiveStartOffset(todayEpochDay: Long): Int {
        val start = startEpochDay ?: return startOffset.coerceIn(0, 6)
        return (start - todayEpochDay).toInt().coerceIn(0, 6)
    }

    fun effectiveEndOffset(todayEpochDay: Long): Int {
        val end = endEpochDay ?: return endOffset.coerceIn(0, 6)
        return (end - todayEpochDay).toInt().coerceIn(0, 6)
    }

    fun effectiveStartEpochDay(todayEpochDay: Long): Long {
        return startEpochDay ?: todayEpochDay + startOffset
    }

    fun effectiveIsOverdue(todayEpochDay: Long): Boolean {
        val deadline = deadlineEpochDay ?: return isOverdue
        return !isDone && deadline < todayEpochDay
    }

    companion object {
        fun fromJson(json: JSONObject): GanttWidgetTask {
            return GanttWidgetTask(
                title = cleanString(json.optString("title")),
                label = cleanString(json.optString("label")),
                startOffset = json.optInt("startOffset", 0),
                endOffset = json.optInt("endOffset", 0),
                startEpochDay = json.optNullableLong("startEpochDay"),
                endEpochDay = json.optNullableLong("endEpochDay"),
                deadlineEpochDay = json.optNullableLong("deadlineEpochDay"),
                completionPercent = json.optInt("completionPercent", 0),
                priority = json.optInt("priority", 0),
                isDone = json.optBoolean("isDone", false),
                isOverdue = json.optBoolean("isOverdue", false),
            )
        }

        private fun cleanString(value: String): String {
            return if (value == "null") "" else value.trim()
        }
    }
}

private object TaskManGanttWidgetRenderer {
    private val weekdayLabels = arrayOf("月", "火", "水", "木", "金", "土", "日")
    private val timeFormat = SimpleDateFormat("HH:mm", Locale.JAPAN)

    private val surfaceColor = Color.rgb(252, 253, 255)
    private val gridColor = Color.rgb(222, 226, 232)
    private val textColor = Color.rgb(55, 62, 72)
    private val mutedTextColor = Color.rgb(109, 118, 130)
    private val primaryColor = Color.rgb(83, 123, 213)
    private val doneColor = Color.rgb(82, 156, 125)
    private val overdueColor = Color.rgb(214, 75, 86)
    private val priorityColor = Color.rgb(229, 157, 62)
    private val todayColor = Color.rgb(255, 237, 173)
    private val saturdayColor = Color.rgb(39, 109, 236)
    private val sundayColor = Color.rgb(224, 31, 68)

    fun render(
        context: Context,
        appWidgetId: Int,
        isDuplicate: Boolean,
    ): Bitmap {
        val metrics = context.resources.displayMetrics
        val density = metrics.density
        val scaledDensity = metrics.scaledDensity
        val preferredSize = GanttWidgetProvider.sizeForWidget(context, appWidgetId)
            ?: AndroidGanttWidgetStore.loadSize(context)
        val size = widgetSizePx(context, appWidgetId, density, preferredSize)
        val bitmap = Bitmap.createBitmap(size.first, size.second, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val layoutScale = 1f

        val card = RectF(0f, 0f, bitmap.width.toFloat(), bitmap.height.toFloat())
        drawCard(canvas, card, density, layoutScale)

        val padding = dp(10f * layoutScale, density)
        val content = RectF(
            padding,
            padding,
            bitmap.width - padding,
            bitmap.height - padding,
        )

        if (isDuplicate) {
            drawCenteredMessage(
                canvas,
                "小窓ガントは1つだけ表示できます",
                content,
                sp(11f * layoutScale, scaledDensity),
            )
            return bitmap
        }

        val today = LocalDate.now()
        val todayEpochDay = today.toEpochDay()
        val hasCache = AndroidGanttWidgetStore.hasCachedTasks(context)
        val tasks = visibleTasks(
            AndroidGanttWidgetStore.loadTasks(context),
            todayEpochDay,
        )
        val headerBottom = drawHeader(
            canvas = canvas,
            content = content,
            today = today,
            updatedAt = AndroidGanttWidgetStore.updatedAt(context),
            density = density,
            scaledDensity = scaledDensity,
            layoutScale = layoutScale,
        )

        if (!hasCache) {
            drawCenteredMessage(
                canvas,
                "アプリを開くと予定を表示します",
                RectF(content.left, headerBottom, content.right, content.bottom),
                sp(11f * layoutScale, scaledDensity),
            )
            return bitmap
        }

        drawGantt(
            canvas = canvas,
            content = RectF(content.left, headerBottom, content.right, content.bottom),
            tasks = tasks,
            today = today,
            todayEpochDay = todayEpochDay,
            preferredSize = preferredSize,
            density = density,
            scaledDensity = scaledDensity,
            layoutScale = layoutScale,
        )

        return bitmap
    }

    private fun visibleTasks(
        tasks: List<GanttWidgetTask>,
        todayEpochDay: Long,
    ): List<GanttWidgetTask> {
        return tasks
            .filter { it.overlaps(todayEpochDay) }
            .sortedWith(
                compareBy<GanttWidgetTask> { it.isDone }
                    .thenBy { it.effectiveStartEpochDay(todayEpochDay) }
                    .thenByDescending { it.priority },
            )
    }

    private fun drawCard(canvas: Canvas, card: RectF, density: Float, layoutScale: Float) {
        val radius = dp(18f * layoutScale, density)
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = surfaceColor
            style = Paint.Style.FILL
        }
        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(225, 229, 236)
            style = Paint.Style.STROKE
            strokeWidth = dp(1f, density)
        }

        canvas.drawRoundRect(card, radius, radius, fill)
        val inset = dp(0.5f, density)
        card.inset(inset, inset)
        canvas.drawRoundRect(card, radius, radius, stroke)
    }

    private fun drawHeader(
        canvas: Canvas,
        content: RectF,
        today: LocalDate,
        updatedAt: Long?,
        density: Float,
        scaledDensity: Float,
        layoutScale: Float,
    ): Float {
        val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = textColor
            textSize = sp(13f * layoutScale, scaledDensity)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val metaPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = mutedTextColor
            textSize = sp(8.8f * layoutScale, scaledDensity)
            textAlign = Paint.Align.RIGHT
        }
        val accentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = primaryColor
            style = Paint.Style.FILL
        }

        val top = content.top
        val headerHeight = dp(28f * layoutScale, density)
        val baseline = top + dp(17f * layoutScale, density)
        val accentWidth = dp(4f * layoutScale, density)
        canvas.drawRoundRect(
            RectF(
                content.left,
                top + dp(4f * layoutScale, density),
                content.left + accentWidth,
                top + dp(20f * layoutScale, density),
            ),
            dp(2f * layoutScale, density),
            dp(2f * layoutScale, density),
            accentPaint,
        )
        canvas.drawText("予定", content.left + dp(10f * layoutScale, density), baseline, titlePaint)

        val rangeEnd = today.plusDays(6)
        val rangeText = "${today.monthValue}/${today.dayOfMonth} - ${rangeEnd.monthValue}/${rangeEnd.dayOfMonth}"
        val syncText = updatedAt?.let { "更新 ${timeFormat.format(Date(it))}" }
        var metaText = listOfNotNull(rangeText, syncText).joinToString("  ")
        val reservedTitleWidth = titlePaint.measureText("予定") + dp(24f * layoutScale, density)
        if (reservedTitleWidth + metaPaint.measureText(metaText) > content.width()) {
            metaText = rangeText
        }
        canvas.drawText(metaText, content.right, baseline, metaPaint)

        return top + headerHeight
    }

    private fun drawGantt(
        canvas: Canvas,
        content: RectF,
        tasks: List<GanttWidgetTask>,
        today: LocalDate,
        todayEpochDay: Long,
        preferredSize: GanttWidgetSize,
        density: Float,
        scaledDensity: Float,
        layoutScale: Float,
    ) {
        val labelWidth = min(
            dp(86f * layoutScale, density),
            content.width() * if (preferredSize.columns <= 3) 0.24f else 0.28f,
        )
        val gridGap = dp(6f * layoutScale, density)
        val gridLeft = content.left + labelWidth + gridGap
        val gridRight = content.right
        val dayHeaderHeight = dp(20f * layoutScale, density)
        val gridTop = content.top + dayHeaderHeight
        val rowAreaHeight = max(dp(28f * layoutScale, density), content.bottom - gridTop)
        val maxRowsByHeight = max(
            1,
            floor(rowAreaHeight / dp(26f * layoutScale, density)).toInt(),
        )
        val maxRowsByPreference = when {
            preferredSize.rows <= 3 -> 2
            preferredSize.rows == 4 -> 3
            preferredSize.rows == 5 -> 5
            else -> 6
        }
        val rowCount = min(
            min(maxRowsByHeight, maxRowsByPreference),
            max(1, tasks.size),
        )
        val visibleTasks = tasks.take(rowCount)
        val maxRowHeight = dp((if (preferredSize.rows >= 5) 34f else 31f) * layoutScale, density)
        val rowHeight = min(maxRowHeight, rowAreaHeight / rowCount)
        val gridBottom = gridTop + rowHeight * rowCount
        val cellWidth = (gridRight - gridLeft) / 7f

        drawDayHeader(
            canvas = canvas,
            today = today,
            gridLeft = gridLeft,
            top = content.top,
            cellWidth = cellWidth,
            density = density,
            scaledDensity = scaledDensity,
            layoutScale = layoutScale,
        )

        if (visibleTasks.isEmpty()) {
            drawCenteredMessage(
                canvas,
                "7日以内のタスクはありません",
                RectF(content.left, gridTop, content.right, content.bottom),
                sp(11f * layoutScale, scaledDensity),
            )
            return
        }

        drawGrid(
            canvas = canvas,
            gridLeft = gridLeft,
            gridRight = gridRight,
            gridTop = gridTop,
            gridBottom = gridBottom,
            rowCount = rowCount,
            rowHeight = rowHeight,
            density = density,
        )

        val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = textColor
            textSize = sp(10f * layoutScale, scaledDensity)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val barTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = sp(8.8f * layoutScale, scaledDensity)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }

        visibleTasks.forEachIndexed { index, task ->
            val top = gridTop + index * rowHeight
            val rowRect = RectF(content.left, top, content.right, top + rowHeight)
            val title = if (task.title.isEmpty()) "無題のタスク" else task.title
            drawTextCenteredVertically(
                canvas = canvas,
                text = ellipsize(title, labelPaint, labelWidth),
                x = content.left,
                rect = rowRect,
                paint = labelPaint,
            )

            val startOffset = task.effectiveStartOffset(todayEpochDay)
            val endOffset = max(startOffset, task.effectiveEndOffset(todayEpochDay))
            val barLeft = gridLeft + startOffset * cellWidth + dp(2f * layoutScale, density)
            val barRight = gridLeft + (endOffset + 1) * cellWidth - dp(2f * layoutScale, density)
            val barTop = top + dp(4f * layoutScale, density)
            val barBottom = top + rowHeight - dp(4f * layoutScale, density)
            val barPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = taskColor(task, todayEpochDay)
                style = Paint.Style.FILL
            }
            val barRect = RectF(
                barLeft,
                barTop,
                max(barLeft + dp(8f * layoutScale, density), barRight),
                barBottom,
            )
            val barRadius = barRect.height() / 2f
            canvas.drawRoundRect(barRect, barRadius, barRadius, barPaint)

            val barLabel = task.label.ifEmpty { "${task.completionPercent}%" }
            drawTextCenteredVertically(
                canvas = canvas,
                text = ellipsize(
                    barLabel,
                    barTextPaint,
                    barRect.width() - dp(10f * layoutScale, density),
                ),
                x = barRect.left + dp(5f * layoutScale, density),
                rect = barRect,
                paint = barTextPaint,
            )
        }

        drawRemainingTaskCount(
            canvas = canvas,
            hiddenCount = tasks.size - visibleTasks.size,
            content = content,
            top = gridBottom + dp(10f * layoutScale, density),
            scaledDensity = scaledDensity,
            layoutScale = layoutScale,
        )
    }

    private fun drawRemainingTaskCount(
        canvas: Canvas,
        hiddenCount: Int,
        content: RectF,
        top: Float,
        scaledDensity: Float,
        layoutScale: Float,
    ) {
        if (hiddenCount <= 0 || top >= content.bottom) {
            return
        }

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = mutedTextColor
            textSize = sp(9.5f * layoutScale, scaledDensity)
            textAlign = Paint.Align.RIGHT
        }
        canvas.drawText("ほか${hiddenCount}件", content.right, top - paint.fontMetrics.ascent, paint)
    }

    private fun drawDayHeader(
        canvas: Canvas,
        today: LocalDate,
        gridLeft: Float,
        top: Float,
        cellWidth: Float,
        density: Float,
        scaledDensity: Float,
        layoutScale: Float,
    ) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = mutedTextColor
            textSize = sp(8.7f * layoutScale, scaledDensity)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
        }

        for (index in 0 until 7) {
            val date = today.plusDays(index.toLong())
            paint.color = when (date.dayOfWeek.value) {
                6 -> saturdayColor
                7 -> sundayColor
                else -> mutedTextColor
            }
            val label = "${date.dayOfMonth}${weekdayLabels[date.dayOfWeek.value - 1]}"
            canvas.drawText(
                label,
                gridLeft + cellWidth * index + cellWidth / 2f,
                top + dp(15f * layoutScale, density),
                paint,
            )
        }
    }

    private fun drawGrid(
        canvas: Canvas,
        gridLeft: Float,
        gridRight: Float,
        gridTop: Float,
        gridBottom: Float,
        rowCount: Int,
        rowHeight: Float,
        density: Float,
    ) {
        val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = gridColor
            strokeWidth = dp(1f, density)
        }
        val todayPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = todayColor
            style = Paint.Style.FILL
        }
        val cellWidth = (gridRight - gridLeft) / 7f

        canvas.drawRect(
            gridLeft,
            gridTop,
            gridLeft + cellWidth,
            gridBottom,
            todayPaint,
        )

        for (index in 0..7) {
            val x = gridLeft + index * cellWidth
            canvas.drawLine(x, gridTop, x, gridBottom, linePaint)
        }

        for (index in 0..rowCount) {
            val y = gridTop + index * rowHeight
            canvas.drawLine(gridLeft, y, gridRight, y, linePaint)
        }
    }

    private fun drawCenteredMessage(
        canvas: Canvas,
        message: String,
        rect: RectF,
        textSize: Float,
    ) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = mutedTextColor
            this.textSize = textSize
            textAlign = Paint.Align.CENTER
        }
        val baseline = rect.centerY() - (paint.fontMetrics.ascent + paint.fontMetrics.descent) / 2f
        canvas.drawText(message, rect.centerX(), baseline, paint)
    }

    private fun drawTextCenteredVertically(
        canvas: Canvas,
        text: String,
        x: Float,
        rect: RectF,
        paint: Paint,
    ) {
        val baseline = rect.centerY() - (paint.fontMetrics.ascent + paint.fontMetrics.descent) / 2f
        canvas.drawText(text, x, baseline, paint)
    }

    private fun taskColor(task: GanttWidgetTask, todayEpochDay: Long): Int {
        return when {
            task.isDone -> doneColor
            task.effectiveIsOverdue(todayEpochDay) -> overdueColor
            task.priority >= 4 -> priorityColor
            else -> primaryColor
        }
    }

    private fun widgetSizePx(
        context: Context,
        appWidgetId: Int,
        density: Float,
        preferredSize: GanttWidgetSize,
    ): Pair<Int, Int> {
        val options = AppWidgetManager.getInstance(context).getAppWidgetOptions(appWidgetId)
        val fallbackWidthDp = cellSpanDp(preferredSize.columns)
        val fallbackHeightDp = cellSpanDp(preferredSize.rows)
        val widthDp = max(
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0),
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0),
        ).takeIf { it > 0 } ?: fallbackWidthDp
        val heightDp = max(
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0),
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0),
        ).takeIf { it > 0 } ?: fallbackHeightDp

        val width = dp(widthDp.toFloat(), density).roundToInt().coerceIn(220, 760)
        val height = dp(heightDp.toFloat(), density).roundToInt().coerceIn(160, 560)
        return width to height
    }

    private fun cellSpanDp(cells: Int): Int {
        return cells * 70 - 30
    }

    private fun ellipsize(text: String, paint: Paint, maxWidth: Float): String {
        if (paint.measureText(text) <= maxWidth) {
            return text
        }

        val ellipsis = "..."
        var end = text.length
        while (end > 0 && paint.measureText(text.substring(0, end) + ellipsis) > maxWidth) {
            end -= 1
        }

        return if (end <= 0) ellipsis else text.substring(0, end) + ellipsis
    }

    private fun dp(value: Float, density: Float): Float = value * density

    private fun sp(value: Float, scaledDensity: Float): Float = value * scaledDensity
}

private fun JSONObject.optNullableLong(name: String): Long? {
    if (!has(name) || isNull(name)) {
        return null
    }

    return optLong(name)
}
