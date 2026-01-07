# ProGuard rules for release builds
# Prevents code stripping that breaks background services, timers, and location tracking

# Keep all service classes
-keep class com.example.demoapp.ForegroundAttendanceService { *; }
-keep class com.example.demoapp.LocationService { *; }
-keep class com.example.demoapp.BootReceiver { *; }
-keep class com.example.demoapp.PermissionHelper { *; }

# Keep all database classes
-keep class com.example.demoapp.database.** { *; }
-keep interface com.example.demoapp.database.** { *; }

# Keep all worker classes
-keep class com.example.demoapp.workers.** { *; }

# Keep Kotlin coroutines
-keep class kotlinx.coroutines.** { *; }
-keepclassmembers class kotlinx.coroutines.** { *; }

# Keep OkHttp
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**

# Keep Room database
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *
-dontwarn androidx.room.paging.**

# Keep WorkManager
-keep class androidx.work.** { *; }
-keep interface androidx.work.** { *; }
-dontwarn androidx.work.**

# Keep location-related classes
-keep class android.location.** { *; }
-keep class com.google.android.gms.location.** { *; }

# Keep all native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep Serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep R class
-keepclassmembers class **.R$* {
    public static <fields>;
}

# Keep annotation default values
-keepattributes AnnotationDefault

# Keep line numbers for better stack traces
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Don't warn about missing classes (some may be optional)
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# Keep generic signatures
-keepattributes Signature

# Keep exceptions
-keepattributes Exceptions

# Keep inner classes
-keepattributes InnerClasses

# Keep enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Prevent obfuscation of classes used in reflection
-keepnames class com.example.demoapp.** { *; }

# Keep Handler and Runnable classes (for timers)
-keep class android.os.Handler { *; }
-keep class android.os.Handler$* { *; }
-keep interface java.lang.Runnable { *; }

# Keep BroadcastReceiver
-keep class * extends android.content.BroadcastReceiver { *; }

# Keep Service classes
-keep class * extends android.app.Service { *; }

# Keep Application class
-keep class * extends android.app.Application { *; }

# Keep Activity classes
-keep class * extends android.app.Activity { *; }
-keep class * extends androidx.appcompat.app.AppCompatActivity { *; }
-keep class * extends io.flutter.embedding.android.FlutterActivity { *; }

# Keep Flutter engine classes
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Keep JSON classes
-keep class org.json.** { *; }

# Keep SharedPreferences keys (prevent obfuscation)
-keepclassmembers class * {
    @androidx.annotation.Keep <fields>;
}

# Preserve native method names
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Keep Kotlin metadata
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations
-keepclassmembers class **$WhenMappings {
    <fields>;
}
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}

# Keep all Flutter/Dart classes - CRITICAL for release behavior
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# Keep all Dart classes
-keep class * extends io.flutter.plugin.common.PluginRegistry { *; }
-keep class * implements io.flutter.plugin.common.PluginRegistry$PluginRegistrantCallback { *; }

# Keep all debug logging classes
-keep class android.util.Log { *; }
-keepclassmembers class * {
    public static *** d(...);
    public static *** e(...);
    public static *** w(...);
    public static *** i(...);
    public static *** v(...);
}

# Keep all reflection-accessed classes
-keepclassmembers class * {
    @androidx.annotation.Keep <methods>;
    @androidx.annotation.Keep <fields>;
}

# Keep all classes in the app package
-keep class com.example.demoapp.** { *; }
-keepclassmembers class com.example.demoapp.** { *; }

# Keep all native method implementations
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep all callback interfaces
-keep interface * {
    <methods>;
}

# Prevent obfuscation of method names used in reflection
-keepnames class * {
    public <methods>;
}

# Keep all annotation classes
-keep class * extends java.lang.annotation.Annotation { *; }

# Keep all enum classes
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep all exception classes
-keep class * extends java.lang.Exception { *; }
-keep class * extends java.lang.Throwable { *; }

# Keep all serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep all Parcelable implementations
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep all View classes
-keep class * extends android.view.View { *; }
-keep class * extends android.view.ViewGroup { *; }

# Keep all Fragment classes
-keep class * extends androidx.fragment.app.Fragment { *; }

# Keep all lifecycle-aware components
-keep class * implements androidx.lifecycle.LifecycleObserver { *; }
-keep class * extends androidx.lifecycle.ViewModel { *; }

# Keep all coroutine-related classes
-keep class kotlinx.coroutines.** { *; }
-keepclassmembers class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# Keep all WorkManager classes
-keep class androidx.work.** { *; }
-keep interface androidx.work.** { *; }
-dontwarn androidx.work.**

# Keep all Room database classes
-keep class * extends androidx.room.RoomDatabase { *; }
-keep @androidx.room.Entity class * { *; }
-keep @androidx.room.Dao class * { *; }
-dontwarn androidx.room.**

# Keep all SharedPreferences keys
-keepclassmembers class * {
    static final java.lang.String *;
}

# Keep all BuildConfig fields
-keepclassmembers class * {
    public static final boolean DEBUG;
    public static final java.lang.String APPLICATION_ID;
    public static final java.lang.String BUILD_TYPE;
    public static final java.lang.String FLAVOR;
    public static final int VERSION_CODE;
    public static final java.lang.String VERSION_NAME;
}

# Don't optimize - match debug behavior
-dontoptimize
-dontobfuscate
-dontpreverify

