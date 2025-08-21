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
        Specifies the directory where the file or files will be exported.

    .PARAMETER FilePath
        Specifies the full file path of the output file.

    .PARAMETER Passthru
        Output script to console

    .PARAMETER NoClobber
        Do not overwrite file

    .PARAMETER Encoding
        Specifies the file encoding. The default is UTF8.

        Valid values are:
        -- ASCII: Uses the encoding for the ASCII (7-bit) character set.
        -- BigEndianUnicode: Encodes in UTF-16 format using the big-endian byte order.
        -- Byte: Encodes a set of characters into a sequence of bytes.
        -- String: Uses the encoding type for a string.
        -- Unicode: Encodes in UTF-16 format using the little-endian byte order.
        -- UTF7: Encodes in UTF-7 format.
        -- UTF8: Encodes in UTF-8 format.
        -- Unknown: The encoding type is unknown or invalid. The data can be treated as binary.

    .PARAMETER Append
        Append to file

    .PARAMETER ScriptOption
        Not real sure how to use this yet

    .PARAMETER InputObject
        Allows piping from Get-DbaReplServer

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