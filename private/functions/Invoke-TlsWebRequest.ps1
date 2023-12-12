function Invoke-TlsWebRequest {
    Param (
        [switch]$UseBasicParsing,
        [switch]$ProxyUseDefaultCredentials
    )
    <#
    Internal utility that mimics invoke-webrequest
    but enables all tls available version
    rather than the default, which on a lot
    of standard installations is just TLS 1.0

    #>
    $currentVersionTls = [Net.ServicePointManager]::SecurityProtocol
    $currentSupportableTls = [Math]::Max($currentVersionTls.value__, [Net.SecurityProtocolType]::Tls.value__)
    $availableTls = [enum]::GetValues('Net.SecurityProtocolType') | Where-Object { $_ -gt $currentSupportableTls }
    $availableTls | ForEach-Object {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor $_
    }

    Invoke-WebRequest @Args -UseBasicParsing:$UseBasicParsing -ProxyUseDefaultCredentials:$ProxyUseDefaultCredentials

    [Net.ServicePointManager]::SecurityProtocol = $currentVersionTls
}