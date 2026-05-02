package de.on100.help_to_learn_app

import android.app.*
import android.content.*
import android.os.Build
import android.os.IBinder
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodChannel

class AudioForegroundService : Service() {

    companion object {
        const val TAG = "AudioFgService"
        const val NOTIFICATION_ID = 1124
        const val CHANNEL_ID = "de.100on.study.audio"
        const val CHANNEL_NAME = "Study Audio"

        // PendingIntent request codes
        private const val REQ_PLAY_PAUSE = 0
        private const val REQ_PREV_SEGMENT = 1
        private const val REQ_NEXT_SEGMENT = 2
        private const val REQ_PREV_MATERIAL = 3
        private const val REQ_NEXT_MATERIAL = 4
        private const val REQ_PLAY_MODE = 5
        private const val REQ_CONTENT = 100

        // Intent action strings
        const val ACTION_PLAY_PAUSE = "com.help_to_learn.action.PLAY_PAUSE"
        const val ACTION_PREV_SEGMENT = "com.help_to_learn.action.PREV_SEGMENT"
        const val ACTION_NEXT_SEGMENT = "com.help_to_learn.action.NEXT_SEGMENT"
        const val ACTION_PREV_MATERIAL = "com.help_to_learn.action.PREV_MATERIAL"
        const val ACTION_NEXT_MATERIAL = "com.help_to_learn.action.NEXT_MATERIAL"
        const val ACTION_PLAY_MODE = "com.help_to_learn.action.PLAY_MODE"

        var channel: MethodChannel? = null
        var instance: AudioForegroundService? = null
    }

    init {
        instance = this
    }

    private lateinit var mediaSession: MediaSessionCompat
    private lateinit var remoteViews: RemoteViews
    private var isPlaying = false
    private var hasPrevMaterial = false
    private var hasNextMaterial = false
    private var hasPrevSegment = false
    private var hasNextSegment = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        setupMediaSession()
        remoteViews = RemoteViews(packageName, R.layout.notification_audio_controls)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        handleIntentAction(intent)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        mediaSession.isActive = false
        mediaSession.release()
        instance = null
        super.onDestroy()
    }

    // ─── Notification Channel ────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Audio playback controls"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    // ─── MediaSession ────────────────────────────────────────────────────────

    private fun setupMediaSession() {
        val cb = object : MediaSessionCompat.Callback() {
            override fun onPlay() {
                channel?.invokeMethod("onMediaButton", "play")
            }
            override fun onPause() {
                channel?.invokeMethod("onMediaButton", "pause")
            }
            override fun onSkipToNext() {
                channel?.invokeMethod("onMediaButton", "next")
            }
            override fun onSkipToPrevious() {
                channel?.invokeMethod("onMediaButton", "prev")
            }
            override fun onSeekTo(pos: Long) {
                channel?.invokeMethod("onSeekTo", mapOf("positionMs" to pos))
            }
            override fun onStop() {
                channel?.invokeMethod("onNotificationDeleted", emptyMap<String, Any>())
            }
        }

        mediaSession = MediaSessionCompat(this, "HelpToLearnAudio", null, null).apply {
            setCallback(cb)
            setPlaybackState(
                PlaybackStateCompat.Builder()
                    .setActions(
                        PlaybackStateCompat.ACTION_PLAY or
                        PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                        PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackStateCompat.ACTION_SEEK_TO or
                        PlaybackStateCompat.ACTION_STOP
                    )
                    .build()
            )
            isActive = true
        }
    }

    // ─── Intent Action Handling ──────────────────────────────────────────────

    private fun handleIntentAction(intent: Intent?) {
        when (intent?.action) {
            ACTION_PLAY_PAUSE -> channel?.invokeMethod("onButtonPress", "play_pause")
            ACTION_PREV_SEGMENT -> channel?.invokeMethod("onButtonPress", "prev_segment")
            ACTION_NEXT_SEGMENT -> channel?.invokeMethod("onButtonPress", "next_segment")
            ACTION_PREV_MATERIAL -> channel?.invokeMethod("onButtonPress", "prev_material")
            ACTION_NEXT_MATERIAL -> channel?.invokeMethod("onButtonPress", "next_material")
            ACTION_PLAY_MODE -> channel?.invokeMethod("onButtonPress", "play_mode")
        }
    }

    // ─── Notification Update (called from Flutter via MethodChannel) ──────────

    fun updateNotification(args: Map<*, *>) {
        val title = args["title"] as? String ?: "Help To Learn"
        val subtitle = args["subtitle"] as? String ?: ""
        val playing = args["playing"] as? Boolean ?: false
        hasPrevMaterial = args["hasPrevMaterial"] as? Boolean ?: false
        hasNextMaterial = args["hasNextMaterial"] as? Boolean ?: false
        hasPrevSegment = args["hasPrevSegment"] as? Boolean ?: false
        hasNextSegment = args["hasNextSegment"] as? Boolean ?: false
        val playlistInfo = args["playlistInfo"] as? String ?: ""
        val modeLabel = args["modeLabel"] as? String ?: ""

        isPlaying = playing

        // Title / subtitle
        remoteViews.setTextViewText(R.id.notifTitle, title)
        remoteViews.setTextViewText(R.id.notifSubtitle, subtitle)

        // Playlist info
        val playlistText = if (modeLabel.isNotEmpty()) {
            if (playlistInfo.isNotEmpty()) "$playlistInfo · $modeLabel" else modeLabel
        } else {
            playlistInfo
        }
        remoteViews.setTextViewText(R.id.notifPlaylistInfo, playlistText)

        // Play/Pause icon
        remoteViews.setImageViewResource(
            R.id.btnPlayPause,
            if (playing) R.drawable.ic_pause else R.drawable.ic_play_arrow
        )

        // Enable/disable + alpha for each nav button
        applyButtonState(R.id.btnPrevMaterial, hasPrevMaterial, 255)
        applyButtonState(R.id.btnNextMaterial, hasNextMaterial, 255)
        applyButtonState(R.id.btnPrevSegment, hasPrevSegment, 179)
        applyButtonState(R.id.btnNextSegment, hasNextSegment, 179)

        // Build and post notification
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
    }

    private fun applyButtonState(viewId: Int, enabled: Boolean, activeAlpha: Int) {
        remoteViews.setInt(viewId, "setAlpha", if (enabled) activeAlpha else 77)
    }

    private fun buildNotification(): Notification {
        // Set click intents for each button
        setButtonPendingIntent(R.id.btnPlayPause, ACTION_PLAY_PAUSE, REQ_PLAY_PAUSE)
        setButtonPendingIntent(R.id.btnPrevSegment, ACTION_PREV_SEGMENT, REQ_PREV_SEGMENT)
        setButtonPendingIntent(R.id.btnNextSegment, ACTION_NEXT_SEGMENT, REQ_NEXT_SEGMENT)
        setButtonPendingIntent(R.id.btnPrevMaterial, ACTION_PREV_MATERIAL, REQ_PREV_MATERIAL)
        setButtonPendingIntent(R.id.btnNextMaterial, ACTION_NEXT_MATERIAL, REQ_NEXT_MATERIAL)
        setButtonPendingIntent(R.id.btnPlayMode, ACTION_PLAY_MODE, REQ_PLAY_MODE)

        // Content intent (open app on tap)
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentPending = PendingIntent.getActivity(
            this, REQ_CONTENT, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag()
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(remoteViews)
            .setCustomBigContentView(remoteViews)
            .setContentIntent(contentPending)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    private fun setButtonPendingIntent(viewId: Int, action: String, requestCode: Int) {
        val intent = Intent(this, AudioForegroundService::class.java).apply {
            this.action = action
        }
        val pending = PendingIntent.getService(
            this, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag()
        )
        remoteViews.setOnClickPendingIntent(viewId, pending)
    }

    // ─── Service Control ─────────────────────────────────────────────────────

    fun stopServiceAndNotification() {
        Log.i(TAG, "stopServiceAndNotification")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    // ─── Compatibility ───────────────────────────────────────────────────────

    private fun pendingIntentImmutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else 0
}
