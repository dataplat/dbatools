function Get-DbaOrphanUser {
    <#
        .SYNOPSIS
            Get orphaned users.
        .DESCRIPTION
            An orphan user is defined by a user that does not have their matching login. (Login property = "").
        .PARAMETER SqlInstance
            The SQL Server Instance to connect to.
        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:
            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
            To connect as a different Windows user, run PowerShell as that user.
        .PARAMETER Database
            Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.
        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.
        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.
        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
        .NOTES
            Tags: Orphan, Databases
            Author: Claudio Silva (@ClaudioESSilva)
            Author: Garry Bargsley (@gbargsley)
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
        .LINK
            https://dbatools.io/Get-DbaOrphanUser
        .EXAMPLE
            Get-DbaOrphanUser -SqlInstance localhost\sql2016
            Finds all orphan users without matching Logins in all databases present on server 'localhost\sql2016'.
        .EXAMPLE
            Get-DbaOrphanUser -SqlInstance localhost\sql2016 -SqlCredential $cred
            Finds all orphan users without matching Logins in all databases present on server 'localhost\sql2016'. SQL Server authentication will be used in connecting to the server.
        .EXAMPLE
            Get-DbaOrphanUser -SqlInstance localhost\sql2016 -Database db1
            Finds orphan users without matching Logins in the db1 database present on server 'localhost\sql2016'.
    #>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [switch][Alias('Silent')]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Write-Message -Level Warning -Message "Failed to connect to: $SqlInstance."
                continue
            }
            if ($Database.Count -eq 0) {
                $DatabaseCollection = $server.Databases | Where-Object { $_.IsSystemObject -eq $false -and $_.IsAccessible -eq $true }
            }
            else {
                if ($pipedatabase.Length -gt 0) {
                    $Source = $pipedatabase[0].parent.name
                    $DatabaseCollection = $pipedatabase.name
                }
                else {
                    $DatabaseCollection = $server.Databases | Where-Object { $_.IsSystemObject -eq $false -and $_.IsAccessible -eq $true -and ($Database -contains $_.Name) }
                }
            }
            if ($DatabaseCollection.Count -gt 0) {
                foreach ($db in $DatabaseCollection) {
                    try {
                        #if SQL 2012 or higher only validate databases with ContainmentType = NONE
                        if ($server.versionMajor -gt 10) {
                            if ($db.ContainmentType -ne [Microsoft.SqlServer.Management.Smo.ContainmentType]::None) {
                                Write-Message -Level Warning -Message "Database '$db' is a contained database. Contained databases can't have orphaned users. Skipping validation."
                                Continue
                            }
                        }
                        Write-Message -Level Verbose -Message "Validating users on database '$db'."
                        if ($Users.Count -eq 0) {
                            #the third validation will remove from list sql users without login. The rule here is Sid with length higher than 16
                            $UsersToWork = $db.Users | Where-Object { $_.Login -eq "" -and ($_.ID -gt 4) -and ($_.Sid.Length -gt 16 -and $_.LoginType -eq [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin) -eq $false }
                        }
                        else {
                            if ($pipedatabase.Length -gt 0) {
                                $Source = $pipedatabase[3].parent.name
                                $UsersToWork = $pipedatabase.name
                            }
                            else {
                                #the fourth validation will remove from list sql users without login. The rule here is Sid with length higher than 16
                                $UsersToWork = $db.Users | Where-Object { $_.Login -eq "" -and ($_.ID -gt 4) -and ($Users -contains $_.Name) -and (($_.Sid.Length -gt 16 -and $_.LoginType -eq [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin) -eq $false) }
                            }
                        }
                        if ($UsersToWork.Count -gt 0) {
                            Write-Message -Level Verbose -Message "Orphan users found"
                                [PSCustomObject]@{
                                    SqlInstance  = $server.name
                                    DatabaseName = $db.Name
                                    User         = $UsersToWork.Name
                                }
                        }
                        else {
                            Write-Message -Level Verbose -Message "No orphan users found on database '$db'."
                        }
                        #reset collection
                        $UsersToWork = $null
                    }
                    catch {
                        Stop-Function -Message $_ -Continue
                    }
                }
            }
            else {
                Write-Message -Level Verbose -Message "There are no databases to analyse."
            }
        }
    }
    end {
        Write-Message -Level Verbose -Message "Total Elapsed time: $totaltime."
    }
}