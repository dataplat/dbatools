function Remove-DbaLogin {
    <#
    .SYNOPSIS
        Drops a Login

    .DESCRIPTION
        Tries a bunch of different ways to remove a Login or two or more.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Allows you to login to servers using alternative credentials.

    .PARAMETER Login
        The Login(s) to process - this list is auto-populated from the server. If unspecified, all Logins will be processed.

    .PARAMETER InputObject
        A collection of Logins (such as returned by Get-DbaLogin), to be removed.

    .PARAMETER Force
        Kills any sessions associated with the login prior to drop

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Delete, Login
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaLogin

    .EXAMPLE
        PS C:\> Remove-DbaLogin -SqlInstance sql2016 -Login mylogin

        Prompts then removes the Login mylogin on SQL Server sql2016

    .EXAMPLE
        PS C:\> Remove-DbaLogin -SqlInstance sql2016 -Login mylogin, yourlogin

        Prompts then removes the Logins mylogin and yourlogin on SQL Server sql2016

    .EXAMPLE
        PS C:\> Remove-DbaLogin -SqlInstance sql2016 -Login mylogin -Confirm:$false

        Does not prompt and swiftly removes mylogin on SQL Server sql2016

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance server\instance -Login yourlogin | Remove-DbaLogin

        Removes mylogin on SQL Server server\instance

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ParameterSetName = "instance")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory, ParameterSetName = "instance")]
        [string[]]$Login,
        [Parameter(ValueFromPipeline, Mandatory, ParameterSetName = "Logins")]
        [Microsoft.SqlServer.Management.Smo.Login[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $InputObject += $server.Logins | Where-Object { $_.Name -in $Login }
        }

        foreach ($currentlogin in $InputObject) {
            try {
                $server = $currentlogin.Parent
                if ($Pscmdlet.ShouldProcess("$currentlogin on $server", "KillLogin")) {
                    if ($force) {
                        $null = Stop-DbaProcess -SqlInstance $server -Login $currentlogin.name
                    }

                    $currentlogin.Drop()

                    [pscustomobject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Login        = $currentlogin.name
                        Status       = "Dropped"
                    }
                }
            } catch {
                [pscustomobject]@{
                    ComputerName = $server.ComputerName
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