function Get-DbaLogin {
    <#
    .SYNOPSIS
        Retrieves SQL Server login accounts with filtering options for security audits and access management

    .DESCRIPTION
        Returns detailed information about SQL Server login accounts, including authentication type, security status, and last login times. This function helps DBAs perform security audits by identifying locked, disabled, or expired accounts, and distinguish between Windows and SQL authentication logins. Use it to troubleshoot access issues, generate compliance reports, or review login configurations across multiple instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Login
        Specifies specific login names to retrieve instead of returning all logins from the instance.
        Use this when you need information about particular accounts for troubleshooting access issues or security audits.

    .PARAMETER ExcludeLogin
        Excludes specific login names from the results.
        Useful when you want all logins except certain service accounts or system logins that you don't need to review.

    .PARAMETER IncludeFilter
        Includes only logins matching the specified wildcard patterns (supports * and ? wildcards).
        Use this to find groups of related logins, such as all domain accounts from a specific organizational unit or service accounts with naming conventions.

    .PARAMETER ExcludeFilter
        Excludes logins matching the specified wildcard patterns (supports * and ? wildcards).
        Commonly used to filter out system accounts or built-in logins when focusing on user accounts during security reviews.

    .PARAMETER ExcludeSystemLogin
        Excludes built-in system logins like sa, BUILTIN\Administrators, and NT AUTHORITY accounts from results.
        Use this when performing user access audits where you only want to see custom logins created for applications and users.

    .PARAMETER Type
        Filters results to show only Windows Authentication logins or SQL Server Authentication logins.
        Use 'Windows' to review domain accounts and local Windows users, or 'SQL' to audit SQL Server native accounts that store passwords in the database.

    .PARAMETER Locked
        Returns only login accounts that are currently locked due to failed authentication attempts.
        Use this to identify accounts that may need to be unlocked or investigate potential security incidents.

    .PARAMETER Disabled
        Returns only login accounts that have been disabled but not dropped from the server.
        Use this to identify inactive accounts that should be reviewed for cleanup or re-enabling for returning employees.

    .PARAMETER MustChangePassword
        Returns only SQL Server logins that are flagged to change their password on next login.
        Use this to identify accounts with temporary passwords or those requiring password updates due to security policies.

    .PARAMETER HasAccess
        Returns only logins that currently have permission to connect to the SQL Server instance.
        Use this to verify which accounts can actually access the server, as some logins may exist but be denied connection rights.

    .PARAMETER Detailed
        Includes additional security-related properties like bad password count, password age, and lockout times.
        Use this for comprehensive security audits when you need detailed information about password policies and authentication failures.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Login
        Author: Mitchell Hamann (@SirCaptainMitch) | Rob Sewell (@SQLDBaWithBeard)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaLogin

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016

        Gets all the logins from server sql2016 using NT authentication and returns the SMO login objects

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -SqlCredential $sqlcred

        Gets all the logins for a given SQL Server using a passed credential object and returns the SMO login objects

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -SqlCredential $sqlcred -Login dbatoolsuser,TheCaptain

        Get specific logins from server sql2016 returned as SMO login objects.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -IncludeFilter '##*','NT *'

        Get all user objects from server sql2016 beginning with '##' or 'NT ', returned as SMO login objects.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -ExcludeLogin dbatoolsuser

        Get all user objects from server sql2016 except the login dbatoolsuser, returned as SMO login objects.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -Type Windows

        Get all user objects from server sql2016 that are Windows Logins

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -Type Windows -IncludeFilter *Rob*

        Get all user objects from server sql2016 that are Windows Logins and have Rob in the name

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -Type SQL

        Get all user objects from server sql2016 that are SQL Logins

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -Type SQL -IncludeFilter *Rob*

        Get all user objects from server sql2016 that are SQL Logins and have Rob in the name

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -ExcludeSystemLogin

        Get all user objects from server sql2016 that are not system objects

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -ExcludeFilter '##*','NT *'

        Get all user objects from server sql2016 except any beginning with '##' or 'NT ', returned as SMO login objects.

    .EXAMPLE
        PS C:\> 'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred

        Using Get-DbaLogin on the pipeline, you can also specify which names you would like with -Login.

    .EXAMPLE
        PS C:\> 'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred -Locked

        Using Get-DbaLogin on the pipeline to get all locked logins on servers sql2016 and sql2014.

    .EXAMPLE
        PS C:\> 'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred -HasAccess -Disabled

        Using Get-DbaLogin on the pipeline to get all Disabled logins that have access on servers sql2016 or sql2014.

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance sql2016 -Type SQL -Detailed

        Get all user objects from server sql2016 that are SQL Logins. Get additional info for login available from LoginProperty function

.EXAMPLE
        PS C:\> 'sql2016', 'sql2014' | Get-DbaLogin -SqlCredential $sqlcred -MustChangePassword

        Using Get-DbaLogin on the pipeline to get all logins that must change password on servers sql2016 and sql2014.
#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Login,
        [string[]]$IncludeFilter,
        [string[]]$ExcludeLogin,
        [string[]]$ExcludeFilter,
        [Alias('ExcludeSystemLogins')]
        [switch]$ExcludeSystemLogin,
        [ValidateSet('Windows', 'SQL')]
        [string]$Type,
        [switch]$HasAccess,
        [switch]$Locked,
        [switch]$Disabled,
        [switch]$MustChangePassword,
        [switch]$Detailed,
        [switch]$EnableException
    )
    begin {

        $loginTimeSql = "SELECT login_name, MAX(login_time) AS login_time FROM sys.dm_exec_sessions GROUP BY login_name"
        $loginProperty = "SELECT
                            LOGINPROPERTY ('/*LoginName*/' , 'BadPasswordCount') AS BadPasswordCount ,
                            LOGINPROPERTY ('/*LoginName*/' , 'BadPasswordTime') AS BadPasswordTime,
                            LOGINPROPERTY ('/*LoginName*/' , 'DaysUntilExpiration') AS DaysUntilExpiration,
                            LOGINPROPERTY ('/*LoginName*/' , 'HistoryLength') AS HistoryLength,
                            LOGINPROPERTY ('/*LoginName*/' , 'IsMustChange') AS IsMustChange,
                            LOGINPROPERTY ('/*LoginName*/' , 'LockoutTime') AS LockoutTime,
                            CONVERT (VARCHAR(514),  (LOGINPROPERTY('/*LoginName*/', 'PasswordHash')),1) AS PasswordHash,
                            LOGINPROPERTY ('/*LoginName*/' , 'PasswordLastSetTime') AS PasswordLastSetTime"
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -AzureUnsupported
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $serverLogins = $server.Logins

            if ($Login) {
                $serverLogins = $serverLogins | Where-Object Name -in $Login
            }

            if ($ExcludeSystemLogin) {
                $serverLogins = $serverLogins | Where-Object IsSystemObject -eq $false
            }

            if ($Type -eq 'Windows') {
                $serverLogins = $serverLogins | Where-Object LoginType -in @('WindowsUser', 'WindowsGroup')
            }

            if ($Type -eq 'SQL') {
                $serverLogins = $serverLogins | Where-Object LoginType -eq 'SqlLogin'
            }

            if ($IncludeFilter) {
                $serverLogins = $serverLogins | Where-Object {
                    foreach ($filter in $IncludeFilter) {
                        if ($_.Name -like $filter) {
                            return $true;
                        }
                    }
                }
            }

            if ($ExcludeLogin) {
                $serverLogins = $serverLogins | Where-Object Name -NotIn $ExcludeLogin
            }

            if ($ExcludeFilter) {
                foreach ($filter in $ExcludeFilter) {
                    $serverLogins = $serverLogins | Where-Object Name -NotLike $filter
                }
            }

            if ($HasAccess) {
                $serverLogins = $serverLogins | Where-Object HasAccess
            }

            if ($Locked) {
                $serverLogins = $serverLogins | Where-Object IsLocked
            }

            if ($Disabled) {
                $serverLogins = $serverLogins | Where-Object IsDisabled
            }

            if ($MustChangePassword) {
                $serverLogins = $serverLogins | Where-Object MustChangePassword
            }

            # There's no reliable method to get last login time with SQL Server 2000, so only show on 2005+
            if ($server.VersionMajor -gt 9) {
                Write-Message -Level Verbose -Message "Getting last login times"
                $loginTimes = $server.ConnectionContext.ExecuteWithResults($loginTimeSql).Tables[0]
            } else {
                $loginTimes = $null
            }

            foreach ($serverLogin in $serverLogins) {
                Write-Message -Level Verbose -Message "Processing $serverLogin on $instance"
                $loginTime = $loginTimes | Where-Object { $_.login_name -eq $serverLogin.name } | Select-Object -ExpandProperty login_time

                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name LastLogin -Value $loginTime

                if ($Detailed) {
                    $loginName = $serverLogin.name
                    $query = $loginProperty.Replace('/*LoginName*/', "$loginName")
                    $loginProperties = $server.ConnectionContext.ExecuteWithResults($query).Tables[0]
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name BadPasswordCount -Value $loginProperties.BadPasswordCount
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name BadPasswordTime -Value $loginProperties.BadPasswordTime
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name DaysUntilExpiration -Value $loginProperties.DaysUntilExpiration
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name HistoryLength -Value $loginProperties.HistoryLength
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name IsMustChange -Value $loginProperties.IsMustChange
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name LockoutTime -Value $loginProperties.LockoutTime
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name PasswordHash -Value $loginProperties.PasswordHash
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name PasswordLastSetTime -Value $loginProperties.PasswordLastSetTime
                }

                $sidString = '0x'
                foreach ($element in $serverLogin.Sid) {
                    $sidString += '{0:X2}' -f $element
                }
                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name SidString -Value $sidString

                Select-DefaultView -InputObject $serverLogin -Property ComputerName, InstanceName, SqlInstance, Name, LoginType, CreateDate, LastLogin, HasAccess, IsLocked, IsDisabled, MustChangePassword
            }
        }
    }
}