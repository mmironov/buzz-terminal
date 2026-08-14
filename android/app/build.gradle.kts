// No `org.jetbrains.kotlin.android` here: from AGP 9 the Android plugin brings
// Kotlin with it, and applying the standalone plugin as well is now an error.
// `:domain` still applies `kotlin.jvm`, because it is not an Android module.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    // Applied conditionally below, not here — see the comment there.
    alias(libs.plugins.google.services) apply false
}

// `google-services.json` is gitignored (it identifies the project and pins its
// API keys), so a fresh clone does not have one — and this plugin fails the
// build outright when the file is missing. Unconditional application would mean
// nobody can build the app until they have been through docs/firebase-setup.md,
// including to run the design gallery or the tests.
//
// Applying it only when the file is there mirrors what the iOS side gets for
// free: with no credentials the app still builds and runs, on fixtures. A
// release build is not allowed that latitude — FirebaseBootstrap refuses to
// start one that has no configuration.
val firebaseConfig = file("google-services.json")
if (firebaseConfig.exists()) {
    apply(plugin = libs.plugins.google.services.get().pluginId)
} else {
    logger.warn(
        "google-services.json not found — building on fixtures. See docs/firebase-setup.md step 6."
    )
}

android {
    namespace = "fest.swingbuzz.terminal"
    compileSdk = 37

    defaultConfig {
        applicationId = "fest.swingbuzz.terminal"

        // java.time (Participant.checkedInAt, Evening.today) is API 26, and so is
        // the variable-font support Archivo needs. Android 8 is old enough that
        // anything a staff member is likely to be carrying will run this.
        minSdk = 26
        targetSdk = 37

        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    buildFeatures {
        compose = true
        // Explicit because AGP no longer generates BuildConfig by default.
        // `BuildConfig.DEBUG` is what decides whether the fixtures are reachable
        // at all — see FirebaseBootstrap.
        buildConfig = true
    }
}

kotlin {
    jvmToolchain(libs.versions.jvmTarget.get().toInt())
}

dependencies {
    implementation(project(":domain"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)

    // The BoM pins every Firebase artifact's version, so the two below carry none.
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.auth)
    implementation(libs.firebase.firestore)
    implementation(libs.kotlinx.coroutines.play.services)

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)
}
