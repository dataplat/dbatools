function Remove-DbaCmConnection {
    <#
    .SYNOPSIS
        Removes connection objects from the connection cache used for remote computer management.

    .DESCRIPTION
        Removes connection objects from the connection cache used for remote computer management.

    .PARAMETER ComputerName
        The target computer. Accepts both text as well as the output of Get-DbaCmConnection.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ComputerManagement, CIM
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaCmConnection

    .EXAMPLE
        PS C:\> Remove-DbaCmConnection -ComputerName sql2014

        Removes the cached connection to the server sql2014 from the cache.

    .EXAMPLE
        PS C:\> Get-DbaCmConnection | Remove-DbaCmConnection

        Clears the entire connection cache.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(ValueFromPipeline, Mandatory)]
        [Sqlcollaborative.Dbatools.Parameter.DbaCmConnectionParameter[]]$ComputerName,
        [switch]$EnableException
    )

    begin {
        Write-Message -Level InternalComment -Message "Starting"
        Write-Message -Level Verbose -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
    }
    process {
        foreach ($connectionObject in $ComputerName) {
            if (-not $connectionObject.Success) { Stop-Function -Message "Failed to interpret computername input: $($connectionObject.InputObject)" -Category InvalidArgument -Target $connectionObject.InputObject -Continue }
            Write-Message -Level VeryVerbose -Message "Removing from connection cache: $($connectionObject.Connection.ComputerName)" -Target $connectionObject.Connection.ComputerName
            if ($Pscmdlet.ShouldProcess($($connectionObject.Connection.ComputerName), "Removing Connection")) {
                if ([Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections.ContainsKey($connectionObject.Connection.ComputerName)) {
                    $null = [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections.Remove($connectionObject.Connection.ComputerName)
                    Write-Message -Level Verbose -Message "Successfully removed $($connectionObject.Connection.ComputerName)" -Target $connectionObject.Connection.ComputerName
                } else {
                    Write-Message -Level Verbose -Message "Not found: $($connectionObject.Connection.ComputerName)" -Target $connectionObject.Connection.ComputerName
                }
            }
        }
    }
    end {
        Write-Message -Level InternalComment -Message "Ending"
    }
}