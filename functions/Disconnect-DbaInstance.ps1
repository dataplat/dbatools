function Disconnect-DbaInstance {
    <#
    .SYNOPSIS
        Disconnects or closes a connection to a SQL Server instance

    .DESCRIPTION
        Disconnects or closes a connection to a SQL Server instance

        To clear all of your connection pools, use Clear-DbaConnectionPool

    .PARAMETER InputObject
        The server object to disconnect from, usually piped in from Get-DbaConnectedInstance

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
        PS C:\> Get-DbaConnectedInstance | Out-GridView -Passthru | Disconnect-DbaInstance

        Disconnects selected SQL Server instances

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
        # to avoid enumeration problems when piped
        $objects += $InputObject
    }
    end {
        foreach ($object in $objects) {
            if ($object.ConnectionObject) {
                $servers = $object.ConnectionObject
            } else {
                $servers = $object
            }
            foreach ($server in $servers) {
                try {
                    if ($server.ConnectionContext) {
                        if ($Pscmdlet.ShouldProcess($server.Name, "Disconnecting SQL Connection")) {
                            $null = $server.ConnectionContext.Disconnect()
                            if ($script:connectionhash[$server.ConnectionContext.ConnectionString]) {
                                Write-Message -Level Verbose -Message "removing from connection hash"
                                $null = $script:connectionhash.Remove($server.ConnectionContext.ConnectionString)
                            }
                            [pscustomobject]@{
                                SqlInstance      = $server.Name
                                ConnectionString = (Hide-ConnectionString -ConnectionString $server.ConnectionContext.ConnectionString)
                                ConnectionType   = $server.GetType().FullName
                                State            = "Disconnected"
                            } | Select-DefaultView -Property SqlInstance, ConnectionType, State
                        }
                    }
                    if ($server.GetType().Name -eq "SqlConnection") {
                        if ($Pscmdlet.ShouldProcess($server.DataSource, "Closing SQL Connection")) {
                            if ($server.State -eq "Open") {
                                $null = $server.Close()
                            }

                            if ($script:connectionhash[$server.ConnectionString]) {
                                Write-Message -Level Verbose -Message "removing from connection hash"
                                $null = $script:connectionhash.Remove($server.ConnectionString)
                            }

                            [pscustomobject]@{
                                SqlInstance      = $server.DataSource
                                ConnectionString = (Hide-ConnectionString -ConnectionString $server.ConnectionString)
                                ConnectionType   = $server.GetType().FullName
                                State            = $server.State
                            } | Select-DefaultView -Property SqlInstance, ConnectionType, State
                        }
                    }
                } catch {
                    Stop-Function -Message "Failed to disconnect $object" -ErrorRecord $PSItem -Continue
                }
            }
        }
    }
}