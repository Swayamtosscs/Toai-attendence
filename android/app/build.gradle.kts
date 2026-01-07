import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.devtools.ksp")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.demoapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
    
    // Configure KSP (replaces kapt)
    ksp {
        arg("room.schemaLocation", "$projectDir/schemas")
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.demoapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystorePropertiesFile = rootProject.file("../key.properties")
            if (keystorePropertiesFile.exists()) {
                val keystoreProperties = Properties()
                keystoreProperties.load(FileInputStream(keystorePropertiesFile))
                val storeFileProp = keystoreProperties["storeFile"] as String?
                if (storeFileProp != null) {
                    storeFile = file(storeFileProp.replace("../", ""))
                    storePassword = keystoreProperties["storePassword"] as String
                    keyAlias = keystoreProperties["keyAlias"] as String
                    keyPassword = keystoreProperties["keyPassword"] as String
                }
            }
        }
    }

    buildTypes {
        release {
            // Use release signing if key.properties exists, otherwise use debug
            val keystorePropertiesFile = rootProject.file("../key.properties")
            if (keystorePropertiesFile.exists()) {
                val keystoreProperties = Properties()
                keystoreProperties.load(FileInputStream(keystorePropertiesFile))
                val storeFileProp = keystoreProperties["storeFile"] as String?
                if (storeFileProp != null) {
                    signingConfig = signingConfigs.getByName("release")
                } else {
                    signingConfig = signingConfigs.getByName("debug")
                }
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
            
            // Disable minification to match debug behavior exactly
            // ProGuard rules are kept for safety but minification disabled
            isMinifyEnabled = false
            isShrinkResources = false
            
            // Ensure release behaves like debug
            isDebuggable = false
            
            // Keep debug symbols for better crash reports
            ndk {
                debugSymbolLevel = "FULL"
            }
        }
        debug {
            // Disable minification in debug for faster builds
            isMinifyEnabled = false
            isDebuggable = true
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    
    // Room database for offline storage
    val roomVersion = "2.6.1"
    implementation("androidx.room:room-runtime:$roomVersion")
    implementation("androidx.room:room-ktx:$roomVersion")
    ksp("androidx.room:room-compiler:$roomVersion")
    
    // WorkManager for background sync
    val workVersion = "2.9.0"
    implementation("androidx.work:work-runtime-ktx:$workVersion")
    
    // Kotlin coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
}

// Configure all Kotlin tasks to use JVM 17
afterEvaluate {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        kotlinOptions {
            jvmTarget = "17"
        }
    }
}
