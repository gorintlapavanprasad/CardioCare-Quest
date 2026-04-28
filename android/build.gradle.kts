allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Suppress noisy compile warnings emitted by third-party Flutter plugins
// (Firebase, Geolocator, etc.) whose Java sources still target Java 8 and
// contain unchecked/deprecated API calls. Our own app code is Dart, so this
// only affects plugin subprojects.
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        options.compilerArgs.addAll(
            listOf(
                "-Xlint:-options",
                "-Xlint:-unchecked",
                "-Xlint:-deprecation"
            )
        )
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
