plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.career_roadmap"

    // Use Flutter’s compile SDK (or set a number like 34)
    compileSdk = flutter.compileSdkVersion

    // 🔧 Fix: match plugins that require NDK 27
    // If you prefer using flutter.ndkVersion from gradle.properties, you can
    // remove this line and set it there instead (see below).
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.career_roadmap"

        // 🔧 Fix: raise minSdk for screen_capture_event
        // You can hardcode 23 or keep using Flutter vars via gradle.properties.
        minSdk = 23

        // Keep using Flutter values for the rest (or hardcode if you want)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Sign how you like; leaving debug key for now so --release runs.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
