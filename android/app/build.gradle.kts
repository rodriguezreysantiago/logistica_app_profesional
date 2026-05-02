plugins {
    id("com.android.application")
    id("kotlin-android")
    // El plugin de Google Services debe ir despu�s de los de Android/Kotlin
    id("com.google.gms.google-services")
    // Crashlytics: requiere google-services declarado antes � el plugin
    // se engancha al build para subir el mapping de obfuscaci�n a
    // Firebase. En debug es no-op porque AppLogger desactiva la
    // colecci�n, pero el plugin igual debe estar declarado.
    id("com.google.firebase.crashlytics")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.coopertrans.movil"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Mantenemos 17 pero aseguramos la compatibilidad
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.coopertrans.movil"
        
        // ?? FORZAMOS minSdk a 23 para evitar errores de compatibilidad con Firebase
        minSdk = 23 
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ?? ACTIVAMOS MULTIDEX: Vital para que no choquen los hilos en apps grandes
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // Signing with the debug keys for now
            signingConfig = signingConfigs.getByName("debug")
            
            // Sugerencia: optimizaci�n de recursos
            minifyEnabled = false
            shrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Agregamos la dependencia de multidex expl�cita por seguridad
    implementation("androidx.multidex:multidex:2.0.1")
}
