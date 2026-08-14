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
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
    testLogging {
        events("passed", "failed", "skipped")
    }
}
