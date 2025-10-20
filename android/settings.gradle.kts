// android/settings.gradle.kts

// ---------------------------------------------------------
// Section 1: 插件管理和 Flutter Gradle 插件的加载
// ---------------------------------------------------------
pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        // 在 CI/CD 环境中，local.properties 可能不存在，需要优雅处理
        val localPropertiesFile = file("local.properties")
        if (localPropertiesFile.exists()) {
            localPropertiesFile.inputStream().use { properties.load(it) }
        }
        val flutterSdkPath = properties.getProperty("flutter.sdk") ?: System.getenv("FLUTTER_ROOT")
        require(flutterSdkPath != null) {
            "Flutter SDK not found. Define location with flutter.sdk in the local.properties file or with a FLUTTER_ROOT environment variable."
        }
        flutterSdkPath
    }
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
    }
}

// ---------------------------------------------------------
// Section 2: 插件应用
// ---------------------------------------------------------
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.0" apply false
    id("org.jetbrains.kotlin.android") version "1.8.10" apply false
}

// ---------------------------------------------------------
// Section 3: 定义项目结构
// ---------------------------------------------------------
rootProject.name = "android"
include(":app")

// ---------------------------------------------------------
// Section 4: 依赖解析管理
// ---------------------------------------------------------
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // 阿里云镜像等其他仓库
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://jitpack.io") }
    }
}
