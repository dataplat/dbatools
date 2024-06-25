# Only update on first import
if (-not ([Dataplat.Dbatools.dbaSystem.SystemHost]::ModuleImported)) {
    # Implement query accelerator for the server object
    Update-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Server -MemberName Query -MemberType ScriptMethod -Value {
        param (
            [string]$Query,
            [string]$Database,
            [bool]$AllTables
        )

        $sqlConnection = $this.ConnectionContext.SqlConnectionObject
        if ($sqlConnection.State -ne 'Open') {
            $sqlConnection.Open()
        }
        if ($Database -and $Database -ne $sqlConnection.Database) {
            $sqlConnection.ChangeDatabase($Database)
        }
        $sqlCommand = New-Object Microsoft.Data.SqlClient.SqlCommand($Query, $sqlConnection)
        $sqlDataAdapter = New-Object Microsoft.Data.SqlClient.SqlDataAdapter($sqlCommand)
        $dataSet = New-Object System.Data.DataSet
        [void]$sqlDataAdapter.Fill($dataSet)
        if ($AllTables) {
            $dataSet.Tables
        } else {
            $dataSet.Tables[0]
        }
    } -ErrorAction Ignore

    Update-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Server -MemberName Invoke -MemberType ScriptMethod -Value {
        param (
            [string]$Command,
            [string]$Database
        )

        $sqlConnection = $this.ConnectionContext.SqlConnectionObject
        if ($sqlConnection.State -ne 'Open') {
            $sqlConnection.Open()
        }
        if ($Database -and $Database -ne $sqlConnection.Database) {
            $sqlConnection.ChangeDatabase($Database)
        }
        $sqlCommand = New-Object Microsoft.Data.SqlClient.SqlCommand($Query, $sqlConnection)
        $sqlCommand.ExecuteNonQuery()
    } -ErrorAction Ignore

    Update-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Database -MemberName Query -MemberType ScriptMethod -Value {
        param (
            $Query,

            $AllTables = $false
        )

        if ($AllTables) { ($this.ExecuteWithResults($Query)).Tables }
        else { ($this.ExecuteWithResults($Query)).Tables[0] }
    } -ErrorAction Ignore

    Update-TypeData -TypeName Microsoft.SqlServer.Management.Smo.Database -MemberName Invoke -MemberType ScriptMethod -Value {
        param (
            $Command
        )

        $this.ExecuteNonQuery($Command)
    } -ErrorAction Ignore
}