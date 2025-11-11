function Test-DbaLoginPassword {
    <#
    .SYNOPSIS
        Identifies SQL Server logins with weak passwords including empty, username-matching, or dictionary-based passwords

    .DESCRIPTION
        Tests SQL Server authentication logins for common weak password patterns using the PWDCOMPARE() function to validate password hashes stored in sys.sql_logins. This security audit function helps identify authentication vulnerabilities by checking for empty passwords, passwords that match the username, and passwords from a custom dictionary you provide. Use this during security reviews to find logins that could be easily compromised and require immediate password changes.

    .PARAMETER SqlInstance
        The SQL Server instance you're checking logins on. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

        $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

        Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

        To connect as a different Windows user, run PowerShell as that user.

    .PARAMETER Dictionary
        Specifies additional passwords to test against all SQL authentication logins using PWDCOMPARE().
        Use this to check for organization-specific weak passwords like company names, common words, or previously breached passwords.
        These passwords are tested in addition to the default checks for empty passwords and username-matching passwords.

    .PARAMETER Login
        Specifies which SQL authentication logins to test for weak passwords instead of testing all SQL logins on the instance.
        Accepts single login names, arrays of login names, or wildcard patterns for filtering specific accounts.
        Useful when you want to focus testing on high-privilege logins or specific service accounts that need immediate attention.

    .PARAMETER InputObject
        Accepts login objects from Get-DbaLogin to test for weak passwords, enabling pipeline operations and complex filtering scenarios.
        Use this when you need to filter logins by properties like creation date, last login time, or server roles before testing passwords.
        Commonly used with Get-DbaLogin to test logins across multiple servers or with specific criteria that can't be achieved with the Login parameter alone.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Login
        Author: Peter Samuelsson

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaLoginPassword

    .EXAMPLE
        PS C:\> Test-DbaLoginPassword -SqlInstance Dev01

        Test all SQL logins that the password is null or same as username on SQL server instance Dev01

    .EXAMPLE
        PS C:\> Test-DbaLoginPassword -SqlInstance Dev01 -Login sqladmin

        Test the 'sqladmin' SQL login that the password is null or same as username on SQL server instance Dev01

    .EXAMPLE
        PS C:\> Test-DbaLoginPassword -SqlInstance Dev01 -Dictionary Test1,test2

        Test all SQL logins that the password is null, same as username or Test1,Test2 on SQL server instance Dev0

    .EXAMPLE
        PS C:\> Get-DbaLogin -SqlInstance "sql2017","sql2016" | Test-DbaLoginPassword

        Test all logins on sql2017 and sql2016

    .EXAMPLE
        PS C:\> $servers | Get-DbaLogin | Out-GridView -PassThru | Test-DbaLoginPassword

        Test selected logins on all servers in the $servers variable

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [String[]]$Login,
        [String[]]$Dictionary,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Login[]]$InputObject,
        [switch]$EnableException
    )

    begin {

        function Split-ArrayInChunks {
            param(
                [object[]] $source,
                [int] $size = 1
            )
            $chunkCount = [Math]::Ceiling($source.Count / $size)
            0 .. ($chunkCount - 1) | ForEach-Object {
                $startIndex = $_ * $size
                $endIndex = [Math]::Min(($_ + 1) * $size, $source.Count)
                , $source[$startIndex .. ($endIndex - 1)]
            }
        }

        $maxBatch = 200

        $CheckPasses = "", "@@Name"
        if ($Dictionary) {
            $Dictionary | ForEach-Object { $CheckPasses += $PSItem }
        }

        $sqlStart = "DECLARE @WeakPwdList TABLE(WeakPwd NVARCHAR(255))
                --Define weak password list
                --Use @@Name if users password contain their name
                INSERT INTO @WeakPwdList(WeakPwd)
                VALUES (NULL)"

        $sqlEnd = "
                SELECT SERVERPROPERTY('MachineName') AS [ComputerName],
                    ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                    SERVERPROPERTY('ServerName') AS [SqlInstance],
                    SysLogins.name AS SqlLogin,
                    WeakPassword = 'True',
                    REPLACE(WeakPassword.WeakPwd,'@@Name',SysLogins.name) AS [Password],
                    SysLogins.is_disabled AS Disabled,
                    SysLogins.create_date AS CreatedDate,
                    SysLogins.modify_date AS ModifiedDate,
                    SysLogins.default_database_name AS DefaultDatabase
                FROM sys.sql_logins SysLogins
                INNER JOIN @WeakPwdList WeakPassword
                ON PWDCOMPARE(REPLACE(WeakPassword.WeakPwd,'@@Name',SysLogins.name),password_hash) = 1
                "
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $InputObject += Get-DbaLogin -SqlInstance $server -Login $Login
        }

        $logins += $InputObject
    }
    end {
        $servers = $logins | Select-Object -Unique -ExpandProperty Parent

        foreach ($serverinstance in $servers) {
            Write-Message -Level Verbose -Message "Testing: same username as Password"
            Write-Message -Level Verbose -Message "Testing: the following Passwords $CheckPasses"
            try {
                $checkParts = , (Split-ArrayInChunks -source $CheckPasses -size $maxBatch)

                $loopIndex = 0

                foreach ($batch in $checkParts) {
                    $thisBatch = $sqlStart
                    $sqlParams = @{ }
                    foreach ($piece in $batch) {
                        $loopIndex += 1
                        $paramKey = "@p_$loopIndex"
                        $sqlParams[$paramKey] = $piece
                        $thisBatch += ", ($paramKey)"
                    }
                    $thisBatch += $sqlEnd
                    Write-Message -Level Debug -Message "sql: $thisBatch"
                    Invoke-DbaQuery -SqlInstance $serverinstance -Query $thisBatch -SqlParameter $sqlParams
                }

            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $serverinstance -Continue
            }
        }
    }
}