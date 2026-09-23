param(
    [string]$Flutter = 'flutter',
    [string]$Device = 'emulator-5554'
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))

function Compress-Fixture([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $stream = [System.IO.MemoryStream]::new()
    $gzipStream = [System.IO.Compression.GZipStream]::new(
        $stream,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $true
    )
    try {
        $gzipStream.Write($bytes, 0, $bytes.Length)
    }
    finally {
        $gzipStream.Dispose()
    }
    return [Convert]::ToBase64String($stream.ToArray())
}

$cloud = Compress-Fixture (Join-Path $repoRoot 'shared\fixtures\cloud\day2-short-link-succeeded.json')
$report = Compress-Fixture (Join-Path $repoRoot 'shared\fixtures\reports\day3-short-link-verified.json')

Push-Location (Join-Path $repoRoot 'mobile')
try {
    $testArguments = @(
        'test', 'integration_test/day3_ai_report_test.dart', '-d', $Device,
        "--dart-define=TAPLENS_DAY3_CLOUD=$cloud",
        "--dart-define=TAPLENS_DAY3_REPORT=$report"
    )
    & $Flutter @testArguments
    $result = $LASTEXITCODE
}
finally {
    Pop-Location
}
exit $result
