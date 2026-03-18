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
        Specifies the DBCC command name to get syntax help for. Provide only the command portion after "DBCC" (e.g., CHECKDB, CHECKTABLE, SHRINKFILE).
        Use this when you need to verify command syntax before running maintenance operations or troubleshooting database issues.
        Common commands include CHECKDB for database integrity, SHRINKFILE for file management, or FREEPROCCACHE for memory management.

    .PARAMETER IncludeUndocumented
        Enables access to help for undocumented DBCC commands by setting trace flag 2588 for the session.
        Use this when troubleshooting advanced scenarios that require undocumented commands like WRITEPAGE or PAGE.
        Only works on SQL Server 2005 and higher, and should be used with caution as undocumented commands can affect system stability.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance containing the DBCC help information.

        Properties:
        - Operation: The DBCC command name specified in the Statement parameter (e.g., "CHECKDB", "SHRINKFILE")
        - Cmd: The complete DBCC command executed against SQL Server (e.g., "DBCC HELP(CHECKDB)")
        - Output: The raw output from the DBCC HELP command, containing the syntax help and parameter information. This is typically a DataTable or collection of results rows with parameter details.

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