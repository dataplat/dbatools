function Disconnect-DbaInstance {
    <#
    .SYNOPSIS
        Closes active SQL Server connections and removes them from the dbatools connection cache

    .DESCRIPTION
        Properly closes SQL Server connections created by dbatools commands like Connect-DbaInstance, preventing connection leaks and freeing up server connection limits. This function handles both SMO server objects and raw SqlConnection objects, ensuring clean disconnection and removing connections from the internal connection hash. Use this in scripts to explicitly manage connection lifecycle, especially when working with multiple instances or in long-running automation where connection limits matter.

        To clear all of your connection pools, use Clear-DbaConnectionPool

    .PARAMETER InputObject
        Specifies the SQL Server connection object(s) to disconnect, such as SMO Server objects or SqlConnection objects from Connect-DbaInstance. Accepts pipeline input from Get-DbaConnectedInstance to disconnect multiple connections at once.
        Use this to explicitly close specific connections rather than letting them time out, which helps prevent connection pool exhaustion and reduces load on SQL Server instances.

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

    .OUTPUTS
        PSCustomObject

        Returns one object per connection successfully disconnected. Contains the following properties:

        Default display properties (via Select-DefaultView):
        - SqlInstance: The name of the SQL Server instance that was disconnected
        - ConnectionType: The full type name of the connection object (e.g., Microsoft.SqlServer.Management.Smo.Server or System.Data.SqlClient.SqlConnection)
        - State: The state of the connection after disconnection (Disconnected or Closed)

        Additional properties available:
        - ConnectionString: The masked/hidden connection string used for the connection

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
                            [PSCustomObject]@{
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

                            [PSCustomObject]@{
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