plugins {
    alias(libs.plugins.kotlin.jvm)
}

// A plain JVM library. No `com.android.library`, no Compose, no Firebase — the
// whole point is that the rules of the festival compile and test without an
// emulator, in the same spirit as the iOS `Domain/` folder importing only
// Foundation.
//
// java.time is used for check-in timestamps, which is also why the app module
// sets minSdk 26: that is the first Android release with it.
kotlin {
    jvmToolchain(libs.versions.jvmTarget.get().toInt())
}

dependencies {
    // The repository seam is `suspend`, exactly as the Swift one is `async`, so
    // coroutines-core comes along. It is a plain JVM library — nothing Android
    // about it — so this does not compromise the module's independence.
    api(libs.kotlinx.coroutines.core)

    testImplementation(kotlin("test"))
    testImplementation(libs.kotlinx.coroutines.test)
}

tasks.test {
    useJUnitPlatform()
    testLogging {
        events("passed", "failed", "skipped")
    }
}
