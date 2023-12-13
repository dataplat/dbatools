function Invoke-TlsWebRequest {
    param(
        [switch]$UseBasicParsing,
        [Uri]$Uri,
        [Version]$HttpVersion,
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,
        [String]$SessionVariable,
        [switch]$AllowUnencryptedAuthentication,
        [Microsoft.PowerShell.Commands.WebAuthenticationType]$Authentication,
        [PSCredential]$Credential,
        [switch]$UseDefaultCredentials,
        [String]$CertificateThumbprint,
        [X509Certificate]$Certificate,
        [switch]$SkipCertificateCheck,
        [Microsoft.PowerShell.Commands.WebSslProtocol]$SslProtocol,
        [SecureString]$Token,
        [String]$UserAgent,
        [switch]$DisableKeepAlive,
        [Int32]$ConnectionTimeoutSeconds,
        [Int32]$OperationTimeoutSeconds,
        [Collections.IDictionary]$Headers,
        [switch]$SkipHeaderValidation,
        [switch]$AllowInsecureRedirect,
        [Int32]$MaximumRedirection,
        [Int32]$MaximumRetryCount,
        [switch]$PreserveAuthorizationOnRedirect,
        [Int32]$RetryIntervalSec,
        [String]$CustomMethod,
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method,
        [switch]$PreserveHttpMethodOnRedirect,
        [System.Net.Sockets.UnixDomainSocketEndPoint]$UnixSocket,
        [switch]$NoProxy,
        [Uri]$Proxy,
        [PSCredential]$ProxyCredential,
        [switch]$ProxyUseDefaultCredentials,
        [Object]$Body,
        [Collections.IDictionary]$Form,
        [String]$ContentType,
        [String]$TransferEncoding,
        [String]$InFile,
        [String]$OutFile,
        [switch]$PassThru,
        [switch]$Resume,
        [switch]$SkipHttpErrorCheck
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

    Invoke-WebRequest @PSBoundParameters

    [Net.ServicePointManager]::SecurityProtocol = $currentVersionTls
}