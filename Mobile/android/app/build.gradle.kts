import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val developmentArtifactSigningKey =
    "mobile-development-1:11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="
val artifactSigningPublicKeys = providers.gradleProperty("artifactSigningPublicKeys")
val releaseStoreFile = providers.gradleProperty("releaseStoreFile")
val releaseStorePassword = providers.gradleProperty("releaseStorePassword")
val releaseKeyAlias = providers.gradleProperty("releaseKeyAlias")
val releaseKeyPassword = providers.gradleProperty("releaseKeyPassword")
val releaseDartDefines = providers.gradleProperty("dart-defines").orNull
    ?.split(',')
    ?.mapNotNull { encoded ->
        runCatching {
            String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
        }.getOrNull()
    }
    ?.mapNotNull { value ->
        val separator = value.indexOf('=')
        if (separator <= 0) null else value.substring(0, separator) to value.substring(separator + 1)
    }
    ?.toMap()
    .orEmpty()

android {
    namespace = "com.hexing.zhilian.hexing_terminal_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.hexing.zhilian.hexing_terminal_mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["artifactSigningPublicKeys"] = ""
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    signingConfigs {
        create("release") {
            if (releaseStoreFile.isPresent) {
                storeFile = file(releaseStoreFile.get())
                storePassword = releaseStorePassword.orNull
                keyAlias = releaseKeyAlias.orNull
                keyPassword = releaseKeyPassword.orNull
            }
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
            enableV4Signing = true
        }
    }

    buildTypes {
        debug {
            manifestPlaceholders["artifactSigningPublicKeys"] =
                artifactSigningPublicKeys.orElse(developmentArtifactSigningKey).get()
                    .replace(',', ';')
        }
        release {
            manifestPlaceholders["artifactSigningPublicKeys"] =
                artifactSigningPublicKeys.orElse("").get().replace(',', ';')
            signingConfig = signingConfigs.getByName("release")
        }
    }

    packaging {
        jniLibs {
            excludes += setOf("lib/armeabi-v7a/**")
        }
    }
}

tasks.configureEach {
    if (name == "preReleaseBuild") {
        doFirst {
            if (artifactSigningPublicKeys.orNull.isNullOrBlank()) {
                throw GradleException(
                    "Release builds require " +
                        "-PartifactSigningPublicKeys=<keyId:base64PublicKey>",
                )
            }
            val nativeArtifactKeys = artifactSigningPublicKeys.get().trim()
            if (nativeArtifactKeys.contains("mobile-development-1:")) {
                throw GradleException("Development artifact signing keys are forbidden in Release builds")
            }
            val dartArtifactKeys = releaseDartDefines["MOBILE_ARTIFACT_PUBLIC_KEYS"]?.trim()
            if (dartArtifactKeys.isNullOrBlank()) {
                throw GradleException(
                    "Release builds require " +
                        "--dart-define=MOBILE_ARTIFACT_PUBLIC_KEYS=<keyId:base64PublicKey>",
                )
            }
            if (dartArtifactKeys != nativeArtifactKeys) {
                throw GradleException(
                    "Dart and native MOBILE_ARTIFACT_PUBLIC_KEYS must be identical",
                )
            }
            val controlPlaneUrl = releaseDartDefines["CONTROL_PLANE_URL"]?.trim().orEmpty()
                .ifBlank { "http://43.198.199.162" }
            if (!controlPlaneUrl.startsWith("https://", ignoreCase = true) &&
                !controlPlaneUrl.equals("http://43.198.199.162", ignoreCase = true)
            ) {
                throw GradleException(
                    "Release builds require an HTTPS CONTROL_PLANE_URL dart define or the current test server http://43.198.199.162",
                )
            }
            val signingValues = listOf(
                releaseStoreFile.orNull,
                releaseStorePassword.orNull,
                releaseKeyAlias.orNull,
                releaseKeyPassword.orNull,
            )
            if (signingValues.any { it.isNullOrBlank() }) {
                throw GradleException(
                    "Release builds require releaseStoreFile, releaseStorePassword, " +
                        "releaseKeyAlias and releaseKeyPassword Gradle properties",
                )
            }
            if (!file(releaseStoreFile.get()).isFile) {
                throw GradleException("Release keystore does not exist: ${releaseStoreFile.get()}")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
