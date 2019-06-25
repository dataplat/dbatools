function Clear-DbaConnectionPool {
    <#
    .SYNOPSIS
        Resets (or empties) the connection pool.

    .DESCRIPTION
        This command resets (or empties) the connection pool.

        If there are connections in use at the time of the call, they are marked appropriately and will be discarded (instead of being returned to the pool) when Close() is called on them.

        Ref: https://msdn.microsoft.com/en-us/library/system.data.sqlclient.sqlconnection.clearallpools(v=vs.110).aspx

    .PARAMETER ComputerName
        Target computer(s). If no computer name is specified, the local computer is targeted.

    .PARAMETER Credential
        Alternate credential object to use for accessing the target computer(s).

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Connection
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Clear-DbaConnectionPool

    .EXAMPLE
        PS C:\> Clear-DbaConnectionPool

        Clears all local connection pools.

    .EXAMPLE
        PS C:\> Clear-DbaConnectionPool -ComputerName workstation27

        Clears all connection pools on workstation27.

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
                        Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock { [System.Data.SqlClient.SqlConnection]::ClearAllPools() }
                    } else {
                        Invoke-Command2 -ComputerName $computer -ScriptBlock { [System.Data.SqlClient.SqlConnection]::ClearAllPools() }
                    }
                } else {
                    Write-Message -Level Verbose -Message "Clearing all local pools"
                    if (Test-Bound 'Credential') {
                        Invoke-Command2 -Credential $Credential -ScriptBlock { [System.Data.SqlClient.SqlConnection]::ClearAllPools() }
                    } else {
                        Invoke-Command2 -ScriptBlock { [System.Data.SqlClient.SqlConnection]::ClearAllPools() }
                    }
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
            }
        }
    }
}