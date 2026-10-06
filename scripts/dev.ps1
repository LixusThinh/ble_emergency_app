param(
    [ValidateSet('run', 'test', 'analyze', 'build', 'benchmark')]
    [string]$Action = 'run',
    [string]$Device = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$originalPath = $env:PATH
$originalJava = $env:JAVA_HOME
try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $gitLocations = @(
            'C:\Program Files\Git\cmd',
            'C:\Dev\flutter\bin\mingit\cmd',
            (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd')
        )
        $gitDirectory = $gitLocations | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'git.exe') } | Select-Object -First 1
        if (-not $gitDirectory) { throw 'Cần cài Git for Windows và thêm Git vào PATH để chạy Flutter.' }
        $env:PATH = "$gitDirectory;$env:PATH"
    }
    if (-not $env:JAVA_HOME -and (Test-Path -LiteralPath 'C:\Program Files\Android\Android Studio\jbr')) {
        $env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
    }
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $flutterCommand) { throw 'Không tìm thấy Flutter trong PATH. Cần Flutter stable / Dart >=3.13.3.' }
    Push-Location -LiteralPath $projectRoot
    try {
        switch ($Action) {
            'run' { if ($Device) { & $flutterCommand.Source run -d $Device } else { & $flutterCommand.Source run } }
            'test' { & $flutterCommand.Source test }
            'analyze' { & $flutterCommand.Source analyze }
            'build' { & $flutterCommand.Source build apk --debug --target lib/main.dart }
            'benchmark' {
                $flutterBin = Split-Path -Parent $flutterCommand.Source
                & (Join-Path $flutterBin 'dart.bat') run tool/benchmark.dart
            }
        }
        if ($LASTEXITCODE -ne 0) { throw "Tác vụ $Action thất bại, mã $LASTEXITCODE" }
    } finally { Pop-Location }
} finally {
    $env:PATH = $originalPath
    $env:JAVA_HOME = $originalJava
}
