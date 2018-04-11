function Repair-DbaOrphanUser {
    <#
        .SYNOPSIS
            Finds orphan users with existing login and remaps them.

        .DESCRIPTION
            An orphan user is defined by a user that does not have a matching login (Login property = "").

            If the matching login exists it must be:
                Enabled
                Not a system object
                Not locked
                Have the same name that user

            You can drop users that does not have their matching login by specifying the parameter -RemoveNotExisting.

        .PARAMETER SqlInstance
            The SQL Server Instance to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

        .PARAMETER Users
            Specifies the list of usernames to repair.

        .PARAMETER Force
        Forces alter schema to dbo owner so users can be dropped.

        .PARAMETER RemoveNotExisting
            If this switch is enabled, all users that do not have a matching login will be dropped from the database.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .EXAMPLE
            Repair-DbaOrphanUser -SqlInstance sql2005

            Finds and repairs all orphan users of all databases present on server 'sql2005'

        .EXAMPLE
            Repair-DbaOrphanUser -SqlInstance sqlserver2014a -SqlCredential $cred

            Finds and repair all orphan users in all databases present on server 'sqlserver2014a'. SQL credentials are used to authenticate to the server.

        .EXAMPLE
            Repair-DbaOrphanUser -SqlInstance sqlserver2014a -Database db1, db2

            Finds and repairs all orphan users in both db1 and db2 databases.

        .EXAMPLE
            Repair-DbaOrphanUser -SqlInstance sqlserver2014a -Database db1 -Users OrphanUser

            Finds and repairs user 'OrphanUser' in 'db1' database.

        .EXAMPLE
            Repair-DbaOrphanUser -SqlInstance sqlserver2014a -Users OrphanUser

            Finds and repairs user 'OrphanUser' on all databases

        .EXAMPLE
            Repair-DbaOrphanUser -SqlInstance sqlserver2014a -RemoveNotExisting

            Finds all orphan users of all databases present on server 'sqlserver2014a'. Removes all users that do not have  matching Logins.

        .NOTES
            Tags: Orphan
            Author: Claudio Silva (@ClaudioESSilva)
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Repair-DbaOrphanUser
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [object[]]$Users,
        [switch]$RemoveNotExisting,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        $start = [System.Diagnostics.Stopwatch]::StartNew()
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
                            $UsersToRemove = @()
                            foreach ($User in $UsersToWork) {
                                $ExistLogin = $server.logins | Where-Object {
                                    $_.Isdisabled -eq $False -and
                                    $_.IsSystemObject -eq $False -and
                                    $_.IsLocked -eq $False -and
                                    $_.Name -eq $User.Name
                                }

                                if ($ExistLogin) {
                                    if ($server.versionMajor -gt 8) {
                                        $query = "ALTER USER " + $User + " WITH LOGIN = " + $User
                                    }
                                    else {
                                        $query = "exec sp_change_users_login 'update_one', '$User'"
                                    }

                                    if ($Pscmdlet.ShouldProcess($db.Name, "Mapping user '$($User.Name)'")) {
                                        $server.Databases[$db.Name].ExecuteNonQuery($query) | Out-Null
                                        Write-Message -Level Verbose -Message "`r`nUser '$($User.Name)' mapped with their login."

                                        [PSCustomObject]@{
                                            SqlInstance  = $server.name
                                            DatabaseName = $db.Name
                                            User         = $User.Name
                                            Status       = "Success"
                                        }
                                    }
                                }
                                else {
                                    if ($RemoveNotExisting) {
                                        #add user to collection
                                        $UsersToRemove += $User
                                    }
                                    else {
                                        Write-Message -Level Verbose -Message "Orphan user $($User.Name) does not have matching login."
                                        [PSCustomObject]@{
                                            SqlInstance  = $server.name
                                            DatabaseName = $db.Name
                                            User         = $User.Name
                                            Status       = "No matching login"
                                        }
                                    }
                                }
                            }

                            #With the collection complete invoke remove.
                            if ($RemoveNotExisting) {
                                if ($Force) {
                                    if ($Pscmdlet.ShouldProcess($db.Name, "Remove-DbaOrphanUser")) {
                                        Write-Message -Level Verbose -Message "Calling 'Remove-DbaOrphanUser' with -Force."
                                        Remove-DbaOrphanUser -SqlInstance $sqlinstance -SqlCredential $SqlCredential -Database $db.Name -User $UsersToRemove -Force
                                    }
                                }
                                Else {
                                    If ($Pscmdlet.ShouldProcess($db.Name, "Remove-DbaOrphanUser")) {
                                    Write-Message -Level Verbose -Message "Calling 'Remove-DbaOrphanUser'."
                                    Remove-DbaOrphanUser -SqlInstance $sqlinstance -SqlCredential $SqlCredential -Database $db.Name -User $UsersToRemove
                                }
                            }
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
        $totaltime = ($start.Elapsed)
        $start.Stop()
        Write-Message -Level Verbose -Message "Total Elapsed time: $totaltime."

        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Repair-SqlOrphanUser
    }
}