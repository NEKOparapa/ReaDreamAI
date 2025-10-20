// android/settings.gradle.kts

// ##### 新增部分：在文件顶部导入 FlutterGradle.kt #####
import dev.flutter.plugins.FlutterGradle

// #######################################################


pluginManagement {
    // 这部分是你原来的 Flutter SDK 路径解析，保持不变
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        // ... 你的阿里云镜像 ...
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        // ... 你的阿里云镜像 ...
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://jitpack.io") }

        // ##### 修改部分：使用 FlutterGradle.instance.getEngineArtifactsDir() #####
        // 这是官方推荐的、获取 Flutter 引擎本地仓库的正确方式
        maven(FlutterGradle.instance.getEngineArtifactsDir(this).path)
        // #######################################################
    }
}

rootProject.name = "android"
include(":app")

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.8.22" apply false
}