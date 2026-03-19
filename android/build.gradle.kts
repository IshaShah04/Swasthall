plugins {
    id("com.google.gms.google-services") version "4.4.2" apply false
}

allprojects {
    val targetBuildDir = rootProject.rootDir.resolve("../build").resolve(project.name)
    project.layout.buildDirectory.set(targetBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}