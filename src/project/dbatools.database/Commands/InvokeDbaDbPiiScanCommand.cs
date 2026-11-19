#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Scans database columns for values or names that look like Personally Identifiable Information,
/// matching column names against known-name lists and sampled data against pattern lists. Port of
/// public/Invoke-DbaDbPiiScan.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// SINGLE HOP. No parameter is ValueFromPipeline, so process fires exactly once - begin and process
/// run back-to-back in one invocation and share one function scope. The port therefore ships them as
/// ONE hop in ProcessRecord (the Expand-DbaDbLogFile pattern), not a begin/process split: begin
/// loads the known-name and pattern lists (default files under $script:PSModuleRoot\bin\datamasking
/// plus any -KnownNameFilePath / -PatternFilePath, filtered by -Country / -CountryCode) and process
/// reads those in-scope locals directly, so no cross-hop sentinel or carry is needed.
///
/// Each source block is dot-sourced inside the hop so its early returns exit only that block while
/// the shared scope persists: begin's parse/validation failures are Stop-Function without -Continue,
/// which DO set the module interrupt flag (Stop-Function sets it on its non-Continue path), and the
/// dot-sourced begin block's own "return" after a parse failure exits begin only. The process block
/// opens with the source's "if (Test-FunctionInterrupt) { return }", so a begin failure makes process
/// emit nothing - reproducing the function-scope short-circuit within the one shared scope. The two
/// process Stop-Function calls are -Continue (skip the current instance/query and keep looping).
///
/// No ShouldProcess, no Test-Bound, no $PSBoundParameters, no Get-PSCallStack. The
/// -ExcludeDefaultKnownName / -ExcludeDefaultPattern switches are consumed by truthiness inside the
/// hop, so they are received UNTYPED (a typed [switch] on a positionally-bound inner parameter is
/// excluded from positional binding). $script:PSModuleRoot and the nested Get-ObjectNameParts /
/// Connect-DbaInstance / Invoke-DbaQuery resolve through the module scope. In-hop Stop-Function /
/// Write-Message carry -FunctionName. Surface pinned by migration/baselines/Invoke-DbaDbPiiScan.json
/// (positions 0-11, no sets).
///
/// GATE NOTE: this command reads its default known-name and pattern JSON from
/// $script:PSModuleRoot\bin\datamasking, so it belongs to the randomizer/datamasking CSV-path
/// cluster whose gate is deferred until the $script:PSModuleRoot-under-ManualPester product fix.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbPiiScan")]
public sealed class InvokeDbaDbPiiScanCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to scan.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Scan only these tables.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Table { get; set; }

    /// <summary>Scan only these columns.</summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? Column { get; set; }

    /// <summary>Keep only patterns for these countries.</summary>
    [Parameter(Position = 5)]
    [PsStringArrayCast]
    public string[]? Country { get; set; }

    /// <summary>Keep only patterns for these country codes.</summary>
    [Parameter(Position = 6)]
    [PsStringArrayCast]
    public string[]? CountryCode { get; set; }

    /// <summary>Skip these tables.</summary>
    [Parameter(Position = 7)]
    [PsStringArrayCast]
    public string[]? ExcludeTable { get; set; }

    /// <summary>Skip these columns.</summary>
    [Parameter(Position = 8)]
    [PsStringArrayCast]
    public string[]? ExcludeColumn { get; set; }

    /// <summary>Rows sampled per column for pattern matching (default 100).</summary>
    [Parameter(Position = 9)]
    public int SampleCount { get; set; } = 100;

    /// <summary>Additional known-name definitions JSON file.</summary>
    [Parameter(Position = 10)]
    [PsStringCast]
    public string? KnownNameFilePath { get; set; }

    /// <summary>Additional pattern definitions JSON file.</summary>
    [Parameter(Position = 11)]
    [PsStringCast]
    public string? PatternFilePath { get; set; }

    /// <summary>Do not load the built-in known-name list.</summary>
    [Parameter]
    public SwitchParameter ExcludeDefaultKnownName { get; set; }

    /// <summary>Do not load the built-in pattern list.</summary>
    [Parameter]
    public SwitchParameter ExcludeDefaultPattern { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ScanScript,
            SqlInstance, SqlCredential, Database, Table, Column, Country, CountryCode, ExcludeTable,
            ExcludeColumn, SampleCount, KnownNameFilePath, PatternFilePath,
            ExcludeDefaultKnownName.ToBool(), ExcludeDefaultPattern.ToBool(), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: begin then process, each VERBATIM and dot-sourced inside ONE hop so they share a scope
    // (process fires once - no VFP). begin's parse/validation Stop-Functions (no -Continue) set the
    // interrupt and its own "return" exits the begin block only; process reads the in-scope
    // $knownNames/$patterns and short-circuits on Test-FunctionInterrupt. Edits: -FunctionName on the
    // eight begin and eight process Stop-Function/Write-Message calls. The switch flags are received
    // UNTYPED so positional binding is not shifted.
    private const string ScanScript = """
param($SqlInstance, $SqlCredential, $Database, $Table, $Column, $Country, $CountryCode, $ExcludeTable, $ExcludeColumn, $SampleCount, $KnownNameFilePath, $PatternFilePath, $ExcludeDefaultKnownName, $ExcludeDefaultPattern, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Table, [string[]]$Column, [string[]]$Country, [string[]]$CountryCode, [string[]]$ExcludeTable, [string[]]$ExcludeColumn, [int]$SampleCount, [string]$KnownNameFilePath, [string]$PatternFilePath, $ExcludeDefaultKnownName, $ExcludeDefaultPattern, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        # Initialize the arrays
        $knownNames = @()
        $patterns = @()

        # Get the known names
        if (-not $ExcludeDefaultKnownName) {
            try {
                $defaultKnownNameFilePath = Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\pii-knownnames.json"
                $knownNames = Get-Content -Path $defaultKnownNameFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't parse known names file" -ErrorRecord $_ -FunctionName Invoke-DbaDbPiiScan
                return
            }
        }

        # Get the patterns
        if (-not $ExcludeDefaultPattern) {
            try {
                $defaultPatternFilePath = Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\pii-patterns.json"
                $patterns = Get-Content -Path $defaultPatternFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't parse pattern file" -ErrorRecord $_ -FunctionName Invoke-DbaDbPiiScan
                return
            }
        }

        # Get custom known names and patterns
        if ($KnownNameFilePath) {
            if (Test-Path -Path $KnownNameFilePath) {
                try {
                    $knownNames += Get-Content -Path $KnownNameFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Couldn't parse known types file" -ErrorRecord $_ -Target $KnownNameFilePath -FunctionName Invoke-DbaDbPiiScan
                    return
                }
            } else {
                Stop-Function -Message "Couldn't not find known names file" -Target $KnownNameFilePath -FunctionName Invoke-DbaDbPiiScan
            }
        }

        if ($PatternFilePath ) {
            if (Test-Path -Path $PatternFilePath ) {
                try {
                    $patterns += Get-Content -Path $PatternFilePath  -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Couldn't parse patterns file" -ErrorRecord $_ -Target $PatternFilePath -FunctionName Invoke-DbaDbPiiScan
                    return
                }
            } else {
                Stop-Function -Message "Couldn't not find patterns file" -Target $PatternFilePath -FunctionName Invoke-DbaDbPiiScan
            }
        }

        # Check parameters
        if (-not $SqlInstance) {
            Stop-Function -Message "Please enter a SQL Server instance" -Category InvalidArgument -FunctionName Invoke-DbaDbPiiScan
        }

        if (-not $Database) {
            Stop-Function -Message "Please enter a database" -Category InvalidArgument -FunctionName Invoke-DbaDbPiiScan
        }

        # Filter the patterns
        if ($Country.Count -ge 1) {
            $patterns = $patterns | Where-Object Country -In $Country
        }

        if ($CountryCode.Count -ge 1) {
            $patterns = $patterns | Where-Object CountryCode -In $CountryCode
        }
    }

    . {
        if (Test-FunctionInterrupt) {
            return
        }

        $piiScanResults = @()

        # Loop through the instances
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaDbPiiScan
            }

            $progressActivity = "Scanning databases for PII"
            $progressId = 1

            # Loop through the databases
            foreach ($dbName in $Database) {

                $progressTask = "Scanning Database $dbName"
                Write-Progress -Id $progressId -Activity $progressActivity -Status $progressTask

                # Get the database object
                $db = $server.Databases[$($dbName)]

                # Filter the tables if needed
                if ($Table) {
                    $tableParts = $Table | ForEach-Object { Get-ObjectNameParts -ObjectName $_ }
                    $tables = @(foreach ($tablePart in $tableParts) {
                            $db.Tables | Where-Object {
                                $_.Name -eq $tablePart.Name -and
                                $tablePart.Schema -in ($_.Schema, $null) -and
                                $tablePart.Database -in ($db.Name, $null)
                            }
                        })
                } else {
                    $tables = @($db.Tables)
                }

                if ($ExcludeTable) {
                    $excludeTableParts = $ExcludeTable | ForEach-Object { Get-ObjectNameParts -ObjectName $_ }
                    $tables = @($tables | Where-Object {
                            $tableObject = $PSItem
                            -not ($excludeTableParts | Where-Object {
                                    $_.Name -eq $tableObject.Name -and
                                    $_.Schema -in ($tableObject.Schema, $null) -and
                                    $_.Database -in ($db.Name, $null)
                                })
                        })
                }

                # Filter the tables based on the column
                if ($Column) {
                    $tables = @($tables | Where-Object { $ColumnNames = $_.Columns.Name; $Column | Where-Object { $_ -in $ColumnNames } })
                }

                if ($tables.Count -eq 0) {
                    Write-Message -Level Verbose -Message "No tables to scan in database $dbName" -FunctionName Invoke-DbaDbPiiScan -ModuleName "dbatools"
                    continue
                }

                $tableNumber = 1
                $progressStatusText = '"Table $($tableNumber.ToString().PadLeft($($tables.Count).Count.ToString().Length)) of $($tables.Count) | Scanning tables for database $dbName"'
                $progressStatusBlock = [ScriptBlock]::Create($progressStatusText)


                # Loop through the tables
                foreach ($tableobject in $tables) {
                    Write-Message -Level Verbose -Message "Scanning table [$($tableobject.Schema)].[$($tableobject.Name)]" -FunctionName Invoke-DbaDbPiiScan -ModuleName "dbatools"

                    $progressTask = "Scanning columns and data"
                    Write-Progress -Id $progressId -Activity $progressActivity -Status (& $progressStatusBlock) -CurrentOperation $progressTask -PercentComplete ($tableNumber / $($tables.Count) * 100)

                    # Get the columns
                    if ($Column) {
                        $columns = $tableobject.Columns | Where-Object Name -In $Column
                    } else {
                        $columns = $tableobject.Columns
                    }

                    if ($ExcludeColumn) {
                        $columns = $columns | Where-Object Name -NotIn $ExcludeColumn
                    }

                    # Loop through the columns
                    foreach ($columnobject in $columns) {

                        if ($columnobject.DataType.Name -eq "geography") {
                            # Add the results
                            $piiScanResults += [PSCustomObject]@{
                                ComputerName   = $db.Parent.ComputerName
                                InstanceName   = $db.Parent.ServiceName
                                SqlInstance    = $db.Parent.DomainInstanceName
                                Database       = $dbName
                                Schema         = $tableobject.Schema
                                Table          = $tableobject.Name
                                Column         = $columnobject.Name
                                "PII-Category" = "Location"
                                "PII-Name"     = "Geography"
                                FoundWith      = "DataType"
                                MaskingType    = "Random"
                                MaskingSubType = "Decimal"
                            }
                        } else {
                            if ($knownNames.Count -ge 1) {

                                # Go through the first check to see if any column is found with a known name
                                foreach ($knownName in $knownNames) {
                                    foreach ($pattern in $knownName.Pattern) {
                                        if ($columnobject.Name -match $pattern) {
                                            # Add the column name match if not already found
                                            if ($null -eq ($piiScanResults | Where-Object {
                                                        $_.ComputerName -eq $db.Parent.ComputerName -and
                                                        $_.InstanceName -eq $db.Parent.ServiceName -and
                                                        $_.SqlInstance -eq $db.Parent.DomainInstanceName -and
                                                        $_.Database -eq $dbName -and
                                                        $_.Schema -eq $tableobject.Schema -and
                                                        $_.Table -eq $tableobject.Name -and
                                                        $_.Column -eq $columnobject.Name -and
                                                        $_."PII-Category" -eq $knownName.Category -and
                                                        $_."PII-Name" -eq $knownName.Name -and
                                                        $_.FoundWith -eq "KnownName" -and
                                                        $_.MaskingType -eq $knownName.MaskingType -and
                                                        $_.MaskingSubType -eq $knownName.MaskingSubType })) {

                                                $piiScanResults += [PSCustomObject]@{
                                                    ComputerName   = $db.Parent.ComputerName
                                                    InstanceName   = $db.Parent.ServiceName
                                                    SqlInstance    = $db.Parent.DomainInstanceName
                                                    Database       = $dbName
                                                    Schema         = $tableobject.Schema
                                                    Table          = $tableobject.Name
                                                    Column         = $columnobject.Name
                                                    "PII-Category" = $knownName.Category
                                                    "PII-Name"     = $knownName.Name
                                                    FoundWith      = "KnownName"
                                                    MaskingType    = $knownName.MaskingType
                                                    MaskingSubType = $knownName.MaskingSubType
                                                    Pattern        = $knownName.Pattern
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                Write-Message -Level Verbose -Message "No known names found to perform check on" -FunctionName Invoke-DbaDbPiiScan -ModuleName "dbatools"
                            }

                            if ($patterns.Count -ge 1) {

                                Write-Message -Level Verbose -Message "Scanning the top $SampleCount values for [$($columnobject.Name)] from [$($tableobject.Schema)].[$($tableobject.Name)]" -FunctionName Invoke-DbaDbPiiScan -ModuleName "dbatools"

                                # Set the text data types
                                $textDataTypes = 'char', 'varchar', 'nchar', 'nvarchar'

                                # Setup the query
                                if ($columnobject.DataType.Name -in $textDataTypes) {
                                    $query = "SELECT TOP($SampleCount) LTRIM(RTRIM([$($columnobject.Name)])) AS [$($columnobject.Name)] FROM [$($tableobject.Schema)].[$($tableobject.Name)]"
                                } else {
                                    $query = "SELECT TOP($SampleCount) [$($columnobject.Name)] AS [$($columnobject.Name)] FROM [$($tableobject.Schema)].[$($tableobject.Name)]"
                                }

                                # Get the data
                                try {
                                    $dataset = Invoke-DbaQuery -SqlInstance $instance -SqlCredential $SqlCredential -Database $dbName -Query $query -EnableException
                                } catch {
                                    $errormessage = $_.Exception.Message.ToString()
                                    Stop-Function -Message "Error executing query $($tableobject.Schema).$($tableobject.Name): $errormessage" -Target $updatequery -Continue -ErrorRecord $_ -FunctionName Invoke-DbaDbPiiScan
                                }

                                # Check if there is any data
                                if ($dataset.Count -ge 1) {

                                    # Loop through the patterns
                                    foreach ($patternobject in $patterns) {

                                        # If there is a result from the match
                                        if ($dataset.$($columnobject.Name) -match $patternobject.Pattern) {
                                            # Add the data match if not already found
                                            if ($null -eq ($piiScanResults | Where-Object {
                                                        $_.ComputerName -eq $db.Parent.ComputerName -and
                                                        $_.InstanceName -eq $db.Parent.ServiceName -and
                                                        $_.SqlInstance -eq $db.Parent.DomainInstanceName -and
                                                        $_.Database -eq $dbName -and
                                                        $_.Schema -eq $tableobject.Schema -and
                                                        $_.Table -eq $tableobject.Name -and
                                                        $_.Column -eq $columnobject.Name -and
                                                        $_."PII-Category" -eq $patternobject.category -and
                                                        $_."PII-Name" -eq $patternobject.Name -and
                                                        $_.FoundWith -eq "Pattern" -and
                                                        $_.MaskingType -eq $patternobject.MaskingType -and
                                                        $_.MaskingSubType -eq $patternobject.MaskingSubType -and
                                                        $_.Country -eq $patternobject.Country -and
                                                        $_.CountryCode -eq $patternobject.CountryCode })) {

                                                $piiScanResults += [PSCustomObject]@{
                                                    ComputerName   = $db.Parent.ComputerName
                                                    InstanceName   = $db.Parent.ServiceName
                                                    SqlInstance    = $db.Parent.DomainInstanceName
                                                    Database       = $dbName
                                                    Schema         = $tableobject.Schema
                                                    Table          = $tableobject.Name
                                                    Column         = $columnobject.Name
                                                    "PII-Category" = $patternobject.Category
                                                    "PII-Name"     = $patternobject.Name
                                                    FoundWith      = "Pattern"
                                                    MaskingType    = $patternobject.MaskingType
                                                    MaskingSubType = $patternobject.MaskingSubType
                                                    Country        = $patternobject.Country
                                                    CountryCode    = $patternobject.CountryCode
                                                    Pattern        = $patternobject.Pattern
                                                    Description    = $patternobject.Description
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    Write-Message -Message "Table $($tableobject.Name) does not contain any rows" -Level Verbose -FunctionName Invoke-DbaDbPiiScan -ModuleName "dbatools"
                                }
                            } else {
                                Write-Message -Level Verbose -Message "No patterns found to perform check on" -FunctionName Invoke-DbaDbPiiScan -ModuleName "dbatools"
                            }
                        }
                    }

                    $tableNumber++

                } # End for each table
            } # End for each database
            Write-Progress -Id $progressId -Activity $progressActivity -Completed
        } # End for each instance

        $piiScanResults
    }
} $SqlInstance $SqlCredential $Database $Table $Column $Country $CountryCode $ExcludeTable $ExcludeColumn $SampleCount $KnownNameFilePath $PatternFilePath $ExcludeDefaultKnownName $ExcludeDefaultPattern $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
