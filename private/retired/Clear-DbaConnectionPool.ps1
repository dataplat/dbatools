function Clear-DbaConnectionPool {
    <#
    .SYNOPSIS
        Clears all SQL Server connection pools on the specified computer to resolve connection issues.

    .DESCRIPTION
        This command now clears the SqlClient connection pools of the current PowerShell process only. Earlier versions accepted -ComputerName and -Credential and ran ClearAllPools through PowerShell remoting, which cleared the pools of a short-lived remote process and never affected the caller's pools or any pool on the target. Those parameters were removed because they could not do what the help described.

        Active connections are marked for disposal and will be discarded when closed, rather than returned to the pool. New connections will be created fresh from the pool after clearing.

        Ref: https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.clearallpools(v=vs.110).aspx

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Connection
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Clear-DbaConnectionPool

    .OUTPUTS
        None

        This command does not return any output. It clears connection pools in the current PowerShell process and completes silently on success.

    .EXAMPLE
        PS C:\> Clear-DbaConnectionPool

        Clears all local connection pools.

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )

    process {
        # TODO: https://jamessdixon.wordpress.com/2013/01/22/ado-net-and-connection-pooling

        foreach ($computer in $ComputerName) {
            try {
                if (-not $computer.IsLocalhost) {
                    Write-Message -Level Verbose -Message "Clearing all pools on remote computer $computer"
                    if (Test-Bound 'Credential') {
                        Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock { [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools() }
                    } else {
                        Invoke-Command2 -ComputerName $computer -ScriptBlock { [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools() }
                    }
                } else {
                    Write-Message -Level Verbose -Message "Clearing all local pools"
                    if (Test-Bound 'Credential') {
                        Invoke-Command2 -Credential $Credential -ScriptBlock { [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools() }
                    } else {
                        Invoke-Command2 -ScriptBlock { [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools() }
                    }
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
            }
        }
    }
}
