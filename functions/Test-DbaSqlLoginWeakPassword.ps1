function Test-DbaSqlLoginWeakPassword {
    <#
    .SYNOPSIS
    Test-DbaSqlLoginWeakPassword returns SQL logins that has password to null or same as login

    .DESCRIPTION

    .PARAMETER SqlInstance
    SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
    Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
    $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
    To connect as a different Windows user, run PowerShell as that user.


    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
    Original Author: Sander Stad (@sqlstad, sqlstad.nl)
    Tags: LogShipping

    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: MIT https://opensource.org/licenses/MIT

    .LINK
    https://dbatools.io/Test-DbaSqlLoginWeakPassword

    .EXAMPLE
    Test-DbaSqlLoginWeakPassword -SqlInstance sql1

#>

    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {

        # Setup the query
        [string]$query = "
SELECT SERVERPROPERTY('machinename')
AS 'Server Name',
ISNULL(SERVERPROPERTY ('instancename'),
SERVERPROPERTY ('machinename')) AS 'Instance Name',
name AS 'Login With Password Equal to Login Name',
is_disabled,
create_date,
modify_date
FROM master.sys.sql_logins
WHERE PWDCOMPARE(name,password_hash)=1
ORDER BY name"
    }

    process {
        foreach ($instance in $sqlinstance) {
            # Try connecting to the instance
            Write-Message -Message "Attempting to connect to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}