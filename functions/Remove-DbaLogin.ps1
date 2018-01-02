function Remove-DbaLogin {
    <#
.SYNOPSIS
Drops a Login

.DESCRIPTION
Tries a bunch of different ways to remove a Login or two or more.

.PARAMETER SqlInstance
The SQL Server instance holding the Logins to be removed.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

.PARAMETER SqlCredential
Allows you to login to servers using alternative credentials.

.PARAMETER Login
The Login(s) to process - this list is auto-populated from the server. If unspecified, all Logins will be processed.

.PARAMETER LoginCollection
A collection of Logins (such as returned by Get-DbaLogin), to be removed.

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: Delete, Logins

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Remove-DbaLogin

.EXAMPLE
Remove-DbaLogin -SqlInstance sql2016 -Login mylogin

Prompts then removes the Login mylogin on SQL Server sql2016

.EXAMPLE
Remove-DbaLogin -SqlInstance sql2016 -Login mylogin, yourlogin

Prompts then removes the Logins mylogin and yourlogin on SQL Server sql2016

.EXAMPLE
Remove-DbaLogin -SqlInstance sql2016 -Login mylogin -Confirm:$false

Does not prompt and swiftly removes mylogin on SQL Server sql2016

.EXAMPLE
Get-DbaLogin -SqlInstance server\instance -Login yourlogin | Remove-DbaLogin

removes mylogin on SQL Server server\instance

#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = "Default")]
    Param (
        [parameter( , Mandatory, ParameterSetName = "instance")]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [parameter(Mandatory = $false)]
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [parameter(Mandatory, ParameterSetName = "instance")]
        [object[]]$Login,
        [Parameter(ValueFromPipeline, Mandatory, ParameterSetName = "Logins")]
        [Microsoft.SqlServer.Management.Smo.Login[]]$LoginCollection,
        [switch]$EnableException
    )

    process {

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $Logincollection += $server.Logins | Where-Object { $_.Name -in $Login }
        }

        foreach ($currentlogin in $Logincollection) {
            try {
                $server = $currentlogin.Parent
                if ($Pscmdlet.ShouldProcess("$currentlogin on $server", "KillLogin")) {
                    $currentlogin.Drop()

                    [pscustomobject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Login        = $currentlogin.name
                        Status       = "Dropped"
                    }
                }
            }
            catch {
                [pscustomobject]@{
                    ComputerName = $server.NetName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Login        = $currentlogin.name
                    Status       = $_
                }
                Stop-Function -Message "Could not drop Login $currentlogin on $server" -ErrorRecord $_ -Target $currentlogin -Continue
            }
        }
    }
}