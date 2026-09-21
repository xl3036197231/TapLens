param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $FlutterArgs
)

$FlutterBin = if ($env:FLUTTER_BIN) { $env:FLUTTER_BIN } else { "flutter" }
& $FlutterBin test @FlutterArgs
exit $LASTEXITCODE
