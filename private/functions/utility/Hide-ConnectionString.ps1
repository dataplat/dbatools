function Hide-ConnectionString {
    [CmdletBinding()]
    Param (
        [string]$ConnectionString
    )
    try {
        $connStringBuilder = New-Object Microsoft.Data.SqlClient.SqlConnectionStringBuilder $ConnectionString
        if ($connStringBuilder.Password) {
            $connStringBuilder.Password = ''.Padleft(8, '*')
        }
        return $connStringBuilder.ConnectionString
    } catch {
        return "Failed to mask the connection string`: $($_.Exception.Message)"
    }
}