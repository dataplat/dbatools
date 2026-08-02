function Get-DbaUnusedLogin {
    <#
    .SYNOPSIS
        Finds logins that no database user maps to and that belong to no server role

    .DESCRIPTION
        Returns the logins on an instance that nothing appears to be using, so you can review them before dropping them.

        A login is reported as unused when both of these are true:

        - No database user in any accessible database maps to the SID of the login. Users are matched on SID rather than name, so the dbo user of a database the login owns counts as a mapping and that login is not reported.
        - The login belongs to no server role. Membership of the public role is not counted, because every login belongs to public.

        SQL logins, Windows logins and groups, and the Entra ID (Azure AD) logins on SQL Server 2022 and Azure are all checked. Logins that SQL Server creates for itself are never reported, because they cannot be dropped: sa, the ## internal logins, and logins mapped to a certificate or an asymmetric key.

        Two things this command deliberately does not do, so read the results before acting on them:

        - It does not look at object ownership or at permissions granted straight to the login. A login can hold a server-level GRANT such as VIEW SERVER STATE, or own a job, an endpoint, a linked server or a credential, and still show up here. SQL Server itself refuses to drop a login that owns a database, an endpoint or a job, so Remove-DbaLogin surfaces that rather than silently breaking something.
        - It cannot see inside a database it cannot open. Databases that are offline, restoring or otherwise inaccessible are skipped with a warning, and a login mapped only in one of those is reported as unused.

        LastLogin comes from sys.dm_exec_sessions, which lists the sessions connected at this moment and nothing older. A login with a LastLogin value has a session open right now and is in use whatever the rest of the check concluded. An empty LastLogin only means the login is not connected right now, so it is not evidence that a login has never been used.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Login
        Limits the check to the specified login names instead of every login on the instance.
        Use this to confirm whether particular accounts are still in use before you decommission them.

    .PARAMETER ExcludeLogin
        Skips the specified login names. Useful for service accounts you already know are in use but that hold no role membership or database mapping, such as a monitoring account that connects and reads DMVs only.

    .PARAMETER ExcludeSystemLogin
        Excludes the built-in Windows principals that SQL Server sets up during installation, meaning the NT AUTHORITY, NT SERVICE and BUILTIN accounts.
        Use this when auditing user accounts, and leave it off when you want to spot a leftover BUILTIN\Administrators login.

    .PARAMETER Database
        Limits the search for database users to the specified databases. Accepts database names or arrays.
        Narrowing the databases also narrows what unused means, because a login mapped only in a database you left out is reported as unused.

    .PARAMETER ExcludeDatabase
        Skips the specified databases when looking for database users. Commonly used to leave out a large database that is slow to enumerate.
        The same caution applies as for Database, because a login mapped only in a database you excluded is reported as unused.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Login, Security, Audit
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaUnusedLogin

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Login

        Returns one Login object per unused login found on the specified SQL Server instance(s). The object is the SMO login itself, so it pipes straight into Remove-DbaLogin, Set-DbaLogin and Export-DbaLogin.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The login account name
        - LoginType: The type of login (SqlLogin, WindowsUser, WindowsGroup, ExternalUser or ExternalGroup)
        - CreateDate: DateTime when the login was created
        - LastLogin: DbaDateTime the login opened the session it currently holds, from sys.dm_exec_sessions (null when the login is not connected right now, or on SQL Server 2000)
        - IsDisabled: Boolean indicating if the login is disabled
        - HasAccess: Boolean indicating if the login has permission to connect

        Additional properties available:
        - SidString: Hexadecimal string representation of the Security Identifier (SID) of the login
        - UncheckedDatabase: Names of databases that could not be opened and so were not searched for database users

        All properties from the base SMO Login object are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaUnusedLogin -SqlInstance sql2016

        Returns every login on sql2016 that no database user maps to and that belongs to no server role.

    .EXAMPLE
        PS C:\> Get-DbaUnusedLogin -SqlInstance sql2016 -ExcludeSystemLogin

        Same as above, but leaves out the NT AUTHORITY, NT SERVICE and BUILTIN logins that SQL Server creates during installation.

    .EXAMPLE
        PS C:\> Get-DbaUnusedLogin -SqlInstance sql2016, sql2017 | Select-Object SqlInstance, Name, CreateDate, LastLogin

        Reviews the unused logins on two instances, showing when each was created and whether it holds a session right now.

    .EXAMPLE
        PS C:\> Get-DbaUnusedLogin -SqlInstance sql2016 -Login olduser1, olduser2

        Checks only olduser1 and olduser2, returning the ones that are unused. A login that is in use returns nothing.

    .EXAMPLE
        PS C:\> Get-DbaUnusedLogin -SqlInstance sql2016 -ExcludeSystemLogin | Remove-DbaLogin -Confirm:$false

        Drops every unused login on sql2016. Review the list first, because ownership and direct permission grants are not part of the check.

    .EXAMPLE
        PS C:\> Get-DbaUnusedLogin -SqlInstance sql2016 -ExcludeDatabase ReportingArchive

        Skips the ReportingArchive database when looking for database users. A login mapped only in that database is reported as unused.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Login,
        [string[]]$ExcludeLogin,
        [switch]$ExcludeSystemLogin,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$EnableException
    )
    begin {
        $loginTimeSql = "SELECT login_name, MAX(login_time) AS login_time FROM sys.dm_exec_sessions GROUP BY login_name"

        # The Windows principals SQL Server sets up during installation. SMO treats them as ordinary logins,
        # so IsSystemObject does not catch them and -ExcludeSystemLogin has to name them.
        $systemLoginPrefix = @(
            "NT AUTHORITY\",
            "NT SERVICE\",
            "BUILTIN\"
        )
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Only logins a DBA could actually drop are candidates. Certificate and asymmetric key logins exist to
            # sign modules, the ## logins belong to SQL Server, and sa is flagged IsSystemObject. ExternalUser and
            # ExternalGroup are the Entra ID logins that New-DbaLogin creates on SQL Server 2022 and Azure, and they
            # are dropped the same way as any other, so they belong in the audit.
            $candidateLogins = $server.Logins | Where-Object {
                $PSItem.LoginType -in "SqlLogin", "WindowsUser", "WindowsGroup", "ExternalUser", "ExternalGroup" -and
                -not $PSItem.IsSystemObject -and
                $PSItem.Name -notlike "##*"
            }

            if ($Login) {
                $candidateLogins = $candidateLogins | Where-Object Name -in $Login
            }

            if ($ExcludeLogin) {
                $candidateLogins = $candidateLogins | Where-Object Name -notin $ExcludeLogin
            }

            if ($ExcludeSystemLogin) {
                $candidateLogins = $candidateLogins | Where-Object {
                    $loginName = $PSItem.Name
                    $isBuiltIn = $false
                    # The switch is documented as excluding built-in Windows principals, so test the login type
                    # rather than trust that only a Windows login can ever carry one of these prefixes.
                    if ($PSItem.LoginType -in "WindowsUser", "WindowsGroup") {
                        foreach ($prefix in $systemLoginPrefix) {
                            if ($loginName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                                $isBuiltIn = $true
                            }
                        }
                    }
                    -not $isBuiltIn
                }
            }

            $candidateLogins = @($candidateLogins)
            if ($candidateLogins.Count -eq 0) {
                Write-Message -Level Verbose -Message "No candidate logins on $instance."
                continue
            }

            # Walking the server roles costs one round trip per role, and an instance has a fixed handful of them.
            # Walking ListMembers() on every login costs one per login, and an instance can have thousands.
            Write-Message -Level Verbose -Message "Collecting server role membership on $instance."
            # A PowerShell hashtable literal compares its keys case-insensitively. An instance with a case-sensitive
            # server collation can hold both "Bob" and "bob", and putting one of them in a role would mark the other
            # as used. Both sides of the lookup are names SQL Server gave us, so compare them ordinally.
            $roleMember = New-Object -TypeName System.Collections.Hashtable -ArgumentList 0, ([System.StringComparer]::Ordinal)
            foreach ($serverRole in $server.Roles) {
                # Every login belongs to public, so membership of it says nothing about whether a login is used.
                # EnumMemberNames() returns nothing for public anyway, but skip it so the intent is not left to chance.
                if ($serverRole.Name -eq "public") {
                    continue
                }
                foreach ($memberName in $serverRole.EnumMemberNames()) {
                    $roleMember[$memberName] = $true
                }
            }

            $databaseCollection = @($server.Databases)

            if ($Database) {
                $databaseCollection = @($databaseCollection | Where-Object Name -in $Database)

                # A typo in -Database would otherwise leave nothing to search, and every candidate login would come
                # back as unused. That is a dangerous list to hand to Remove-DbaLogin, so name what was not found.
                $missingDatabase = @($Database | Where-Object { $PSItem -notin $databaseCollection.Name })
                if ($missingDatabase.Count -gt 0) {
                    $missingDatabaseList = $missingDatabase -join ", "
                    Write-Message -Level Warning -Message "These databases were not found on $instance and so were not searched for database users: $missingDatabaseList."
                }
            }

            if ($ExcludeDatabase) {
                $databaseCollection = @($databaseCollection | Where-Object Name -notin $ExcludeDatabase)
            }

            # A login mapped only inside a database we cannot open looks unused, so say which ones were skipped
            # rather than let the caller assume the whole instance was searched.
            $uncheckedDatabase = @($databaseCollection | Where-Object { -not $PSItem.IsAccessible } | Select-Object -ExpandProperty Name)
            if ($uncheckedDatabase.Count -gt 0) {
                $uncheckedDatabaseList = $uncheckedDatabase -join ", "
                Write-Message -Level Warning -Message "These databases on $instance could not be opened and were not searched for database users, so a login mapped only there is reported as unused: $uncheckedDatabaseList."
            }

            # Matching on SID rather than on the resolved login name means the dbo user of a database the login
            # owns counts as a mapping, and a user whose login SMO cannot resolve is still matched.
            $mappedSid = New-Object -TypeName System.Collections.Hashtable -ArgumentList 0, ([System.StringComparer]::Ordinal)
            foreach ($db in ($databaseCollection | Where-Object IsAccessible)) {
                Write-Message -Level Verbose -Message "Collecting database users from $db on $instance."
                foreach ($dbUser in $db.Users) {
                    if ($dbUser.Sid -and $dbUser.Sid.Length -gt 0) {
                        $mappedSid[(Convert-ByteToHexString -InputObject $dbUser.Sid)] = $true
                    }
                }
            }

            # There is no reliable method to get last login time with SQL Server 2000, so only show on 2005+
            if ($server.VersionMajor -ge 9) {
                Write-Message -Level Verbose -Message "Getting last login times on $instance."
                $loginTimes = $server.ConnectionContext.ExecuteWithResults($loginTimeSql).Tables[0]
                # The query groups the sessions by login_name, and SQL Server groups under the server collation.
                # Matching those groups back to a login with that same comparer is what keeps the lookup below
                # unambiguous. This is the comparer Compare-DbaCollationSensitiveObject builds internally, but it
                # builds one per call, so calling the helper per login would construct a throwaway SMO Server
                # object for every login on the instance. Build it once instead.
                $loginNameComparer = (New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server).GetStringComparer($server.Collation)
            } else {
                $loginTimes = $null
                $loginNameComparer = $null
            }

            foreach ($currentLogin in $candidateLogins) {
                Write-Message -Level Verbose -Message "Processing $currentLogin on $instance."

                if ($roleMember[$currentLogin.Name]) {
                    Write-Message -Level Verbose -Message "$currentLogin belongs to a server role, skipping."
                    continue
                }

                $sidString = Convert-ByteToHexString -InputObject $currentLogin.Sid
                if ($mappedSid[$sidString]) {
                    Write-Message -Level Verbose -Message "$currentLogin is mapped to a database user, skipping."
                    continue
                }

                # Compare with the server collation rather than -eq or -ceq, because each of those gets one of
                # the two collations wrong. -eq matches the separate "Bob" and "bob" groups a case-sensitive
                # instance returns and hands the resulting two-element array to the [DbaDateTime] cast, which
                # throws and takes the whole instance down over two logins that differ only in case. -ceq misses
                # a "LAB\dba" session against a "lab\dba" login on a case-insensitive instance, which reports a
                # login someone is connected under right now as unused. Since this is the comparer SQL Server
                # grouped the rows with, at most one group can ever match and the cast always gets one value.
                $lastLogin = $null
                if ($null -ne $loginTimes) {
                    $loginTime = $loginTimes | Where-Object { $loginNameComparer.Compare($PSItem.login_name, $currentLogin.Name) -eq 0 } | Select-Object -ExpandProperty login_time
                    if ($loginTime) {
                        $lastLogin = [DbaDateTime]$loginTime
                    }
                }

                Add-Member -Force -InputObject $currentLogin -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $currentLogin -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $currentLogin -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $currentLogin -MemberType NoteProperty -Name LastLogin -Value $lastLogin
                Add-Member -Force -InputObject $currentLogin -MemberType NoteProperty -Name SidString -Value $sidString
                Add-Member -Force -InputObject $currentLogin -MemberType NoteProperty -Name UncheckedDatabase -Value $uncheckedDatabase

                Select-DefaultView -InputObject $currentLogin -Property ComputerName, InstanceName, SqlInstance, Name, LoginType, CreateDate, LastLogin, IsDisabled, HasAccess
            }
        }
    }
}
