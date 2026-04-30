allprojects {
    repositories {
        google()
        central()
    }
}

// 🛠️ Simplificamos el manejo del buildDir para que sea estándar y no rompa los hilos
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// 🚨 AGREGAMOS ESTO: Es vital para que las versiones de Google y Kotlin coincidan
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Asegurate de que esta versión de gms sea compatible con tu Firebase
        classpath("com.google.gms:google-services:4.4.0")
    }
}