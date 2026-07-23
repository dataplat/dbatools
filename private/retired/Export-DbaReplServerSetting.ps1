function Export-DbaReplServerSetting {
    <#
    .SYNOPSIS
        Generates T-SQL scripts to recreate SQL Server replication distributor and publication configurations

    .DESCRIPTION
        Creates T-SQL scripts that can recreate your SQL Server replication setup, including distributor configuration, publications, subscriptions, and all related settings. The generated scripts include both creation commands and a distributor cleanup statement, making this perfect for disaster recovery planning, environment migrations, or replication topology documentation.

        The function scripts out the complete replication configuration using SQL Server's replication management objects, so you can rebuild identical replication setups on different servers or restore replication after system failures.

        All replication commands need SQL Server Management Studio installed and are therefore currently not supported.
        Have a look at this issue to get more information: https://github.com/dataplat/dbatools/issues/7428

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Specifies the directory where the replication script file will be created. Defaults to the dbatools export path configuration.
        Use this when you want to organize replication scripts in a specific directory structure for disaster recovery or documentation purposes.

    .PARAMETER FilePath
        Specifies the complete file path including filename for the exported replication script. Overrides both Path parameter and default naming.
        Use this when you need precise control over the output file location and name, especially for automated backup processes.

    .PARAMETER Passthru
        Returns the generated T-SQL replication script to the console instead of writing to a file.
        Use this for immediate review of the script content or when piping output to other commands for further processing.

    .PARAMETER NoClobber
        Prevents overwriting an existing file with the same name. The operation will fail if the target file already exists.
        Use this as a safety measure to avoid accidentally replacing existing replication scripts during routine exports.

    .PARAMETER Encoding
        Specifies the character encoding for the output script file. Defaults to UTF8 which handles international characters properly.
        Use ASCII for maximum compatibility with older systems, or Unicode when working with databases containing non-English characters.

    .PARAMETER Append
        Adds the replication script to the end of an existing file instead of overwriting it.
        Use this when consolidating multiple replication configurations into a single script file for bulk operations.

    .PARAMETER ScriptOption
        Specifies custom Microsoft.SqlServer.Replication.ScriptOptions flags to control which replication components are scripted.
        Advanced parameter for fine-tuning script output when the default options don't meet specific requirements.

    .PARAMETER InputObject
        Accepts replication server objects from Get-DbaReplServer pipeline input for batch processing.
        Use this when scripting replication settings from multiple servers or when combining with other replication commands in a pipeline.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Replication, Repl
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaReplServerSetting

    .OUTPUTS
        System.String (when -Passthru is specified)

        Returns the generated T-SQL replication script as a string. The script includes:
        - An 'exec sp_dropdistributor' statement with @no_checks = 1 and @ignore_distributor = 1
        - T-SQL commands to recreate the distributor configuration
        - T-SQL commands to recreate all publications and their settings
        - T-SQL commands to recreate all subscriptions
        - All related replication objects and configurations based on the specified -ScriptOption flags

        None (when -Passthru is not specified)

        No output is returned to the pipeline when saving to a file. The T-SQL script is written to the specified file path containing the complete replication configuration needed to recreate the replication setup on another server.

    .EXAMPLE
        PS C:\> Export-DbaReplServerSetting -SqlInstance sql2017 -Path C:\temp\replication.sql

        Exports the replication settings on sql2017 to the file C:\temp\replication.sql

    .EXAMPLE
        PS C:\> Get-DbaReplServer -SqlInstance sql2017 | Export-DbaReplServerSetting -Path C:\temp\replication.sql

        Exports the replication settings on sql2017 to the file C:\temp\replication.sql

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [object[]]$ScriptOption,
        [Parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [switch]$Passthru,
        [switch]$NoClobber,
        [switch]$Append,
        [switch]$EnableException
    )
    begin {
        Add-ReplicationLibrary
        $null = Test-ExportDirectory -Path $Path
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException
        }

        foreach ($repserver in $InputObject) {
            $FilePath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $repserver.SqlServerName

            try {
                if (-not $ScriptOption) {
                    $out = $repserver.Script([Microsoft.SqlServer.Replication.ScriptOptions]::Creation `
                            -bor [Microsoft.SqlServer.Replication.ScriptOptions]::IncludeAll `
                            -bor [Microsoft.SqlServer.Replication.ScriptOptions]::EnableReplicationDB `
                            -bor [Microsoft.SqlServer.Replication.ScriptOptions]::IncludeInstallDistributor
                    )
                } else {
                    $out = $repserver.Script($scriptOption)
                }
            } catch {
                Stop-Function -ErrorRecord $_ -Message "Replication export failed. Is it setup?" -Continue
            }
            if ($Passthru) {
                "exec sp_dropdistributor @no_checks = 1, @ignore_distributor = 1" | Out-String
                $out | Out-String
                continue
            }

            "exec sp_dropdistributor @no_checks = 1, @ignore_distributor = 1" | Out-File -FilePath $FilePath -Encoding $encoding -Append
            $out | Out-File -FilePath $FilePath -Encoding $encoding -Append:$Append
        }
    }
}