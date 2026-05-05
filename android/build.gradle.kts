allprojects {
    repositories {
        google()
        mavenCentral()
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

// Kotlin 2.x dejó de soportar languageVersion 1.6 (usado por sentry_flutter
// y otros plugins viejos). Forzamos mínimo 1.9 en todos los subproyectos.
subprojects {
    afterEvaluate {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9)
                apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_9)
            }
        }
    }
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
        classpath("com.google.gms:google-services:4.4.2")
    }
}