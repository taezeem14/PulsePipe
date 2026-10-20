# Sine ProGuard / R8 Rules for ExoPlayer & AudioService

# Keep AudioService and MediaSession
-keep class com.ryanheise.audioservice.** { *; }
-keep interface com.ryanheise.audioservice.** { *; }

# Keep JustAudio and ExoPlayer decoders
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.google.android.exoplayer2.** { *; }
-keep class androidx.media3.** { *; }

# Keep MediaCompat classes
-keep class android.support.v4.media.** { *; }
-keep class androidx.media.** { *; }
