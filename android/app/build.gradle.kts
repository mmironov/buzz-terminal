import java.io.FileInputStream
import java.util.Properties

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

        // The commit count, for the same reason the iOS build number is: it always
        // rises, the same commit always yields the same number, and nobody has to
        // remember to bump anything. Falls back to 1 outside a git checkout.
        versionCode = commitCount()
        versionName = "1.0"
    }

    // Read from a gitignored keystore.properties rather than hard-coded, because
    // a signing key is a credential: whoever holds it can ship an update that
    // Android will install over the real app. See docs/distribution.md.
    val keystoreProperties = loadKeystoreProperties()

    signingConfigs {
        if (keystoreProperties != null) {
            create("release") {
                // Resolved against android/, where keystore.properties itself
                // lives, so a relative path in that file means what it looks
                // like. `file()` here would resolve against app/ instead.
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // Unsigned when there is no keystore. That still builds — which is
            // what CI and a fresh clone need — but Android refuses to install
            // the result, so it cannot be mistaken for a distributable one.
            signingConfig = signingConfigs.findByName("release")
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

// Name each test as it runs, matching what `:domain` prints. Without this a
// passing run is silent and a failing one says only that the task failed.
tasks.withType<Test>().configureEach {
    testLogging {
        events("passed", "failed", "skipped")
    }
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

    // Plain JVM tests, no device. Almost everything worth testing lives in
    // `:domain` and is tested there; the one test class here covers the Firestore
    // field names, which are a security contract `:domain` deliberately cannot
    // see. JUnit 4, unlike `:domain`'s JUnit 5 — it is Android's default and needs
    // no engine wiring for a single test class.
    testImplementation(libs.kotlin.test.junit)
}

/**
 * The keystore's details, or null when there is no keystore on this machine.
 *
 * Absence is a normal state, not an error: the file is gitignored, so a fresh
 * clone and CI both have none, and both should still be able to build a release
 * to prove it compiles. Only signing is withheld.
 */
fun loadKeystoreProperties(): Properties? {
    val file = rootProject.file("keystore.properties")
    if (!file.exists()) return null
    return Properties().apply { FileInputStream(file).use(::load) }
}

/**
 * `git rev-list --count HEAD`, or 1 outside a checkout (a source archive, say).
 *
 * Read from git rather than hard-coded so it cannot go stale. Firebase App
 * Distribution does not require the number to rise, but a device does: Android
 * refuses to install an APK whose versionCode is lower than the installed one,
 * and silently keeping the old build is a nasty way to lose an afternoon.
 *
 * Run through `providers.exec` rather than ProcessBuilder: the configuration
 * cache rejects a raw external process at configuration time, and this is the
 * supported way to declare one so its result can be cached and invalidated.
 */
fun commitCount(): Int {
    val git = providers.exec {
        commandLine("git", "rev-list", "--count", "HEAD")
        workingDir = rootProject.projectDir
        isIgnoreExitValue = true
    }
    if (git.result.get().exitValue != 0) return 1
    return git.standardOutput.asText.get().trim().toIntOrNull() ?: 1
}
