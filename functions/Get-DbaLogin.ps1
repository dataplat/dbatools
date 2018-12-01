function Get-DbaLogin {
    <#
    .SYNOPSIS
        Function to get an SMO login object of the logins for a given SQL Server instance. Takes a server object from the pipeline.

    .DESCRIPTION
        The Get-DbaLogin function returns an SMO Login object for the logins passed, if there are no users passed it will return all logins.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

    .PARAMETER Login
        The login(s) to process - this list is auto-populated from the server. If unspecified, all logins will be processed.

    .PARAMETER ExcludeLogin
        The login(s) to exclude - this list is auto-populated from the server

    .PARAMETER IncludeFilter
        A list of logins to include - accepts wildcard patterns

    .PARAMETER ExcludeFilter
        A list of logins to exclude - accepts wildcard patterns

    .PARAMETER ExcludeSystemLogin
        A Switch to remove System Logins from the output.

    .PARAMETER Type
        Filters logins by their type. Valid options are Windows and SQL.

    .PARAMETER Locked
        A Switch to return locked Logins.

    .PARAMETER Disabled
        A Switch to return disabled Logins.

    .PARAMETER SqlLogins
        Deprecated. Please use -Type SQL

    .PARAMETER WindowsLogins
        Deprecated. Please use -Type Windows.

    .PARAMETER HasAccess
        A Switch to return Logins that have access to the instance of SQL Server.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Login, Security
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

#>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Login,
        [object[]]$IncludeFilter,
        [object[]]$ExcludeLogin,
        [object[]]$ExcludeFilter,
        [Alias('ExcludeSystemLogins')]
        [switch]$ExcludeSystemLogin,
        [ValidateSet('Windows', 'SQL')]
        [string]$Type,
        [switch]$HasAccess,
        [switch]$SqlLogins,
        [switch]$WindowsLogins,
        [switch]$Locked,
        [switch]$Disabled,
        [switch]$EnableException
    )
    begin {
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter SQLLogins
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter WindowsLogins

        if ($SQLLogins) {
            $Type = "SQL"
        }
        if ($WindowsLogins) {
            $Type = "Windows"
        }
    }
    process {
        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
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
                $serverLogins = $serverLogins | Where-Object LoginType -eq 'WindowsUser'
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

            foreach ($serverLogin in $serverlogins) {
                Write-Message -Level Verbose -Message "Processing $serverLogin on $instance"

                if ($server.VersionMajor -gt 9) {
                    # There's no reliable method to get last login time with SQL Server 2000, so only show on 2005+
                    Write-Message -Level Verbose -Message "Getting last login time"
                    $sql = "SELECT MAX(login_time) AS [login_time] FROM sys.dm_exec_sessions WHERE login_name = '$($serverLogin.name)'"
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name LastLogin -Value $server.ConnectionContext.ExecuteScalar($sql)
                } else {
                    Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name LastLogin -Value $null
                }

                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $serverLogin -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName

                Select-DefaultView -InputObject $serverLogin -Property ComputerName, InstanceName, SqlInstance, Name, LoginType, CreateDate, LastLogin, HasAccess, IsLocked, IsDisabled
            }
        }
    }
}
