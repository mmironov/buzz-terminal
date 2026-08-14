pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "BuzzTerminal"

// `:domain` is a plain JVM module on purpose — it has no Android dependency at
// all, which is how the iOS side's "Domain/ imports Foundation only" rule is
// enforced here. You cannot accidentally reach for a Composable or a Context in
// it, because neither is on the compile classpath.
include(":domain")
include(":app")
