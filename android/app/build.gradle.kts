import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.raunak.swasthall"
    compileSdk = 36

    ndkVersion = "28.2.13676358"

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    // ── Release signing ──────────────────────────────────────────────────────
    // Store keystore credentials in android/key.properties (never commit to git)
    signingConfigs {
        val keyPropertiesFile = rootProject.file("key.properties")
        if (keyPropertiesFile.exists()) {
            val keyProperties = Properties()
            keyProperties.load(FileInputStream(keyPropertiesFile))
            create("release") {
                storeFile     = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias      = keyProperties.getProperty("keyAlias")
                keyPassword   = keyProperties.getProperty("keyPassword")
            }
        }
    }

    defaultConfig {
        applicationId  = "com.raunak.swasthall"
        minSdk         = 24
        targetSdk      = 36
        versionCode    = 1
        versionName    = "1.0"
        multiDexEnabled = true

    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled   = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            val releaseConfig = signingConfigs.findByName("release")
            signingConfig = releaseConfig ?: signingConfigs.getByName("debug")
        }

        getByName("debug") {
            isMinifyEnabled   = false
            isShrinkResources = false
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    packaging {
        resources {
            excludes  += "/META-INF/{AL2.0,LGPL2.1}"
            pickFirsts += "**/libc++_shared.so"
        }
        jniLibs {
            excludes += setOf("**/libtranslate_jni.so")
        }
    }

    buildFeatures {
        buildConfig = true
    }

} 

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.core:core-splashscreen:1.0.1")
    implementation("androidx.multidex:multidex:2.0.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    implementation(platform("com.google.firebase:firebase-bom:33.1.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("im.zego:zpns-fcm:2.7.0")

    implementation("com.google.android.play:core:1.10.3")

    implementation(files("../../esewa_flutter_sdk/android/libs/esewasdk-release.aar"))
}