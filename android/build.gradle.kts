allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Force any Android library subproject (e.g. flutter_webrtc, which hardcodes
// compileSdkVersion 31 in its own build.gradle) up to SDK 36 to match this
// project's compileSdk. Must run in afterEvaluate: the plugin's own
// build.gradle sets its compileSdkVersion AFTER applying `com.android.library`,
// so an earlier plugins.withId() override would just get clobbered. There is
// no evaluationDependsOn(":app") call here — that was forcing :app to evaluate
// early and crashing this exact hook with "project is already evaluated".
subprojects {
    afterEvaluate {
        val android = project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        android?.compileSdkVersion(36)
    }
}