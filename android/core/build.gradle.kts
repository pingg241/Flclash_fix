import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
}

val targetPlatform =
    (project.findProperty("target-platform") ?: rootProject.findProperty("target-platform"))
        ?.toString()
val requestedAbis =
    when (val androidArch = System.getenv("ANDROID_ARCH")) {
        "arm" -> listOf("armeabi-v7a")
        "arm64" -> listOf("arm64-v8a")
        "amd64" -> listOf("x86_64")
        null -> {
            targetPlatform?.let { platforms ->
                platforms
                    .split(',')
                    .map { platform ->
                        when (val name = platform.trim()) {
                            "android-arm" -> "armeabi-v7a"
                            "android-arm64" -> "arm64-v8a"
                            "android-x64" -> "x86_64"
                            else -> throw GradleException("Invalid target-platform: $name")
                        }
                    }.distinct()
                    .ifEmpty { throw GradleException("No Android target platforms provided") }
            } ?: listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
        else -> throw GradleException("Invalid ANDROID_ARCH: $androidArch")
    }

android {
    namespace = "com.follow.clash.core"
    compileSdk = libs.versions.compileSdk.get().toInt()
    ndkVersion = libs.versions.ndkVersion.get()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
        ndk {
            abiFilters += requestedAbis
        }
    }


    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    externalNativeBuild {
        cmake {
            path("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}


dependencies {
    implementation(libs.annotation.jvm)
}
