function Convert-ConnectionString {
    <#

    # there are new synonyms in Microsoft.Data
    # https://docs.microsoft.com/en-us/sql/connect/ado-net/introduction-microsoft-data-sqlclient-namespace?view=sql-server-ver15#new-connection-string-property-synonyms

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$ConnectionString
    )

    foreach ($connstring in $ConnectionString) {
        $array = $connstring.Split(';')
        foreach ($item in $array) {
            $connstring = $connstring.Replace("Application Intent", "ApplicationIntent")
            $connstring = $connstring.Replace("Connect Retry Count", "ConnectRetryCount")
            $connstring = $connstring.Replace("Connect Retry Interval", "ConnectRetryInterval")
            $connstring = $connstring.Replace("Pool Blocking Period", "PoolBlockingPeriod")
            $connstring = $connstring.Replace("Multiple Active Result Sets", "MultipleActiveResultSets")
            $connstring = $connstring.Replace("Multiple Subnet Failover", "MultiSubnetFailover")
            $connstring = $connstring.Replace("Trust Server Certificate", "TrustServerCertificate")
        }
        $connstring
    }
}