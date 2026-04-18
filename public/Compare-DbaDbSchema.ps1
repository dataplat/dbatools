function Compare-DbaDbSchema {
    <#
    .SYNOPSIS
        Compares the schema of a DACPAC file against a target database or DACPAC file using sqlpackage.

    .DESCRIPTION
        Uses sqlpackage's DeployReport action to compare a source DACPAC against a target (live database or DACPAC file) and returns a structured list of schema differences.

        The source must be a DACPAC file. The target can be either a live SQL Server database or another DACPAC file.

        Note: Comparing two live databases is not supported by sqlpackage. To compare two live databases, first export one as a DACPAC using Export-DbaDacPackage, then pass that DACPAC as the source to this command.

        sqlpackage must be available. Install it via Install-DbaSqlPackage if needed.

    .PARAMETER SourcePath
        The path to the source DACPAC file to compare from.

    .PARAMETER TargetSqlInstance
        The target SQL Server instance containing the database to compare against.

    .PARAMETER TargetSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Only SQL authentication is supported. When not specified, uses Trusted Authentication.

    .PARAMETER TargetDatabase
        The name of the target database on the target SQL Server instance to compare against.

    .PARAMETER TargetPath
        The path to the target DACPAC file to compare against. Use this for offline comparisons between two DACPAC files.

    .PARAMETER OutputPath
        The directory where the XML deployment report will be saved. Defaults to the configured DbatoolsExport path.

        The report file is removed after parsing unless -KeepReport is specified.

    .PARAMETER KeepReport
        When specified, the generated XML deployment report file is kept after parsing. By default, the file is removed after processing.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Dacpac, Schema, SqlPackage, Compare, Deployment
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires sqlpackage to be installed. Use Install-DbaSqlPackage to install it.

    .LINK
        https://dbatools.io/Compare-DbaDbSchema

    .OUTPUTS
        PSCustomObject

        Returns one object per schema difference found between source and target.

        Properties:
        - SourcePath: Full path to the source DACPAC file
        - Target: The target database or DACPAC path
        - Operation: The type of change (e.g., Create, Alter, Drop, Rename)
        - Value: The schema object name (e.g., [dbo].[MyTable])
        - Type: The object type (e.g., Table, Procedure, View)
        - ReportPath: Full path to the XML deployment report (only present when -KeepReport is specified)

    .EXAMPLE
        PS C:\> Compare-DbaDbSchema -SourcePath C:\temp\source.dacpac -TargetSqlInstance sql2019 -TargetDatabase AdventureWorks

        Compares the source.dacpac schema against the AdventureWorks database on sql2019 and returns a list of differences.

    .EXAMPLE
        PS C:\> Compare-DbaDbSchema -SourcePath C:\temp\v2.dacpac -TargetPath C:\temp\v1.dacpac

        Compares two DACPAC files offline and returns the schema differences.

    .EXAMPLE
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database db_source -FilePath C:\temp\db_source.dacpac
        PS C:\> Compare-DbaDbSchema -SourcePath C:\temp\db_source.dacpac -TargetSqlInstance sql2016 -TargetDatabase db_target

        Exports a DACPAC from the source database, then compares it against the target database on the same instance.

    .EXAMPLE
        PS C:\> Compare-DbaDbSchema -SourcePath C:\temp\source.dacpac -TargetSqlInstance sql2019 -TargetDatabase AdventureWorks -KeepReport -OutputPath C:\reports

        Compares schema and keeps the XML report file in C:\reports.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias("Path", "FilePath")]
        [string]$SourcePath,
        [DbaInstance]$TargetSqlInstance,
        [PSCredential]$TargetSqlCredential,
        [string]$TargetDatabase,
        [string]$TargetPath,
        [string]$OutputPath = (Get-DbatoolsConfigValue -FullName "Path.DbatoolsExport"),
        [switch]$KeepReport,
        [switch]$EnableException
    )

    begin {
        $sqlPackagePath = Get-DbaSqlPackagePath -EnableException:$EnableException
        if (-not $sqlPackagePath) {
            return
        }

        if ((Test-Bound -Not -ParameterName TargetSqlInstance) -and (Test-Bound -Not -ParameterName TargetPath)) {
            Stop-Function -Message "You must specify either -TargetSqlInstance (with -TargetDatabase) or -TargetPath."
            return
        }

        if ((Test-Bound -ParameterName TargetSqlInstance) -and (Test-Bound -ParameterName TargetPath)) {
            Stop-Function -Message "Specify either -TargetSqlInstance or -TargetPath, not both."
            return
        }

        if (Test-Bound -ParameterName TargetSqlInstance) {
            if (Test-Bound -Not -ParameterName TargetDatabase) {
                Stop-Function -Message "When using -TargetSqlInstance you must also specify -TargetDatabase."
                return
            }
        }

        if (Test-Bound -ParameterName TargetPath) {
            if (-not (Test-Path -Path $TargetPath)) {
                Stop-Function -Message "Target DACPAC file not found: $TargetPath"
                return
            }
        }

        $null = Test-ExportDirectory -Path $OutputPath
    }

    process {
        if (Test-FunctionInterrupt) { return }

        if (-not (Test-Path -Path $SourcePath)) {
            Stop-Function -Message "Source DACPAC file not found: $SourcePath"
            return
        }

        $sourcePathFull = (Resolve-Path -Path $SourcePath).Path
        $timeStamp = (Get-Date).ToString("yyMMdd_HHmmss_f")
        $reportFile = Join-Path -Path $OutputPath -ChildPath "Compare-DbaDbSchema_$timeStamp.xml"

        # Build sqlpackage arguments
        $sqlPackageArgs = "/action:deployreport /of:True /sf:""$sourcePathFull"" /op:""$reportFile"""

        if (Test-Bound -ParameterName TargetSqlInstance) {
            try {
                $targetServer = Connect-DbaInstance -SqlInstance $TargetSqlInstance -SqlCredential $TargetSqlCredential
            } catch {
                Stop-Function -Message "Failure connecting to $TargetSqlInstance" -Category ConnectionError -ErrorRecord $_ -Target $TargetSqlInstance
                return
            }

            $connString = $targetServer.ConnectionContext.ConnectionString | Convert-ConnectionString
            if ($connString -notmatch "Database=") {
                $connString = "$connString;Database=$TargetDatabase"
            }
            $connStringEscaped = $connString.Replace('"', "'")
            $sqlPackageArgs += " /tcs:""$connStringEscaped"""
            $targetDescription = "$($targetServer.DomainInstanceName)\$TargetDatabase"
        } else {
            $targetPathFull = (Resolve-Path -Path $TargetPath).Path
            $targetDbName = [System.IO.Path]::GetFileNameWithoutExtension($TargetPath)
            $sqlPackageArgs += " /tf:""$targetPathFull"" /tdn:""$targetDbName"""
            $targetDescription = $TargetPath
        }

        Write-Message -Level Verbose -Message "Running sqlpackage DeployReport for $sourcePathFull against $targetDescription."

        try {
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $sqlPackagePath
            $startInfo.Arguments = $sqlPackageArgs
            $startInfo.RedirectStandardError = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo
            $process.Start() | Out-Null
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()

            Write-Message -Level Verbose -Message "sqlpackage stdout: $stdout"

            if ($process.ExitCode -ne 0) {
                Stop-Function -Message "sqlpackage failed: $stderr" -Target $SourcePath
                return
            }
        } catch {
            Stop-Function -Message "Failed to run sqlpackage" -ErrorRecord $_ -Target $SourcePath
            return
        }

        if (-not (Test-Path -Path $reportFile)) {
            Stop-Function -Message "sqlpackage did not produce an output report at $reportFile. Output: $stdout"
            return
        }

        # Parse the deployment report XML
        try {
            [xml]$report = Get-Content -Path $reportFile -ErrorAction Stop
        } catch {
            Stop-Function -Message "Failed to read or parse the deployment report at $reportFile" -ErrorRecord $_ -Target $reportFile
            return
        }

        foreach ($operation in $report.DeploymentReport.Operations.Operation) {
            $operationName = $operation.Name
            foreach ($item in $operation.Item) {
                $objectType = $item.Type -replace "^Sql", ""
                $outputObject = [PSCustomObject]@{
                    SourcePath = $sourcePathFull
                    Target     = $targetDescription
                    Operation  = $operationName
                    Value      = $item.Value
                    Type       = $objectType
                }

                if ($KeepReport) {
                    $outputObject | Add-Member -NotePropertyName "ReportPath" -NotePropertyValue $reportFile
                }

                $outputObject
            }
        }

        if (-not $KeepReport) {
            Remove-Item -Path $reportFile -ErrorAction SilentlyContinue
        } else {
            Write-Message -Level Verbose -Message "Deployment report kept at $reportFile"
        }
    }
}