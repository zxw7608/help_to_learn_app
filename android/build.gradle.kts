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
    // 将配置逻辑提取为一个独立的闭包函数
    val configureNamespace = {
        try {
            val androidExt = extensions.findByName("android")
            if (androidExt is com.android.build.gradle.LibraryExtension) {
                if (androidExt.namespace == null) {
                    val manifestFile = file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val doc = javax.xml.parsers.DocumentBuilderFactory.newInstance()
                            .newDocumentBuilder().parse(manifestFile)
                        val pkg = doc.documentElement.getAttribute("package")
                        if (!pkg.isNullOrEmpty()) {
                            androidExt.namespace = pkg
                        } else {
                            // 兜底方案：如果解析不到 package，使用 group 名字
                            androidExt.namespace = project.group.toString()
                        }
                    }
                }
                // 旧版插件可能未设置 compileSdk，导致 release 构建出现 lStar 错误
                if (androidExt.compileSdk == null) {
                    androidExt.compileSdk = 35
                }
            }
        } catch (_: Exception) {
            // ignore
        }
    }

    // 动态判断生命周期状态
    if (state.executed) {
        // 如果子项目已经评估完毕，直接执行
        configureNamespace()
    } else {
        // 如果还没评估，挂载到评估完成后的钩子上
        afterEvaluate {
            configureNamespace()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
