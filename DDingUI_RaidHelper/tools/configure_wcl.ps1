$ErrorActionPreference = "Stop"

$clientId = Read-Host "Warcraft Logs Client ID"
if ([string]::IsNullOrWhiteSpace($clientId)) {
    throw "Client ID is required."
}

$secureSecret = Read-Host "Warcraft Logs Client Secret" -AsSecureString
$secretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSecret)

try {
    $clientSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer)
    if ([string]::IsNullOrWhiteSpace($clientSecret)) {
        throw "Client Secret is required."
    }

    [Environment]::SetEnvironmentVariable("WCL_CLIENT_ID", $clientId.Trim(), "User")
    [Environment]::SetEnvironmentVariable("WCL_CLIENT_SECRET", $clientSecret.Trim(), "User")
}
finally {
    if ($secretPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
    }
    $clientSecret = $null
}

Write-Host "Warcraft Logs credentials saved to the current Windows user environment." -ForegroundColor Green
Write-Host "You can now run Update_RaidHelper_Data.bat." -ForegroundColor Yellow
