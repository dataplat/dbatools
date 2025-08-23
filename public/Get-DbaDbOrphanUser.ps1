function Get-DbaDbOrphanUser {
    <#
    .SYNOPSIS
        Get orphaned users.

    .DESCRIPTION
        An orphan user is defined by a user that does not have their matching login. (Login property = "").

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to check for orphaned users. Accepts database names, wildcards, or arrays.
        Use this when you need to focus the orphaned user search on specific databases rather than checking all databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip when checking for orphaned users. Useful for excluding system databases or databases under maintenance.
        Commonly used to exclude tempdb, distribution, or databases where orphaned users are expected and acceptable.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Orphan, Database, User, Login
        Author: Claudio Silva (@ClaudioESSilva) | Garry Bargsley (@gbargsley) | Simone Bizzotto (@niphlod)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbOrphanUser

    .EXAMPLE
        PS C:\> Get-DbaDbOrphanUser -SqlInstance localhost\sql2016

        Finds all orphan users without matching Logins in all databases present on server 'localhost\sql2016'.

    .EXAMPLE
        PS C:\> Get-DbaDbOrphanUser -SqlInstance localhost\sql2016 -SqlCredential $cred

        Finds all orphan users without matching Logins in all databases present on server 'localhost\sql2016'. SQL Server authentication will be used in connecting to the server.

    .EXAMPLE
        PS C:\> Get-DbaDbOrphanUser -SqlInstance localhost\sql2016 -Database db1

        Finds orphan users without matching Logins in the db1 database present on server 'localhost\sql2016'.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $DatabaseCollection = $server.Databases | Where-Object IsAccessible

            if ($Database) {
                $DatabaseCollection = $DatabaseCollection | Where-Object Name -In $Database
            }
            if ($ExcludeDatabase) {
                $DatabaseCollection = $DatabaseCollection | Where-Object Name -NotIn $ExcludeDatabase
            }

            if ($DatabaseCollection.Count -gt 0) {
                foreach ($db in $DatabaseCollection) {
                    try {
                        Write-Message -Level Verbose -Message "Validating users on database '$db'."
                        $UsersToWork = @()
                        $UsersToWork += $db.Users | Where-Object { ($_.Login -eq "") -and ($_.ID -gt 4) -and ($_.Sid.Length -eq 16) -and ($_.LoginType -in 'SqlLogin', 'Certificate') }
                        $UsersToWork += $db.Users | Where-Object { ($_.Login -notin $server.Logins.Name) -and ($_.ID -gt 4) -and ($_.Sid.Length -gt 16 -and $_.LoginType -in 'WindowsUser', 'WindowsGroup') }
                        if ($UsersToWork.Count -gt 0) {
                            Write-Message -Level Verbose -Message "Orphan users found"
                            foreach ($user in $UsersToWork) {
                                [PSCustomObject]@{
                                    ComputerName = $server.ComputerName
                                    InstanceName = $server.ServiceName
                                    SqlInstance  = $server.DomainInstanceName
                                    DatabaseName = $db.Name
                                    User         = $user.Name
                                    SmoUser      = $user
                                } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, DatabaseName, User
                            }
                        } else {
                            Write-Message -Level Verbose -Message "No orphan users found on database '$db'."
                        }
                        #reset collection
                        $UsersToWork = $null
                    } catch {
                        Stop-Function -Message $_ -Continue
                    }
                }
            } else {
                Write-Message -Level VeryVerbose -Message "There are no databases to analyse."
            }
        }
    }
}