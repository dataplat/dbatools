#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Move-DbaCmsRegServer {
    <#
    .SYNOPSIS
        Moves registered servers around SQL Server Central Management Server (CMS)

    .DESCRIPTION
        Moves registered servers around SQL Server Central Management Server (CMS)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Name
        Specifies one or more reg servers to move. Name is the visible name in SSMS CMS interface (labeled Registered Server Name)

    .PARAMETER ServerName
        Specifies one or more reg servers to move. Server Name is the actual instance name (labeled Server Name)

    .PARAMETER NewGroup
        The new group. If no new group is specified, the default root will used

    .PARAMETER InputObject
        Allows results from Get-DbaCmsRegServer to be piped in

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
        https://dbatools.io/Move-DbaCmsRegServer

    .EXAMPLE
        PS C:\> Move-DbaCmsRegServer -SqlInstance sql2012 -Name 'Web SQL Cluster' -NewGroup HR\Prod

        Moves the registered server on sql2012 titled 'Web SQL Cluster' to the Prod group within the HR group

    .EXAMPLE
        PS C:\> Get-DbaCmsRegServer -SqlInstance sql2017 -Name 'Web SQL Cluster' | Move-DbaCmsRegServer -NewGroup Web

        Moves the registered server 'Web SQL Cluster' on sql2017 to the Web group, also on sql2017

    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Name,
        [string[]]$ServerName,
        [string]$NewGroup,
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
            $InputObject += Get-DbaCmsRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $Name -ServerName $ServerName

        }

        foreach ($regserver in $InputObject) {
            $parentserver = Get-RegServerParent -InputObject $regserver

            if ($null -eq $parentserver) {
                Stop-Function -Message "Something went wrong and it's hard to explain, sorry. This basically shouldn't happen." -Continue
            }

            $server = $regserver.ParentServer

            if ((Test-Bound -ParameterName NewGroup)) {
                $group = Get-DbaCmsRegServerGroup -SqlInstance $server -Group $NewGroup

                if (-not $group) {
                    Stop-Function -Message "$NewGroup not found on $server" -Continue
                }
            } else {
                $group = Get-DbaCmsRegServerGroup -SqlInstance $server -Id 1
            }

            if ($Pscmdlet.ShouldProcess($regserver.SqlInstance, "Moving $($regserver.Name) to $group")) {
                try {
                    $null = $parentserver.ServerConnection.ExecuteNonQuery($regserver.ScriptMove($group).GetScript())
                    Get-DbaCmsRegServer -SqlInstance $server -Name $regserver.Name -ServerName $regserver.ServerName
                    $parentserver.ServerConnection.Disconnect()
                } catch {
                    Stop-Function -Message "Failed to move $($regserver.Name) to $NewGroup on $($regserver.SqlInstance)" -ErrorRecord $_ -Continue
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Move-DbaRegisteredServer
    }
}