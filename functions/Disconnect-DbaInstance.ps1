function Disconnect-DbaInstance {
    <#
    .SYNOPSIS
        Disconnects or closes a connected instance

    .DESCRIPTION
        Disconnects or closes a connected instance

    .PARAMETER InputObject
        The server object to disconnet

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Connection
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Disconnect-DbaInstance

    .EXAMPLE
        PS C:\> Get-DbaConnectedInstance | Disconnect-DbaInstance

        Disconnects all connected instances

    .EXAMPLE
        PS C:\> $server = Connect-DbaInstance -SqlInstance sql01
        PS C:\> $server | Disconnect-DbaInstance

        Disconnects the $server connection
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(ValueFromPipeline)]
        [psobject[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($object in $InputObject) {
            try {
                if ($object.ConnectionObject) {
                    $server = $object.ConnectionObject
                } else {
                    $server = $object
                }
                if ($server.ConnectionContext) {
                    if ($Pscmdlet.ShouldProcess($server.Name, "Disconnecting SQL Connection")) {
                        $server.ConnectionContext.Disconnect()
                        [pscustomobject]@{
                            SqlInstance      = [dbainstanceparameter]$server
                            ConnectionString = (Hide-ConnectionString -ConnectionString $server.ConnectionContext.ConnectionString)
                            ConnectionType   = $server.GetType().FullName
                            State            = "Disconnected"
                        } | Select-DefaultView -Property SqlInstance, ConnectionType, State
                    }
                }
                if ($server.GetType().Name -eq "SqlConnection") {
                    if ($Pscmdlet.ShouldProcess($server.Name, "Closing SQL Connection")) {
                        if ($server.State -eq "Open") {
                            $server.Close()
                            [pscustomobject]@{
                                SqlInstance      = [dbainstanceparameter]$server.ConnectionString
                                ConnectionString = (Hide-ConnectionString -ConnectionString $server.ConnectionString)
                                ConnectionType   = $server.GetType().FullName
                                State            = "Disconnected"
                            } | Select-DefaultView -Property SqlInstance, ConnectionType, State
                        }
                    }
                }
            } catch {
                Stop-Function -Message "Failed to disconnect $object" -ErrorRecord $PSItem -Continue
            }
        }
    }
}