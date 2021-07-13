function New-SqlConnection {
    <#
     Created for commands that require System.Data.SqlClient
     SQL Connections, like the replication commands
    #>
    param(
        [string]$SqlInstance,
        [PSCredential]$SqlCredential
    )
    $connstring = (New-DbaConnectionStringBuilder -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Legacy).ToString()
    New-Object System.Data.SqlClient.SqlConnection $connstring
}