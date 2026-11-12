plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is provided by CI or a local, untracked keystore. An unsigned
// release is preferable to silently distributing an APK signed with the debug key.
val releaseKeystorePath = System.getenv("MOVERA_RELEASE_KEYSTORE_PATH")
val releaseStorePassword = System.getenv("MOVERA_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = System.getenv("MOVERA_RELEASE_KEY_ALIAS")
val releaseKeyPassword = System.getenv("MOVERA_RELEASE_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseKeystorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

// Maps key: Gradle property or environment variable. Debug builds keep the
// placeholder so local work runs without one (the map tiles stay grey), but a
// release must never ship it: Google Maps would show a blank grey map.
val providedMapsApiKey = ((project.findProperty("MAPS_API_KEY") as String?)
    ?: System.getenv("MAPS_API_KEY"))
    ?.trim()
val hasMapsApiKey = !providedMapsApiKey.isNullOrBlank()
val mapsApiKey = if (hasMapsApiKey) providedMapsApiKey!! else "MISSING_MAPS_API_KEY"

gradle.taskGraph.whenReady {
    val packagesRelease = allTasks.any { task ->
        task.project.path == ":app" &&
            (task.name.matches(Regex("(?i)(assemble|bundle|package).*release.*")))
    }
    if (packagesRelease && !hasReleaseSigning) {
        throw GradleException("Release signing requires all four MOVERA_RELEASE_* environment variables")
    }
    if (packagesRelease && !hasMapsApiKey) {
        throw GradleException(
            "Release builds require a Google Maps key: set MAPS_API_KEY as a Gradle property " +
                "(-PMAPS_API_KEY=...) or environment variable. Without it the map ships blank.",
        )
    }
}

android {
    namespace = "com.movera.rider"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.movera.rider"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
        // G31 rider (owner 2026-11-12): the Firebase Test Lab device suite
        // (android/app/src/androidTest + integration_test/). Only the
        // androidTest APK uses it; the app APK does not change.
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("moveraRelease") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                check(storeFile?.isFile == true) { "Release keystore does not exist" }
                check(storeFile?.canonicalFile != file("${System.getProperty("user.home")}/.android/debug.keystore").canonicalFile) {
                    "A debug keystore cannot sign a release"
                }
                check(!keyAlias.equals("androiddebugkey", ignoreCase = true)) {
                    "The Android debug key cannot sign a release"
                }
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("moveraRelease")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // G31 rider: the instrumentation runner of the device suite (test APK only).
    androidTestImplementation("androidx.test:runner:1.2.0")
    androidTestImplementation("androidx.test:rules:1.2.0")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.3.0")
}
