function Invoke-AppVeyorApi {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [string]$AccountName = 'dataplat',

        [string]$Method = 'Get'
    )

    # Check for API token
    $apiToken = $env:APPVEYOR_API_TOKEN
    if (-not $apiToken) {
        Write-Warning "APPVEYOR_API_TOKEN environment variable not set."
        return
    }

    # Always use v1 base URL even with v2 tokens
    $baseUrl = "https://ci.appveyor.com/api"
    $fullUrl = "$baseUrl/$Endpoint"

    # Prepare headers
    $headers = @{
        'Authorization' = "Bearer $apiToken"
        'Content-Type'  = 'application/json'
        'Accept'        = 'application/json'
    }

    Write-Verbose "Making API call to: $fullUrl"

    try {
        $restParams = @{
            Uri         = $fullUrl
            Method      = $Method
            Headers     = $headers
            ErrorAction = 'Stop'
        }
        $response = Invoke-RestMethod @restParams
        return $response
    } catch {
        $errorMessage = "Failed to call AppVeyor API: $($_.Exception.Message)"

        if ($_.ErrorDetails.Message) {
            $errorMessage += " - $($_.ErrorDetails.Message)"
        }

        throw $errorMessage
    }
}
