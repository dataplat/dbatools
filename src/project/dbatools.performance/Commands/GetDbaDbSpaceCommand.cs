#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Reports file space usage per database file. Port of public/Get-DbaDbSpace.ps1
/// (W1-070). Quirks preserved: -IncludeSystemDBs short-circuits every process block with
/// the record-less deprecation Stop-Function; a truthy -SqlInstance appends
/// Get-DbaDatabase output (WHOLE array, all four parameters verbatim) to InputObject;
/// $db.Parent/status/IsAccessible read ETS-FIRST (W1-069 law) and a null-or-<9
/// VersionMajor (null -lt 9 is TRUE) takes the "SQL Server 2000 not supported" branch;
/// the verbose and catch messages interpolate the UNDEFINED $instance through the
/// module-scope dynamic read (W1-051 law); the ($db.ExecuteWithResults($sql)).Tables.Rows
/// member-enumeration walk rides the hop VERBATIM; the five DBNull-or-Round locals and
/// all [dbasize] arithmetic sit INSIDE the function's own try - any fault lands in the
/// catch's Stop-Function -Continue. Surface pinned by
/// migration/baselines/Get-DbaDbSpace.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaDbSpace")]
public sealed class GetDbaDbSpaceCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The databases to report on.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The databases to skip.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Deprecated; stops the command with the migration hint.</summary>
    [Parameter]
    public SwitchParameter IncludeSystemDBs { get; set; }

    /// <summary>Database objects piped in, typically from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private const string Sql = @"SELECT SERVERPROPERTY('MachineName') AS ComputerName,
                                   ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                                   SERVERPROPERTY('ServerName') AS SqlInstance,
                    DB_NAME() AS DBName
                    ,f.name AS [FileName]
                    ,fg.name AS [Filegroup]
                    ,f.physical_name AS [PhysicalName]
                    ,f.type_desc AS [FileType]
                    ,CAST(CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS INT)/128.0 AS FLOAT) AS [UsedSpaceMB]
                    ,CAST(f.size/128.0 - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS INT)/128.0 AS FLOAT) AS [FreeSpaceMB]
                    ,CAST((f.size/128.0) AS FLOAT) AS [FileSizeMB]
                    ,CAST((FILEPROPERTY(f.name, 'SpaceUsed')/(f.size/1.0)) * 100 AS FLOAT) AS [PercentUsed]
                    ,CAST((f.growth/128.0) AS FLOAT) AS [GrowthMB]
                    ,CASE is_percent_growth WHEN 1 THEN 'pct' WHEN 0 THEN 'MB' ELSE 'Unknown' END AS [GrowthType]
                    ,CASE f.max_size WHEN -1 THEN 2147483648. ELSE CAST((f.max_size/128.0) AS FLOAT) END AS [MaxSizeMB]
                    ,CAST((f.size/128.0) AS FLOAT) - CAST(CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS INT)/128.0 AS FLOAT) AS [SpaceBeforeAutoGrow]
                    ,CASE f.max_size    WHEN (-1)
                                        THEN CAST(((2147483648.) - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS INT))/128.0 AS FLOAT)
                                        ELSE CAST((f.max_size - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS INT))/128.0 AS FLOAT)
                                        END AS [SpaceBeforeMax]
                    ,CASE f.growth    WHEN 0 THEN 0.00
                                    ELSE    CASE f.is_percent_growth    WHEN 0
                                                    THEN    CASE f.max_size
                                                            WHEN (-1)
                                                            THEN CAST(((((2147483648.)-f.size)/f.growth)*f.growth)/128.0 AS FLOAT)
                                                            ELSE CAST((((f.max_size-f.size)/f.growth)*f.growth)/128.0 AS FLOAT)
                                                            END
                                                    WHEN 1
                                                    THEN    CASE f.max_size
                                                            WHEN (-1)
                                                            THEN CAST(CONVERT([INT],f.size*POWER((1)+CONVERT([FLOAT],f.growth)/(100),CONVERT([INT],LOG10(CONVERT([FLOAT],(2147483648.))/CONVERT([FLOAT],f.size))/LOG10((1)+CONVERT([FLOAT],f.growth)/(100)))))/128.0 AS FLOAT)
                                                            ELSE CAST(CONVERT([INT],f.size*POWER((1)+CONVERT([FLOAT],f.growth)/(100),CONVERT([INT],LOG10(CONVERT([FLOAT],f.max_size)/CONVERT([FLOAT],f.size))/LOG10((1)+CONVERT([FLOAT],f.growth)/(100)))))/128.0 AS FLOAT)
                                                            END
                                                    ELSE (0)
                                                    END
                                    END AS [PossibleAutoGrowthMB]
                    , CASE f.max_size    WHEN -1 THEN 0
                                        ELSE CASE f.growth
                                                WHEN 0 THEN (f.max_size - f.size)/128
                                                ELSE    CASE f.is_percent_growth
                                                        WHEN 0
                                                        THEN CAST((f.max_size - f.size - (    CONVERT(FLOAT,FLOOR((f.max_size-f.size)/f.growth)*f.growth)))/128.0 AS FLOAT)
                                                        ELSE CAST((f.max_size - f.size - (    CONVERT([INT],f.size*POWER((1)+CONVERT([FLOAT],f.growth)/(100),CONVERT([INT],LOG10(CONVERT([FLOAT],f.max_size)/CONVERT([FLOAT],f.size))/LOG10((1)+CONVERT([FLOAT],f.growth)/(100)))))))/128.0 AS FLOAT)
                                                        END
                                                END
                                    END AS [UnusableSpaceMB]

                FROM sys.database_files AS f WITH (NOLOCK)
                LEFT OUTER JOIN sys.filegroups AS fg WITH (NOLOCK)
                ON f.data_space_id = fg.data_space_id";

    // PS: $InputObject += ... mutates the parameter variable, which persists ACROSS
    // process blocks unless the binder re-binds it (pipeline binding creates a new
    // array each record; a named binding never re-binds) - so instance-piped input
    // re-emits earlier records' databases.
    private List<object?> _accumulated = new List<object?>();
    private object? _lastBoundInputObject;

    protected override void ProcessRecord()
    {
        if (IncludeSystemDBs.IsPresent)
        {
            StopFunction("IncludeSystemDBs will be removed. Please pipe in filtered results from Get-DbaDatabase instead.");
            return;
        }

        if (!ReferenceEquals(InputObject, _lastBoundInputObject))
        {
            _accumulated = new List<object?>();
            if (InputObject is not null)
            {
                foreach (Microsoft.SqlServer.Management.Smo.Database db in InputObject)
                    _accumulated.Add(db);
            }
            _lastBoundInputObject = InputObject;
        }
        List<object?> inputObjects = _accumulated;

        // PS: if ($SqlInstance) - VALUE truthiness; the WHOLE array rides one call.
        if (PsTruthy(SqlInstance))
        {
            try
            {
                foreach (PSObject? fetched in NestedCommand.InvokeScoped(this, GetDatabaseScript, SqlInstance, SqlCredential, Database, ExcludeDatabase, BoundVerbose(), BoundDebug()))
                    inputObjects.Add(fetched);
            }
            catch (PipelineStoppedException) { throw; }
            catch (RuntimeException ex) { StatementFault.Surface(this, ex, "Get-DbaDbSpace"); }
        }

        foreach (object? item in inputObjects)
        {
            // PS: ETS-first reads; $server.VersionMajor -lt 9 is TRUE for null (null
            // converts to 0), an ARRAY value filters elementwise (result truthiness
            // decides), and a non-comparable value statement-faults the IF - both
            // branches skipped, execution continues at the try.
            object? server = DotAccess(item, "Parent");
            object? versionMajor = DotAccess(server, "VersionMajor");
            bool tooOld;
            bool gateFaulted = false;
            try
            {
                tooOld = PsLessThanNine(versionMajor);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StatementFault.Surface(this, ex, "Get-DbaDbSpace");
                tooOld = false;
                gateFaulted = true;
            }
            if (!gateFaulted && tooOld)
            {
                StopFunction("SQL Server 2000 not supported. " + PsText(server) + " skipped.", continueLoop: true);
                continue;
            }

            try
            {
                WriteMessage(MessageLevel.Verbose, "Querying " + PsText(ModuleInstance()) + " - " + PsText(item) + ".");
                if (!PsOps.Eq(DotAccess(item, "status"), "Normal") || PsOps.Eq(DotAccess(item, "IsAccessible"), false))
                {
                    WriteMessage(MessageLevel.Warning, PsText(item) + " is not accessible.", target: item);
                    continue;
                }
                // PS: ($db.ExecuteWithResults($sql)).Tables.Rows - the member-enum walk
                // rides the hop verbatim (decorated objects included).
                foreach (PSObject? row in NestedCommand.InvokeScoped(this, ExecuteWithResultsScript, item, Sql))
                {
                    if (row is null)
                        continue;
                    object usedMB = RoundOrZero(DotAccess(row, "UsedSpaceMB"));
                    object freeMB = RoundOrZero(DotAccess(row, "FreeSpaceMB"));
                    object percentUsed = RoundOrZero(DotAccess(row, "PercentUsed"));
                    object spaceUntilMax = RoundOrZero(DotAccess(row, "SpaceBeforeMax"));
                    object unusableSpace = RoundOrZero(DotAccess(row, "UnusableSpaceMB"));

                    PSObject result = new PSObject();
                    result.Properties.Add(new PSNoteProperty("ComputerName", DotAccess(server, "ComputerName")));
                    result.Properties.Add(new PSNoteProperty("InstanceName", DotAccess(server, "ServiceName")));
                    result.Properties.Add(new PSNoteProperty("SqlInstance", DotAccess(server, "DomainInstanceName")));
                    result.Properties.Add(new PSNoteProperty("Database", DotAccess(row, "DBName")));
                    result.Properties.Add(new PSNoteProperty("FileName", DotAccess(row, "FileName")));
                    result.Properties.Add(new PSNoteProperty("FileGroup", DotAccess(row, "FileGroup")));
                    result.Properties.Add(new PSNoteProperty("PhysicalName", DotAccess(row, "PhysicalName")));
                    result.Properties.Add(new PSNoteProperty("FileType", DotAccess(row, "FileType")));
                    result.Properties.Add(new PSNoteProperty("UsedSpace", DbaSizeBytes(usedMB)));
                    result.Properties.Add(new PSNoteProperty("FreeSpace", DbaSizeBytes(freeMB)));
                    result.Properties.Add(new PSNoteProperty("FileSize", DbaSizeBytes(DotAccess(row, "FileSizeMB"))));
                    result.Properties.Add(new PSNoteProperty("PercentUsed", percentUsed));
                    result.Properties.Add(new PSNoteProperty("AutoGrowth", DbaSizeBytes(DotAccess(row, "GrowthMB"))));
                    result.Properties.Add(new PSNoteProperty("AutoGrowType", DotAccess(row, "GrowthType")));
                    result.Properties.Add(new PSNoteProperty("SpaceUntilMaxSize", DbaSizeBytes(spaceUntilMax)));
                    result.Properties.Add(new PSNoteProperty("AutoGrowthPossible", DbaSizeBytes(DotAccess(row, "PossibleAutoGrowthMB"))));
                    result.Properties.Add(new PSNoteProperty("UnusableSpace", DbaSizeBytes(unusableSpace)));
                    WriteObject(result);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction("Unable to query " + PsText(ModuleInstance()) + " - " + PsText(item) + ".", target: item, errorRecord: StatementFault.Record(ex, "Get-DbaDbSpace"), continueLoop: true);
                continue;
            }
        }
    }

    /// <summary>PS: DBNull maps to int 0, otherwise [Math]::Round - decimal keeps the
    /// decimal overload, everything else goes double (a fault bubbles to the
    /// function's own catch).</summary>
    private static object RoundOrZero(object? value)
    {
        object? unwrapped = value is PSObject pso ? pso.BaseObject : value;
        if (unwrapped is DBNull)
            return 0;
        if (unwrapped is decimal dec)
            return Math.Round(dec);
        return Math.Round((double)LanguagePrimitives.ConvertTo(unwrapped, typeof(double), CultureInfo.InvariantCulture));
    }

    /// <summary>PS `$x -lt 9`: null converts to 0 (TRUE); an array filters elementwise
    /// and the RESULT's truthiness decides (1-element results take the element's
    /// truthiness); a non-comparable scalar throws to the caller's fault handling.</summary>
    private static bool PsLessThanNine(object? value)
    {
        if (value is null)
            return true;
        object? unwrapped = value is PSObject pso ? pso.BaseObject : value;
        if (unwrapped is not string && LanguagePrimitives.GetEnumerable(unwrapped) is IEnumerable elements)
        {
            List<object?> matches = new List<object?>();
            foreach (object? element in elements)
            {
                object? el = element is PSObject epso ? epso.BaseObject : element;
                if (el is null || LanguagePrimitives.Compare(el, 9, false, CultureInfo.InvariantCulture) < 0)
                    matches.Add(el);
            }
            if (matches.Count == 0)
                return false;
            if (matches.Count == 1)
                return LanguagePrimitives.IsTrue(matches[0]);
            return true;
        }
        return LanguagePrimitives.Compare(unwrapped, 9, false, CultureInfo.InvariantCulture) < 0;
    }

    /// <summary>PS: [dbasize]($x * 1024 * 1024) - null propagates, DBNull faults like
    /// the PS op_Multiply miss (to the function's own catch).</summary>
    private static object? DbaSizeBytes(object? value)
    {
        object? unwrapped = value is PSObject pso ? pso.BaseObject : value;
        if (unwrapped is null)
            return null;
        if (unwrapped is DBNull)
            throw new RuntimeException("Method invocation failed because [System.DBNull] does not contain a method named 'op_Multiply'.");
        double product = (double)LanguagePrimitives.ConvertTo(unwrapped, typeof(double), CultureInfo.InvariantCulture) * 1024.0 * 1024.0;
        return LanguagePrimitives.ConvertTo(product, typeof(Size), CultureInfo.InvariantCulture);
    }

    /// <summary>PS array truthiness: empty = false, one element = its truthiness,
    /// two or more = true.</summary>
    private static bool PsTruthy(object[]? values)
    {
        if (values is null || values.Length == 0)
            return false;
        if (values.Length == 1)
            return LanguagePrimitives.IsTrue(values[0]);
        return true;
    }

    /// <summary>The UNDEFINED $instance interpolation - module-scope dynamic read (W1-051 law).</summary>
    private object? ModuleInstance()
    {
        return PipelineValue(NestedCommand.InvokeScoped(this, ModuleVariableScript, "instance"));
    }

    /// <summary>PS pipeline-assignment collapse: none = null, one = the item, many = array.</summary>
    private static object? PipelineValue(Collection<PSObject> results)
    {
        if (results.Count == 0)
            return null;
        if (results.Count == 1)
            return results[0];
        object?[] array = new object?[results.Count];
        for (int n = 0; n < results.Count; n++)
            array[n] = results[n];
        return array;
    }

    /// <summary>The PS dot operator (ETS-first single-object reads).</summary>
    private static object? DotAccess(object? item, string name)
    {
        if (item is null)
            return null;
        PSObject wrapped = PSObject.AsPSObject(item);
        PSPropertyInfo? direct = wrapped.Properties[name];
        if (direct is null)
            return null;
        object? value;
        try { value = direct.Value; }
        catch { return null; }
        if (value is PSObject psValue && psValue.BaseObject is not PSCustomObject)
            return psValue.BaseObject;
        return value;
    }

    /// <summary>PS string interpolation via LanguagePrimitives (invariant).</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
    }

    /// <summary>A bound -Debug carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundDebug()
    {
        object? debug;
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    /// <summary>A bound -Verbose carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundVerbose()
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    // PS: Get-DbaDatabase called with the WHOLE -SqlInstance array and all parameters
    // verbatim (null when unbound).
    private const string GetDatabaseScript = """
param($__instances, $SqlCredential, $Database, $ExcludeDatabase, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__instances, $SqlCredential, $Database, $ExcludeDatabase, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    Get-DbaDatabase -SqlInstance $__instances -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
} $__instances $SqlCredential $Database $ExcludeDatabase $__boundVerbose $__boundDebug 3>&1
""";

    // PS: ($db.ExecuteWithResults($sql)).Tables.Rows - verbatim member-enum walk.
    private const string ExecuteWithResultsScript = """
param($db, $query)
($db.ExecuteWithResults($query)).Tables.Rows
""";

    // PS: the undefined fn-variable read resolves module -> global (the W1-051 law).
    private const string ModuleVariableScript = """
param($__name)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__name)
    $ExecutionContext.SessionState.PSVariable.GetValue($__name)
} $__name 3>&1
""";
}
