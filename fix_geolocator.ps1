# Fix geolocator_android build.gradle properly
$pubCache = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev"
$geolocatorPath = Get-ChildItem -Path $pubCache -Recurse -Filter "geolocator_android-2.1.0" -Directory | Select-Object -First 1

if ($geolocatorPath) {
    $buildGradle = Join-Path $geolocatorPath.FullName "android\build.gradle"
    if (Test-Path $buildGradle) {
        $content = Get-Content $buildGradle -Raw
        
        # Fix namespace
        if (-not $content.Contains("namespace")) {
            $content = $content -replace "android\s*\{", "android {`n    namespace = 'com.baseflow.geolocator'"
        }
        
        # Fix Java version - replace VERSION_1_8 with VERSION_11
        $content = $content -replace "JavaVersion\.VERSION_1_8", "JavaVersion.VERSION_11"
        $content = $content -replace "JavaVersion\.VERSION_8", "JavaVersion.VERSION_11"
        
        # Fix -Werror issue - remove it properly, including empty options blocks
        # Remove -Werror flag
        $content = $content -replace "\s*-Werror\s*", " "
        # Fix empty options blocks
        $content = $content -replace "options\s*\{\s*\}", ""
        # Fix options blocks with only whitespace
        $content = $content -replace "options\s*\{\s*\n\s*\}", ""
        # If options block becomes empty, remove the whole block
        $content = $content -replace "compileOptions\s*\{\s*\n\s*options\s*\{\s*\}\s*\n\s*\}", "compileOptions {`n        sourceCompatibility = JavaVersion.VERSION_11`n        targetCompatibility = JavaVersion.VERSION_11`n    }"
        
        # Ensure compileOptions has proper Java version if missing
        if ($content -notmatch "sourceCompatibility.*VERSION_11") {
            if ($content -match "compileOptions\s*\{") {
                $content = $content -replace "(compileOptions\s*\{)", "`$1`n        sourceCompatibility = JavaVersion.VERSION_11`n        targetCompatibility = JavaVersion.VERSION_11"
            }
        }
        
        Set-Content -Path $buildGradle -Value $content -NoNewline
        Write-Host "Fixed geolocator_android build configuration"
    }
} else {
    Write-Host "geolocator_android package not found"
}
