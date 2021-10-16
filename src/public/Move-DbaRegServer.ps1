function Move-DbaRegServer {
    <#
    .SYNOPSIS
        Moves registered servers around SQL Server Central Management Server (CMS). Local Registered Servers not currently supported.

    .DESCRIPTION
        Moves registered servers around SQL Server Central Management Server (CMS). Local Registered Servers not currently supported.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        Specifies one or more reg servers to move. Name is the visible name in SSMS CMS interface (labeled Registered Server Name)

    .PARAMETER ServerName
        Specifies one or more reg servers to move. Server Name is the actual instance name (labeled Server Name)

    .PARAMETER Group
        The new group. If no new group is specified, the default root will used

    .PARAMETER InputObject
        Allows results from Get-DbaRegServer to be piped in

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