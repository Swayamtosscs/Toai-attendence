allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    
    afterEvaluate {
        tasks.withType<JavaCompile>().configureEach {
            options.compilerArgs.removeAll { it.isBlank() }
            if (sourceCompatibility == null) {
                sourceCompatibility = JavaVersion.VERSION_17.toString()
            }
            if (targetCompatibility == null) {
                targetCompatibility = JavaVersion.VERSION_17.toString()
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
