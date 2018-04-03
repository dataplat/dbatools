function Test-DbaSqlLoginWeakPassword {
    <#
        .SYNOPSIS
            Test-DbaSqlLoginWeakPassword finds any logins on SQL instance that are SQL Logins and have a password that is either null or same as the login

        .DESCRIPTION
            The purpose of this function is to find SQL Server logins that have no password or the same password as login. You can add your own password to check for or add them to a csv file.
            By default it will test for empty password and the same password as username.

        .PARAMETER SqlInstance
            The SQL Server instance you're checking logins on. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Dictionary
            Specifies a list of passwords to include in the test for weak passwords.

        .PARAMETER Path
            Specifies a csv file path of passwords to include in the test for weak passwords.
            The CSV file has no header, it should just have the passwords you want to check.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Author: Peter Samuelsson

            dWebsite: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Test-DbaSqlLoginWeakPassword

        .EXAMPLE
            Test-DbaSqlLoginWeakPassword -SqlInstance Dev01

            Test all SQL logins that the password is null or same as username on SQL server instance Dev01

        .EXAMPLE
            Test-DbaSqlLoginWeakPassword -SqlInstance Dev01 -Dictionary Test1,test2

            Test all SQL logins that the password is null, same as username or Test1,Test2 on SQL server instance Dev0
    #>
    
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [String[]]$Dictionary,
        [switch]$EnableException
    )

    begin {
        $CheckPasses = "''", "'@@Name'"
        if ($Dictionary) {
            $Dictionary | ForEach-Object {$CheckPasses += "'" + $psitem + "'" }
        }

        foreach ($CheckPass in $CheckPasses) {
            if ($CheckPasses.IndexOf($CheckPass) -eq 0) {
                $checks = "SELECT " + $CheckPass
            } else {
                $checks += "
        UNION SELECT " + $CheckPass
            }
        }

        $sql = "DECLARE @WeakPwdList TABLE(WeakPwd NVARCHAR(255))
            --Define weak password list
            --Use @@Name if users password contain their name
            INSERT INTO @WeakPwdList(WeakPwd)
            $checks

            SELECT @@SERVERNAME As ServerName,
                SysLogins.name as SqlLogin,
                REPLACE(WeakPassword.WeakPwd,'@@Name',SysLogins.name) As [Password],
                SysLogins.is_disabled as Disabled,
                SysLogins.create_date as CreatedDate,
                SysLogins.modify_date as ModifiedDate,
                SysLogins.default_database_name as DefaultDatabase
            FROM sys.sql_logins SysLogins
            INNER JOIN @WeakPwdList WeakPassword ON (PWDCOMPARE(WeakPassword.WeakPwd, password_hash) = 1
                OR PWDCOMPARE(REPLACE(WeakPassword.WeakPwd,'@@Name',SysLogins.name),password_hash) = 1)"


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
            Write-Message -Level Verbose -Message "Testing: same username as Password"
            Write-Message -Level Verbose -Message "Testing: the following Passwords $CheckPasses"
            $server.Query("$sql")

        }
    }
    end {}
}