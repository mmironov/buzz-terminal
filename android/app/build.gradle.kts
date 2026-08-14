// No `org.jetbrains.kotlin.android` here: from AGP 9 the Android plugin brings
// Kotlin with it, and applying the standalone plugin as well is now an error.
// `:domain` still applies `kotlin.jvm`, because it is not an Android module.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
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

    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)
}
