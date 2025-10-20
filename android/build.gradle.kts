// android/build.gradle.kts

// 使用 plugins 块来声明构建脚本的插件
plugins {
    // 定义 Android Gradle Plugin 的版本
    id("com.android.application") version "8.7.0" apply false // 版本号可以根据你的项目调整，但 8.2.2 是一个稳定版本
    // 定义 Kotlin Gradle Plugin 的版本
    id("org.jetbrains.kotlin.android") version "1.8.10" apply false // 建议与 Flutter 兼容的版本
}