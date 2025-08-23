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
        Specifies the objects to convert

    .PARAMETER ConvertTo
        Specifies the output type. Valid choices are Excel and CSV. CSV is the default.

    .PARAMETER Path
        Specifies the path to the output files.

    .PARAMETER Suffix
        Suffix for the filename. It's datetime by default.

    .PARAMETER NoPlanExport
        Use this switch to suppress exporting of .sqlplan files

    .PARAMETER NoQueryExport
        Use this switch to suppress exporting of .sql files

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