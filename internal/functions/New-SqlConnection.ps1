function New-SqlConnection {
    <#
     Created for commands that require System.Data.SqlClient
     SQL Connections, like the replication commands
    #>
    param(
        [string]$SqlInstance,
        [PSCredential]$SqlCredential
    )
    $connstring = (New-DbaConnectionString -SqlInstance $SqlInstance -SqlCredential $SqlCredential).ToString()
    New-Object Microsoft.Data.SqlClient.SqlConnection $connstring
}