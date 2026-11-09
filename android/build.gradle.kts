group = "design.codeux.flutter_store_listing"
version = "1.0-SNAPSHOT"

buildscript {
    // Kept in step with what Flutter's own first-party plugins ship, so that a
    // consumer's build does not end up resolving two different Android Gradle
    // plugin or Kotlin versions. Compare `url_launcher_android`, which this
    // package already depends on.
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:8.13.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

android {
    namespace = "design.codeux.flutter_store_listing"

    // Follows the Flutter SDK's own value rather than pinning one here, so a
    // consumer on a newer Flutter does not have to wait for this package. Note
    // this tracks the SDK, not the consuming app.
    compileSdk = flutter.compileSdkVersion

    defaultConfig {
        // Flutter's own floor as of 3.44, and the same value url_launcher_android
        // declares — so any app already pulling url_launcher is at 24 anyway.
        // It is a manifest-merger floor for consumers, hence the CHANGELOG note.
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        checkAllWarnings = true
        warningsAsErrors = true
        // `QueryPermissionsNeeded` is deliberately not disabled: this module
        // never queries for a handler, it attempts the intent and handles
        // ActivityNotFoundException, which is what Android documents and what
        // needs no `<queries>` entry in a consumer's manifest.
        // `UseKtx` is suppressed at its one call site rather than here, so the
        // check stays live for code added later.
        disable.addAll(setOf("AndroidGradlePluginVersion", "GradleDependency", "NewerVersionAvailable"))
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            isReturnDefaultValues = true
        }
    }
}

dependencies {
    // No `implementation` dependencies at all: no androidx, and in particular
    // no Play Core. Opening a store listing is one intent, and Play's in-app
    // review API is deliberately kept out of this package so it stays free of
    // proprietary dependencies — see the note in pubspec.yaml. The test
    // dependencies below are resolved only when these tests are run.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.mockito:mockito-core:5.23.0")
    testImplementation("org.robolectric:robolectric:4.16")
}
