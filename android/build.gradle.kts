// android/settings.gradle.kts

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // 这里是配置项目依赖库的地方
        google()
        mavenCentral()
        // 你之前配置的阿里云镜像可以放在这里，用于加速依赖库下载
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        maven("https://maven.aliyun.com/repository/gradle-plugin")
    }
}

rootProject.name = "android"
include(":app")