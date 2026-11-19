#nullable enable

using System;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports Invoke-DbaDiagnosticQuery results to csv/excel plus .sqlplan/.sql side files.
/// Port of public/Export-DbaDiagnosticQuery.ps1 (W1-049). The begin block's Excel module
/// probe, directory ensure/type check, and the whole per-row export body run as VERBATIM
/// module-scoped PS via hops (Remove-InvalidFileNameChars stays private PS; Join-DbaPath is
/// compiled and resolves through the module; Get-Member/Select-Object/Out-File/Export-Csv/
/// Export-Excel/Get-ChildItem are the real engine cmdlets, so column detection, default
/// Out-File encodings, CSV shapes, and the streamed FileInfo output are engine-exact). The
/// empty-result row maps to the function's exact Stop-Function -Continue site in the C#
/// loop. Parameter defaults evaluate per call like PS bind-time defaults: -Path from the
/// Path.DbatoolsExport config, -Suffix from Get-Date's "yyyyMMddHHmmssms" custom format
/// (the trailing "ms" renders minute+second again - the function's quirk, preserved).
/// No positional bindings.
/// Surface pinned by migration/baselines/Export-DbaDiagnosticQuery.json.
/// </summary>
[Cmdlet(VerbsData.Export, "DbaDiagnosticQuery")]
public sealed class ExportDbaDiagnosticQueryCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Position 0-3 mirror the source's IMPLICIT positional binding: an advanced function
    // assigns positions to its non-switch parameters in declaration order unless
    // PositionalBinding is disabled, so the source surface is InputObject 0, ConvertTo 1,
    // Path 2, Suffix 3. A compiled cmdlet grants NO position unless it is declared, so
    // omitting these is a BREAKING surface change - the gate caught exactly that
    // (surfaceDiffPs7: "Position ... 1 -> (null)" on all four). Switch parameters take no
    // position in either world. Same class as the Backup family regression (#12).
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public object[] InputObject { get; set; } = null!;

    [Parameter(Position = 1)]
    [PsStringCast]
    [ValidateSet("Excel", "Csv")]
    public string ConvertTo { get; set; } = "Csv";

    // No file path because this needs a directory
    [Parameter(Position = 2)]
    public FileInfo? Path { get; set; }

    [Parameter(Position = 3)]
    [PsStringCast]
    public string? Suffix { get; set; }

    [Parameter]
    public SwitchParameter NoPlanExport { get; set; }

    [Parameter]
    public SwitchParameter NoQueryExport { get; set; }

    protected override void BeginProcessing()
    {
        // PS bind-time defaults evaluate per call.
        if (!TestBound("Path"))
        {
            object? configured = null;
            foreach (PSObject item in NestedCommand.InvokeScoped(this, PathDefaultScript))
                configured = PsAssignment.Unwrap(item);
            if (configured is not null)
                Path = configured as FileInfo ?? new FileInfo(PsToText(configured));
        }
        if (!TestBound("Suffix"))
            Suffix = DateTime.Now.ToString("yyyyMMddHHmmssms", CultureInfo.CurrentCulture);

        // PS: if ($ConvertTo -eq "Excel") { try { Import-Module ImportExcel -ErrorAction Stop } catch { Stop-Function <verbatim message>; return } }
        if (PsString.Eq(ConvertTo, "Excel"))
        {
            bool loaded = false;
            foreach (PSObject item in NestedCommand.InvokeScoped(this, ImportExcelProbeScript))
                loaded = LanguagePrimitives.IsTrue(PsAssignment.Unwrap(item));
            if (!loaded)
            {
                StopFunction(@"Failed to load module, exporting to Excel feature is not available
                            Install the module from: https://github.com/dfinke/ImportExcel
                            Valid alternative conversion format is csv");
                return;
            }
        }

        // PS: Test-Path/New-Item directory ensure, else the must-be-a-directory check.
        string? failure = null;
        foreach (PSObject item in NestedCommand.InvokeScoped(this, EnsureDirectoryScript, PsToText(Path)))
        {
            object? marker = PsProperty.Get(item, "__dbatoolsPathFailure");
            if (marker is not null)
                failure = PsToText(marker);
        }
        if (failure is not null)
        {
            StopFunction("Path (" + PsToText(Path) + ") must be a directory");
            return;
        }
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        foreach (object? rawRow in InputObject)
        {
            object? row = PsAssignment.Unwrap(rawRow);

            // PS reads $row.Result/.Name before the null check; SqlInstance.Replace on a
            // null SqlInstance raises the engine's method-on-null exactly like the hop does.
            object? result = PsProperty.Get(row, "Result");
            object? name = PsProperty.Get(row, "Name");

            if (result is null)
            {
                // PS: Stop-Function -Message "Result was empty for $name" -Target $result -Continue
                StopFunction("Result was empty for " + PsToText(name), target: result, continueLoop: true);
                continue;
            }

            foreach (PSObject item in NestedCommand.InvokeScoped(this, ExportRowScript,
                row, PsToText(Path), Suffix, NoPlanExport.ToBool(), NoQueryExport.ToBool(), ConvertTo))
            {
                WriteObject(item);
            }
        }
    }

    /// <summary>PS interpolation-style text ([string]/"$x" - null renders empty).</summary>
    private static string PsToText(object? value)
    {
        if (value is null)
            return "";
        return PSObject.AsPSObject(value).ToString();
    }

    private const string PathDefaultScript = """
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'
}
""";

    private const string ImportExcelProbeScript = """
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    try {
        Import-Module ImportExcel -ErrorAction Stop
        $true
    } catch {
        $false
    }
}
""";

    private const string EnsureDirectoryScript = """
param($__path)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__path)
    $Path = $__path
    if (-not (Test-Path -Path $Path)) {
        $null = New-Item -ItemType Directory -Path $Path
    } else {
        if ((Get-Item $Path -ErrorAction Ignore) -isnot [System.IO.DirectoryInfo]) {
            [PSCustomObject]@{ __dbatoolsPathFailure = $Path }
        }
    }
} $__path
""";

    // The function's per-row export body VERBATIM (from $result/$name reads through the
    // ConvertTo switch), fed the raw row plus the resolved parameter values.
    private const string ExportRowScript = """
param($__row, $__path, $__suffix, $__noPlanExport, $__noQueryExport, $__convertTo)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__row, $__path, $__suffix, $__noPlanExport, $__noQueryExport, $__convertTo)
    $row = $__row
    $Path = $__path
    $Suffix = $__suffix
    $NoPlanExport = $__noPlanExport
    $NoQueryExport = $__noQueryExport
    $ConvertTo = $__convertTo

    $result = $row.Result
    $name = $row.Name
    $SqlInstance = $row.SqlInstance.Replace("\", "$")
    $dbName = $row.Database
    $number = $row.Number

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
                Write-Message -Level Verbose -Message "Exporting $planfilename" -FunctionName Export-DbaDiagnosticQuery -ModuleName "dbatools"
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
                Write-Message -Level Verbose -Message "Exporting $sqlfilename" -FunctionName Export-DbaDiagnosticQuery -ModuleName "dbatools"
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
                Write-Message -Level Verbose -Message "Exporting $exceldbfilename" -FunctionName Export-DbaDiagnosticQuery -ModuleName "dbatools"
                $result | Export-Excel -Path $exceldbfilename -WorkSheetname $Name -AutoSize -AutoFilter -BoldTopRow -FreezeTopRow
                Get-ChildItem -Path $exceldbfilename
            } else {
                Write-Message -Level Verbose -Message "Exporting $excelfilename" -FunctionName Export-DbaDiagnosticQuery -ModuleName "dbatools"
                $result | Export-Excel -Path $excelfilename -WorkSheetname $Name -AutoSize -AutoFilter -BoldTopRow -FreezeTopRow
                Get-ChildItem -Path $excelfilename
            }
        }
        "csv" {
            if ($row.DatabaseSpecific) {
                Write-Message -Level Verbose -Message "Exporting $csvdbfilename" -FunctionName Export-DbaDiagnosticQuery -ModuleName "dbatools"
                $result | Export-Csv -Path $csvdbfilename -NoTypeInformation -Append
                Get-ChildItem -Path $csvdbfilename
            } else {
                Write-Message -Level Verbose -Message "Exporting $csvfilename" -FunctionName Export-DbaDiagnosticQuery -ModuleName "dbatools"
                $result | Export-Csv -Path $csvfilename -NoTypeInformation -Append
                Get-ChildItem -Path $csvfilename
            }
        }
    }
} $__row $__path $__suffix $__noPlanExport $__noQueryExport $__convertTo 3>&1
""";
}
