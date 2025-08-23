function Export-DbaDiagnosticQuery {
    <#
    .SYNOPSIS
        Converts diagnostic query results from Invoke-DbaDiagnosticQuery into CSV or Excel files

    .DESCRIPTION
        Processes the PowerShell objects returned by Glenn Berry's diagnostic queries and saves them as CSV files or Excel worksheets for analysis, reporting, and sharing with vendors.
        Automatically extracts execution plans as separate .sqlplan files and query text as .sql files, which can be opened directly in SQL Server Management Studio.
        This is useful when you need file-based output for compliance documentation, performance analysis, or when working with teams that prefer traditional file formats over PowerShell objects.
        CSV output creates individual files per query while Excel output consolidates results into worksheets within a single workbook.

    .PARAMETER InputObject
        Specifies the diagnostic query results from Invoke-DbaDiagnosticQuery to convert to files.
        Accepts pipeline input directly from Invoke-DbaDiagnosticQuery or stored results in a variable.
        Each object contains query results, execution plans, and metadata needed for file export.

    .PARAMETER ConvertTo
        Specifies the output format for diagnostic query results. Valid choices are Excel and CSV with CSV as the default.
        Use Excel when you need consolidated results in worksheets for easier analysis and sharing with non-technical stakeholders.
        Choose CSV when you need individual files per query for automated processing or importing into other tools.

    .PARAMETER Path
        Specifies the directory path where exported files will be created. Must be a directory, not a filename.
        Defaults to the configured dbatools export path if not specified.
        The function creates separate files for each diagnostic query result within this directory.

    .PARAMETER Suffix
        Specifies a suffix to append to all generated filenames for uniqueness. Defaults to a timestamp in yyyyMMddHHmmssms format.
        Use this when running exports multiple times to prevent filename conflicts or when you need custom file identification.
        Helps organize multiple export runs when tracking performance trends over time.

    .PARAMETER NoPlanExport
        Suppresses the export of execution plans as separate .sqlplan files. These files can be opened directly in SQL Server Management Studio for plan analysis.
        Use this switch when you only need the query results data and not the execution plan details.
        Reduces file clutter when performing bulk exports where execution plans are not required for analysis.

    .PARAMETER NoQueryExport
        Suppresses the export of query text as separate .sql files. These files contain the actual SQL statements from the diagnostic queries.
        Use this switch when you only need the result data and not the source query text.
        Helpful when exporting large result sets where the query text is not needed for your analysis workflow.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, GlennBerry
        Author: Andre Kamman (@AndreKamman), clouddba.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaDiagnosticQuery

    .EXAMPLE
        PS C:\> Invoke-DbaDiagnosticQuery -SqlInstance sql2016 | Export-DbaDiagnosticQuery -Path c:\temp

        Converts output from Invoke-DbaDiagnosticQuery to multiple CSV files

    .EXAMPLE
        PS C:\> $output = Invoke-DbaDiagnosticQuery -SqlInstance sql2016
        PS C:\> Export-DbaDiagnosticQuery -InputObject $output -ConvertTo Excel

        Converts output from Invoke-DbaDiagnosticQuery to Excel worksheet(s) in the Documents folder
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$InputObject,
        [ValidateSet("Excel", "Csv")]
        [string]$ConvertTo = "Csv",
        # No file path because this needs a directory
        [System.IO.FileInfo]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [string]$Suffix = "$(Get-Date -format 'yyyyMMddHHmmssms')",
        [switch]$NoPlanExport,
        [switch]$NoQueryExport,
        [switch]$EnableException
    )

    begin {
        if ($ConvertTo -eq "Excel") {
            try {
                Import-Module ImportExcel -ErrorAction Stop
            } catch {
                $message = "Failed to load module, exporting to Excel feature is not available
                            Install the module from: https://github.com/dfinke/ImportExcel
                            Valid alternative conversion format is csv"
                Stop-Function -Message $message
                return
            }
        }

        if (-not (Test-Path -Path $Path)) {
            $null = New-Item -ItemType Directory -Path $Path
        } else {
            if ((Get-Item $Path -ErrorAction Ignore) -isnot [System.IO.DirectoryInfo]) {
                Stop-Function -Message "Path ($Path) must be a directory"
                return
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($row in $InputObject) {
            $result = $row.Result
            $name = $row.Name
            $SqlInstance = $row.SqlInstance.Replace("\", "$")
            $dbName = $row.Database
            $number = $row.Number

            if ($null -eq $result) {
                Stop-Function -Message "Result was empty for $name" -Target $result -Continue
            }

            $queryname = Remove-InvalidFileNameChars -Name $Name
            $excelfilename = Join-DbaPath -Path $Path -Child "$SqlInstance-DQ-$Suffix.xlsx"
            $exceldbfilename = Join-DbaPath -Path $Path -Child "$SqlInstance-DQ-$dbName-$Suffix.xlsx"
            $csvdbfilename = Join-DbaPath -Path $Path -Child "$SqlInstance-$dbName-DQ-$number-$queryname-$Suffix.csv"
            $csvfilename = Join-DbaPath -Path $Path -Child "$SqlInstance-DQ-$number-$queryname-$Suffix.csv"

            $columnnameoptions = "Query Plan", "QueryPlan", "Query_Plan", "query_plan_xml"
            if (($result | Get-Member | Where-Object Name -in $columnnameoptions).Count -gt 0) {
                $plannr = 0
                $columnname = ($result | Get-Member | Where-Object Name -In $columnnameoptions).Name
                foreach ($plan in $result."$columnname") {
                    $plannr += 1
                    if ($row.DatabaseSpecific) {
                        $planfilename = Join-DbaPath -Path $Path -Child "$SqlInstance-$dbName-DQ-$number-$queryname-$plannr-$Suffix.sqlplan"
                    } else {
                        $planfilename = Join-DbaPath -Path $Path -Child "$SqlInstance-DQ-$number-$queryname-$plannr-$Suffix.sqlplan"
                    }

                    if (-not $NoPlanExport) {
                        Write-Message -Level Verbose -Message "Exporting $planfilename"
                        if ($plan) { $plan | Out-File -FilePath $planfilename }
                    }
                }

                $result = $result | Select-Object * -ExcludeProperty "$columnname"
            }

            $columnnameoptions = "Complete Query Text", "QueryText", "Query Text", "Query_Text", "query_sql_text"
            if (($result | Get-Member | Where-Object Name -In $columnnameoptions ).Count -gt 0) {
                $sqlnr = 0
                $columnname = ($result | Get-Member | Where-Object Name -In $columnnameoptions).Name
                foreach ($sql in $result."$columnname") {
                    $sqlnr += 1
                    if ($row.DatabaseSpecific) {
                        $sqlfilename = Join-DbaPath -Path $Path -Child "$SqlInstance-$dbName-DQ-$number-$queryname-$sqlnr-$Suffix.sql"
                    } else {
                        $sqlfilename = Join-DbaPath -Path $Path -Child "$SqlInstance-DQ-$number-$queryname-$sqlnr-$Suffix.sql"
                    }

                    if (-not $NoQueryExport) {
                        Write-Message -Level Verbose -Message "Exporting $sqlfilename"
                        if ($sql) {
                            $sql | Out-File -FilePath $sqlfilename
                            Get-ChildItem -Path $sqlfilename
                        }
                    }
                }

                $result = $result | Select-Object * -ExcludeProperty "$columnname"
            }

            switch ($ConvertTo) {
                "Excel" {
                    if ($row.DatabaseSpecific) {
                        Write-Message -Level Verbose -Message "Exporting $exceldbfilename"
                        $result | Export-Excel -Path $exceldbfilename -WorkSheetname $Name -AutoSize -AutoFilter -BoldTopRow -FreezeTopRow
                        Get-ChildItem -Path $exceldbfilename
                    } else {
                        Write-Message -Level Verbose -Message "Exporting $excelfilename"
                        $result | Export-Excel -Path $excelfilename -WorkSheetname $Name -AutoSize -AutoFilter -BoldTopRow -FreezeTopRow
                        Get-ChildItem -Path $excelfilename
                    }
                }
                "csv" {
                    if ($row.DatabaseSpecific) {
                        Write-Message -Level Verbose -Message "Exporting $csvdbfilename"
                        $result | Export-Csv -Path $csvdbfilename -NoTypeInformation -Append
                        Get-ChildItem -Path $csvdbfilename
                    } else {
                        Write-Message -Level Verbose -Message "Exporting $csvfilename"
                        $result | Export-Csv -Path $csvfilename -NoTypeInformation -Append
                        Get-ChildItem -Path $csvfilename
                    }
                }
            }
        }
    }
}