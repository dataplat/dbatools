function Export-DbaRepServerSetting {
    <#
    .SYNOPSIS
        Exports replication server settings to file.

    .DESCRIPTION
        Exports replication server settings to file.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
        Allows piping from Get-DbaRepServer

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Replication
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        PS C:\> Export-DbaRepServerSetting -SqlInstance sql2017 -Path C:\temp\replication.sql

        Exports the replication settings on sql2017 to the file C:\temp\replication.sql

    .EXAMPLE
        PS C:\> Get-DbaRepServer -SqlInstance sql2017 | Export-DbaRepServerSettings -Path C:\temp\replication.sql

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
        [Microsoft.SqlServer.Replication.ReplicationServer[]]$InputObject,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [switch]$Passthru,
        [switch]$NoClobber,
        [switch]$Append,
        [switch]$EnableException
    )
    begin {
        if ((Test-Bound -ParamterName Path) -and ((Get-Item $Path -ErrorAction Ignore) -isnot [System.IO.DirectoryInfo])) {
            if ($Path -eq (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport')) {
                $null = New-Item -ItemType Directory -Path $Path
            } else {
            Stop-Function -Message "Path ($Path) must be a directory"
            }
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaRepServer -SqlInstance $instance -SqlCredential $sqlcredential
        }

        foreach ($repserver in $InputObject) {
            $server = $repserver.SqlServerName
            $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")

            if (-not $FilePath) {
                $FilePath = Join-DbaPath -Path $Path -Child "$($server.name.replace('\', '$'))-$timenow-replication.sql"
            }

            if (Test-Path $Path -PathType Container) {
                $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
                $FilePath = Join-Path -Path $Path -ChildPath "$($server.name.replace('\', '$'))-$timenow-replication.sql"
            } elseif (Test-Path $Path -PathType Leaf) {
                if ($SqlInstance.Count -gt 1) {
                    $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
                    $PathData = Get-ChildItem $Path
                    $FilePath = "$($PathData.DirectoryName)\$($server.name.replace('\', '$'))-$timenow-$($PathData.Name)"
                } else {
                    $FilePath = $Path
                }
            }

            $topdir = Split-Path -Path $FilePath

            if (-not (Test-Path -Path $topdir)) {
                New-Item -Path $topdir -ItemType Directory
            }

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
            }

            if ($FilePath) {

                "exec sp_dropdistributor @no_checks = 1, @ignore_distributor = 1" | Out-File -FilePath $FilePath -Encoding $encoding -Append
                $out | Out-File -FilePath $FilePath -Encoding $encoding -Append:$Append
            }
        }
    }
}