plugins {
    id("com.google.gms.google-services") version "4.4.2" apply false
}

allprojects {
    val targetBuildDir = rootProject.rootDir.resolve("../build").resolve(project.name)
    project.layout.buildDirectory.set(targetBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
    configurations.all {
        resolutionStrategy.force("androidx.glance:glance-appwidget:1.1.1")
        resolutionStrategy.force("androidx.glance:glance:1.1.1")
        resolutionStrategy.force("androidx.compose.remote:remote-creation-android:1.0.0-alpha10")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}