function Remove-DbaCmConnection {
    <#
    .SYNOPSIS
    Removes connection objects from the connection cache used for remote computer management.

    .DESCRIPTION
    Removes connection objects from the connection cache used for remote computer management.

    .PARAMETER ComputerName
    The computer whose connection to remove.
    Accepts both text as well as the output of Get-DbaCmConnection.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Author: Fred Winmann (@FredWeinmann)
    Tags: ComputerManagement

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/Remove-DbaCmConnection

    .EXAMPLE
    Remove-DbaCmConnection -ComputerName sql2014

    Removes the cached connection to the server sql2014 from the cache.

    .EXAMPLE
    Get-DbaCmConnection | Remove-DbaCmConnection

    Clears the entire connection cache.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [Sqlcollaborative.Dbatools.Parameter.DbaCmConnectionParameter[]]
        $ComputerName,

        [switch]
        [Alias('Silent')]$EnableException
    )

    BEGIN {
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Verbose -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
    }
    PROCESS {
        foreach ($connectionObject in $ComputerName) {
            if (-not $connectionObject.Success) { Stop-Function -Message "Failed to interpret computername input: $($connectionObject.InputObject)" -Category InvalidArgument -Target $connectionObject.InputObject -Continue }
            Write-Message -Level VeryVerbose -Message "Removing from connection cache: $($connectionObject.Connection.ComputerName)" -Target $connectionObject.Connection.ComputerName
            if ([Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections.ContainsKey($connectionObject.Connection.ComputerName)) {
                $null = [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections.Remove($connectionObject.Connection.ComputerName)
                Write-Message -Level Verbose -Message "Successfully removed $($connectionObject.Connection.ComputerName)" -Target $connectionObject.Connection.ComputerName
            }
            else {
                Write-Message -Level Verbose -Message "Not found: $($connectionObject.Connection.ComputerName)" -Target $connectionObject.Connection.ComputerName
            }
        }
    }
    END {
        Write-Message -Level InternalComment -Message "Ending"
    }
}
