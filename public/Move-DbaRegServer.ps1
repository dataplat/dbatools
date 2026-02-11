function Move-DbaRegServer {
    <#
    .SYNOPSIS
        Moves registered servers between groups within SQL Server Central Management Server (CMS)

    .DESCRIPTION
        Moves registered server entries from one group to another within Central Management Server hierarchy. This helps reorganize CMS structure when server roles change or you need to restructure your server groupings for better management. The function updates the CMS database to reflect the new group membership while preserving all server connection details and properties.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Specifies one or more registered servers to move by their display name as shown in SSMS CMS interface. This is the friendly name you see in the registered servers tree, which may differ from the actual server instance name.
        Use this when you know the descriptive name assigned to servers in CMS but not necessarily their technical instance names.

    .PARAMETER ServerName
        Specifies one or more registered servers to move by their actual SQL Server instance name. This is the technical server\instance connection string used to connect to SQL Server.
        Use this when you need to target servers by their network instance names rather than their CMS display names.

    .PARAMETER Group
        Specifies the destination group where the registered servers will be moved. Use backslash notation for nested groups like 'Production\WebServers'.
        If not specified, servers are moved to the root level of the CMS hierarchy. The target group must already exist in CMS.

    .PARAMETER InputObject
        Accepts registered server objects from the pipeline, typically from Get-DbaRegServer output. This allows you to filter servers first and then move the results.
        Use this approach when you need complex filtering or when working with servers from multiple CMS instances.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: RegisteredServer, CMS
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Move-DbaRegServer

    .OUTPUTS
        Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer

        Returns one RegisteredServer object per registered server that was successfully moved to the new group. Each object is returned via Get-DbaRegServer and represents the updated server registration after the move operation completes.

        Default display properties (via Select-DefaultView in Get-DbaRegServer):
        - Name: The display name of the registered server in CMS
        - ServerName: The actual SQL Server instance name (connection string)
        - Group: The group path where the registered server is now located
        - Description: The description of the registered server
        - Source: The source of the registration (e.g., Central Management Servers)

    .EXAMPLE
        PS C:\> Move-DbaRegServer -SqlInstance sql2012 -Name 'Web SQL Cluster' -Group HR\Prod

        Moves the registered server on sql2012 titled 'Web SQL Cluster' to the Prod group within the HR group

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2017 -Name 'Web SQL Cluster' | Move-DbaRegServer -Group Web

        Moves the registered server 'Web SQL Cluster' on sql2017 to the Web group, also on sql2017

    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Name,
        [string[]]$ServerName,
        [Alias("NewGroup")]
        [string]$Group,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        if ((Test-Bound -ParameterName SqlInstance) -and (Test-Bound -Not -ParameterName Name) -and (Test-Bound -Not -ParameterName ServerName)) {
            Stop-Function -Message "Name or ServerName must be specified when using -SqlInstance"
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $Name -ServerName $ServerName
        }

        foreach ($regserver in $InputObject) {
            $parentserver = Get-RegServerParent -InputObject $regserver

            if ($null -eq $parentserver) {
                Stop-Function -Message "Something went wrong and it's hard to explain, sorry. This basically shouldn't happen." -Continue
            }

            $server = $regserver.ParentServer

            if ((Test-Bound -ParameterName Group)) {
                $movetogroup = Get-DbaRegServerGroup -SqlInstance $server -Group $Group

                if (-not $movetogroup) {
                    Stop-Function -Message "$Group not found on $server" -Continue
                }
            } else {
                $movetogroup = Get-DbaRegServerGroup -SqlInstance $server -Id 1
            }

            if ($Pscmdlet.ShouldProcess($regserver.SqlInstance, "Moving $($regserver.Name) to $movetogroup")) {
                try {
                    $null = $parentserver.ServerConnection.ExecuteNonQuery($regserver.ScriptMove($movetogroup).GetScript())
                    Get-DbaRegServer -SqlInstance $server -Name $regserver.Name -ServerName $regserver.ServerName
                    $parentserver.ServerConnection.Disconnect()
                } catch {
                    Stop-Function -Message "Failed to move $($regserver.Name) to $Group on $($regserver.SqlInstance)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}