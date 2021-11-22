filter Where-CollationSensitiveObject {
    param(
        [parameter(Mandatory)]
        [string]$Property,
        [parameter(Mandatory)]
        [object]$Value,
        [parameter(Mandatory, ParameterSetName = 'In')]
        [switch]$In,
        [parameter(Mandatory, ParameterSetName = 'Notin')]
        [switch]$Notin,
        [parameter(Mandatory)]
        [String]$Collation)
    $server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server
    $stringComparer = $server.getStringComparer($Collation)
    if ($In) {
        foreach ($ref in $_."$Property") {
            foreach ($dif in $Value) {
                if ($stringComparer.Compare($ref, $dif) -eq 0 ) {
                    return $_
                }
            }
        }
    }
    if ($Notin) {
        foreach ($ref in $_."$Property") {
            foreach ($dif in $Value) {
                if ($stringComparer.Compare($ref, $dif) -ne 0 ) {
                    return $_
                }
            }
        }
    }
}