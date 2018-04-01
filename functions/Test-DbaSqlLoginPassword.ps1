function Test-DbaSqlLoginPassword {
    <#
        .SYNOPSIS
            Test-DbaSqlLoginPassword finds any logins on SQL instance that are SQL Logins and have a password that is either null or same as the login

        .DESCRIPTION
            The purpose of this function is to find SQL Server logins that are used by active directory users that are either disabled or removed from the domain. It allows you to keep your logins accurate and up to date by removing accounts that are no longer needed.

        .PARAMETER SqlInstance
            The SQL Server instance you're checking logins on. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Login
            Specifies a list of logins to include in the results. Options for this list are auto-populated from the server.

        .PARAMETER ExcludeLogin
            Specifies a list of logins to exclude from the results. Options for this list are auto-populated from the server.

        .PARAMETER FilterBy
            Specifies the object types to return. By default, both Logins and Groups are returned. Valid options for this parameter are 'GroupsOnly' and 'LoginsOnly'.

        .PARAMETER IgnoreDomains
            Specifies a list of Active Directory domains to ignore. By default, all domains in the forest as well as all trusted domains are traversed.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Stephen Bennett: https://sqlnotesfromtheunderground.wordpress.com/
            Author: Chrissy LeMaire (@cl), netnerds.net

            dWebsite: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Test-DbaSqlLoginPassword

        .EXAMPLE
            Test-DbaSqlLoginPassword -SqlInstance Dev01

            Tests all logins in the current Active Directory domain that are either disabled or do not exist on the SQL Server instance Dev01

        .EXAMPLE
            Test-DbaSqlLoginPassword -SqlInstance Dev01 -FilterBy GroupsOnly | Select-Object -Property *

            Tests all Active Directory groups that have logins on Dev01, and shows all information for those logins

        .EXAMPLE
            Test-DbaSqlLoginPassword -SqlInstance Dev01 -IgnoreDomains testdomain

            Tests all Domain logins excluding any that are from the testdomain

    #>
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$NoPassword,
        [switch]$PasswordAsLogin,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter Detailed

        $sql = "SELECT name as SqlLogin,
                                is_disabled as Disabled,
                                create_date as CreatedDate,
                                modify_date as ModifiedDate,
                                default_database_name as DefaultDatabase
                FROM master.sys.sql_logins"
        if ($NoPassword) {
            $sql += " WHERE PWDCOMPARE('',password_hash)=1"
        } elseif ($PasswordAsLogin) {
            $sql += " WHERE PWDCOMPARE(name,password_hash)=1"
        } else {
            $sql += " WHERE PWDCOMPARE(name,password_hash)=1 or PWDCOMPARE('',password_hash)=1"
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
                Write-Message -Message "Connected to: $instance." -Level Verbose
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            if ($Server.VersionMajor -lt 10) {
                throw "PWDCOMPARE is only supported on sql 2008 and up. Quitting."
            }
            Write-Message -Level Debug -Message "Executing $sql"
            $server.Query("$sql")
        }
    }
    end {}
}