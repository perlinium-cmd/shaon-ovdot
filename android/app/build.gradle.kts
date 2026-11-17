plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.perlinium.shaon.employee"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.perlinium.shaon.employee"
        minSdk = 26
        targetSdk = 36
        versionCode = 4
        versionName = "1.3"
        // ./gradlew assembleDebug -Pemulator=true  -> talks to the local Firebase emulators (tests), never to real data.
        buildConfigField("boolean", "USE_EMULATOR", (project.findProperty("emulator") == "true").toString())
    }

    // Release key lives outside the repo (~/.gradle/gradle.properties -> SHAON_*). It must be kept forever:
    // updates only install over an app signed with the same key.
    val storeFilePath = project.findProperty("SHAON_STORE_FILE") as String?
    signingConfigs {
        if (storeFilePath != null) create("release") {
            storeFile = file(storeFilePath)
            storePassword = project.property("SHAON_STORE_PASSWORD") as String
            keyAlias = project.property("SHAON_KEY_ALIAS") as String
            keyPassword = project.property("SHAON_KEY_PASSWORD") as String
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release")
            // In-app updates (update/Updater.kt): tools/release-android.sh publishes here. A qa build with
            // -Pemulator=true checks a local test server on the Mac (port 5055) instead, never the real one.
            val feed = if (project.findProperty("emulator") == "true") "http://10.0.2.2:5055/android/latest.json"
                else "https://shaon-ovdot-2c10.web.app/android/latest.json"
            buildConfigField("String", "UPDATE_FEED", "\"$feed\"")
        }
        debug { buildConfigField("String", "UPDATE_FEED", "\"\"") }   // debug key: a release APK can't install over it
        // The exact release build (R8, release key) pointed at the local emulators: ./gradlew assembleQa -Pemulator=true
        create("qa") {
            initWith(getByName("release"))
            matchingFallbacks += "release"
        }
    }
    sourceSets["qa"].res.srcDir("src/debug/res")
    sourceSets["qa"].manifest.srcFile("src/debug/AndroidManifest.xml")
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true; buildConfig = true }
    testOptions { unitTests.isReturnDefaultValues = true }
    sourceSets["test"].resources.srcDir("../../shared")   // shared/pay-cases.json
}

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.10.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.4")

    implementation(platform("com.google.firebase:firebase-bom:34.4.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")

    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")   // QR without camera permission
    implementation("com.google.android.gms:play-services-auth-blockstore:16.4.0") // "connect once, forever"
    implementation("androidx.work:work-runtime-ktx:2.10.5")
    implementation("androidx.glance:glance-appwidget:1.1.1")
    implementation("androidx.glance:glance-material3:1.1.1")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
