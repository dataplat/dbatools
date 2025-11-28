function Remove-DbaLogin {
    <#
    .SYNOPSIS
        Removes SQL Server logins from target instances

    .DESCRIPTION
        Removes one or more SQL Server logins from specified instances using the SMO Drop() method. This function handles the complete removal process including dependency checks and provides proper error handling when logins cannot be dropped due to existing sessions or database ownership. Use the -Force parameter to automatically terminate active sessions associated with the login before removal, which is useful when cleaning up test environments or decommissioning user accounts.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Allows you to login to servers using alternative credentials.

    .PARAMETER Login
        Specifies the SQL Server login names to remove from the target instance. Accepts multiple login names as an array.
        Use this when you know the specific logins to delete, such as when cleaning up test accounts or decommissioned user logins.

    .PARAMETER InputObject
        Accepts login objects piped from Get-DbaLogin or other dbatools functions that return SQL Server login objects.
        Use this for advanced filtering scenarios or when chaining multiple dbatools commands together in a pipeline.

    .PARAMETER Force
        Automatically terminates any active database connections and sessions associated with the login before attempting removal.
        Use this when you need to forcibly remove logins that have active sessions, common in development environments or during emergency cleanup.

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
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $foundLogins = $server.Logins | Where-Object { $_.Name -in $Login }
            $foundLoginNames = $foundLogins.Name
            foreach ($requestedLogin in $Login) {
                if ($requestedLogin -notin $foundLoginNames) {
                    Write-Message -Level Warning -Message "Login '$requestedLogin' not found on instance $instance"
                }
            }
            $InputObject += $foundLogins
        }

        foreach ($currentlogin in $InputObject) {
            try {
                $server = $currentlogin.Parent
                if ($Pscmdlet.ShouldProcess("$currentlogin on $server", "KillLogin")) {
                    if ($force) {
                        $null = Stop-DbaProcess -SqlInstance $server -Login $currentlogin.name
                    }

                    $currentlogin.Drop()

                    Remove-TeppCacheItem -SqlInstance $server -Type login -Name $currentlogin.name

                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Login        = $currentlogin.name
                        Status       = "Dropped"
                    }
                }
            } catch {
                [PSCustomObject]@{
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