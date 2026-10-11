plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hairsaloon.salon_customer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        resValues = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.hairsaloon.salon_customer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue("string", "app_name", "salon_customer")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Branded single-salon apps (see ../../lib/core/brand/brand_config.dart)
    // are additional flavors of this same codebase, not separate Flutter
    // projects — each gets its own applicationId + app_name so it installs
    // independently alongside the default (main) app, while sharing 100% of
    // the Dart/booking/auth code. `main` reproduces today's app unchanged;
    // adding a future branded salon app is one more flavor block here plus
    // one more BrandConfig entry, never a change to `main`'s.
    flavorDimensions += "brand"
    productFlavors {
        // Named "standard", not "main" — Gradle/AGP reserves "main" for the
        // implicit default source set, and a flavor of the same name
        // collides with it.
        create("standard") {
            dimension = "brand"
            // applicationId/app_name inherited from defaultConfig above —
            // this flavor is byte-for-byte today's app.
        }
        create("nilHairPort") {
            dimension = "brand"
            applicationId = "com.hairsaloon.salon_customer.nilhairport"
            resValue("string", "app_name", "Nil Hair Port Unisex")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
