allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
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

// Workaround: legacy Flutter plugins that don't declare namespace in build.gradle
// (e.g. request_permission, flutter_isolate) cause AGP 8.x to fail.
// Read the package attribute from each subproject's AndroidManifest.xml and
// set it as namespace before AGP creates variants.
subprojects {
    afterEvaluate {
        try {
            val androidExt = extensions.findByName("android")
            if (androidExt is com.android.build.gradle.LibraryExtension && androidExt.namespace == null) {
                val manifestFile = file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val doc = javax.xml.parsers.DocumentBuilderFactory.newInstance()
                        .newDocumentBuilder().parse(manifestFile)
                    val pkg = doc.documentElement.getAttribute("package")
                    if (!pkg.isNullOrEmpty()) {
                        androidExt.namespace = pkg
                    }
                }
            }
        } catch (_: Exception) {
            // ignore — not an Android subproject or manifest parsing failed
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
