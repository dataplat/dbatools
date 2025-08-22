function Get-DbaDbccHelp {
    <#
    .SYNOPSIS
        Retrieves syntax help and parameter information for DBCC commands

    .DESCRIPTION
        Executes DBCC HELP against SQL Server to display syntax, parameters, and usage information for Database Console Commands. This saves you from having to look up DBCC command syntax in documentation, especially for complex commands like CHECKDB, CHECKTABLE, or SHRINKFILE. Supports both documented and undocumented DBCC commands when used with the IncludeUndocumented parameter.

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-help-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Statement
        Is the name of the DBCC command for which to receive syntax information.
        Provide only the part of the DBCC command that follows DBCC,
            for example, CHECKDB instead of DBCC CHECKDB.

    .PARAMETER IncludeUndocumented
        Allows getting help for undocumented DBCC commands. Requires Traceflag 2588
        This only works for SQL Server 2005 or Higher

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DBCC
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbccHelp

    .EXAMPLE
        PS C:\> Get-DbaDbccHelp -SqlInstance SQLInstance -Statement FREESYSTEMCACHE -Verbose | Format-List

        Runs the command DBCC HELP(FREESYSTEMCACHE) WITH NO_INFOMSGS against the SQLInstance SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaDbccHelp -SqlInstance SQLInstance -Statement WritePage -IncludeUndocumented | Format-List

        Sets Trace Flag 2588 on for the session and then runs the command DBCC HELP(WritePage) WITH NO_INFOMSGS against the SQLInstance SQL Server instance.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Statement,
        [switch]$IncludeUndocumented,
        [switch]$EnableException
    )
    begin {
        if (Test-Bound -Not -ParameterName Statement) {
            Stop-Function -Message "You must specify a value for Statement"
            return
        }
        $stringBuilder = New-Object System.Text.StringBuilder

        if (Test-Bound -ParameterName IncludeUndocumented) {
            $null = $stringBuilder.Append("DBCC TRACEON (2588) WITH NO_INFOMSGS;")
        }

        Write-Message -Message "Get Help Information for $Statement" -Level Verbose
        $null = $stringBuilder.Append("DBCC HELP($Statement) WITH NO_INFOMSGS;")
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                $query = $StringBuilder.ToString()
                Write-Message -Message "Query to run: $query" -Level Verbose
                $results = $server | Invoke-DbaQuery  -Query $query -MessagesToOutput

            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
            }

            [PSCustomObject]@{
                Operation = $Statement
                Cmd       = "DBCC HELP($Statement)"
                Output    = $results
            }

        }
    }
}
