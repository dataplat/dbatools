function Get-DbaDbccUserOption {
    <#
    .SYNOPSIS
        Retrieves current session-level SET options and connection settings from SQL Server instances

    .DESCRIPTION
        Executes DBCC USEROPTIONS against SQL Server instances to display current session settings including ANSI options, isolation levels, date formats, language, and timeout values. This is particularly useful when troubleshooting application connection issues or verifying that session-level defaults match across environments. You can filter results to specific options or retrieve all current settings to compare against expected configurations during deployments or performance investigations.

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-useroptions-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Option
        Filters results to show only specific session options instead of all DBCC USEROPTIONS output. Use this when troubleshooting specific connection settings like ANSI options, date formats, or isolation levels without seeing the full list of 13 available options.
        Accepts any values in set 'ansi_null_dflt_on', 'ansi_nulls', 'ansi_padding', 'ansi_warnings', 'arithabort', 'concat_null_yields_null', 'datefirst', 'dateformat', 'isolation level', 'language', 'lock_timeout', 'quoted_identifier', 'textsize'

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        System.Management.Automation.PSCustomObject

        Returns one object per session option returned by DBCC USEROPTIONS. If the -Option parameter is specified, only matching options are returned.

        Default display properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name (service name)
        - SqlInstance: The full SQL Server instance name in the format ComputerName\InstanceName or just the computer name for the default instance
        - Option: The name of the session option (e.g., ansi_nulls, dateformat, isolation level)
        - Value: The current value or setting of the option

    .NOTES
        Tags: DBCC
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbccUserOption

    .EXAMPLE
        PS C:\> Get-DbaDbccUserOption -SqlInstance Server1

        Get results of DBCC USEROPTIONS for Instance Server1

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaDbccUserOption

        Get results of DBCC USEROPTIONS for Instances Sql1 and Sql2/sqlexpress

    .EXAMPLE
        PS C:\> $cred = Get-Credential sqladmin
        PS C:\> Get-DbaDbccUserOption -SqlInstance Server1 -SqlCredential $cred

        Connects using sqladmin credential and gets results of DBCC USEROPTIONS for Instance Server1

    .EXAMPLE
        PS C:\> Get-DbaDbccUserOption -SqlInstance Server1 -Option ansi_nulls, ansi_warnings, datefirst

        Gets results of DBCC USEROPTIONS for Instance Server1. Only display results for the options ansi_nulls, ansi_warnings, datefirst

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet('ansi_null_dflt_on', 'ansi_nulls', 'ansi_padding', 'ansi_warnings', 'arithabort', 'concat_null_yields_null', 'datefirst', 'dateformat', 'isolation level', 'language', 'lock_timeout', 'quoted_identifier', 'textsize')]
        [string[]]$Option,
        [switch]$EnableException
    )
    begin {
        $stringBuilder = New-Object System.Text.StringBuilder
        $null = $stringBuilder.Append("DBCC USEROPTIONS WITH NO_INFOMSGS")
    }
    process {
        $query = $StringBuilder.ToString()

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                Write-Message -Message "Query to run: $query" -Level Verbose
                $results = $server.Query($query)
            } catch {
                Stop-Function -Message "Failure running $query against $instance" -ErrorRecord $_ -Target $server -Continue
            }
            foreach ($row in $results) {
                if ((Test-Bound -Not -ParameterName Option) -or ($row[0] -in $Option)) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Option       = $row[0]
                        Value        = $row[1]
                    }
                }
            }
        }
    }
}