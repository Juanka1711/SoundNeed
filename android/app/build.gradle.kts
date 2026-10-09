plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.music_player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.music_player"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24  // Android 7.0 (API 24)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // NOTE: The Flutter Gradle Plugin force-enables R8 minification for the
            // "release" build type, so disabling it here has no effect. R8 overrides
            // needed for NewPipe Extractor (via org.mozilla.javascript / Rhino, which
            // references desktop-JDK-only classes like java.beans, javax.script and
            // jdk.dynalink that do not exist on Android) are provided in
            // "proguard-rules.pro" in this directory.
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("com.google.android.gms:play-services-cast-framework:22.3.1")
    implementation("com.github.TeamNewPipe:NewPipeExtractor:v0.26.5")
    implementation("io.github.amanrajaryan:TagLib:1.0.0")
    // NewPipe Extractor requires java.nio desugaring when minSdk < 33.
    // desugar_jdk_libs_nio includes the base desugar set PLUS package java.nio
    // (the plain "desugar_jdk_libs" does NOT cover java.nio). Without it, NewPipe
    // throws in runtime on devices with SDK lower than 33 (e.g. Android 10) when
    // extracting an online stream (NewPipeExtractor prerequisite,
    // see the project Installation docs).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs_nio:2.1.5")
}

flutter {
    source = "../.."
}
