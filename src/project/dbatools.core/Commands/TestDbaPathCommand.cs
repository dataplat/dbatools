#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests path accessibility from the SQL Server service account via xp_fileexist. Port of
/// public/Test-DbaPath.ps1 (W1-040). Per instance: the real Connect-DbaInstance rides the
/// outcome-as-data hop (failure -> Stop-Function -Continue); paths cast [string[]]-style
/// and batch in groups of 100; each batch joins per-path "EXEC master.dbo.xp_fileexist 'p'"
/// statements with ';' (single-quoted interpolation, UNescaped - the function's quirk);
/// ExecuteWithResults runs on SMO directly. The SCALAR mode (one path, one instance, raw
/// input not an array) returns a bare bool and ENDS the record: the function's
/// $batchresult.Tables.rows member enumeration flattens one table's one row to the DataRow
/// itself, so [0]/[1] index its COLUMNS (Bytes; -eq $true converts true to 1 - lab-proven).
/// The multi mode pairs each result row with its batch path and emits the six-property
/// object. An execution failure under -EnableException Stop-Functions and returns; otherwise
/// it writes the verbose service-account note, returns the bare false (scalar mode) or emits
/// all-false rows for the batch, and continues with the next batch.
/// Positions: SqlInstance 0, SqlCredential 1, Path 2.
/// Surface pinned by migration/baselines/Test-DbaPath.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaPath")]
public sealed class TestDbaPathCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    [Parameter(Mandatory = true, Position = 2)]
    public object Path { get; set; } = null!;

    // PS: $Path = [string[]]$Path runs at FUNCTION scope inside the instance loop, so the
    // narrowing survives into every later instance AND pipeline record: from the second
    // iteration onward $RawPath picks up the ARRAY and the scalar bare-bool mode is gone
    // for good. Carried here so record 2+ diverges to object mode exactly like the source
    // (DEF-008 re-open, B's "sql1","sql2" | Test-DbaPath -Path C:\temp probe).
    private object? _narrowedPath;

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { $server = Connect-DbaInstance ... } catch { Stop-Function "Failure" -Category ConnectionError -Continue }
            Server? server = null;
            ErrorRecord? connectError = null;
            foreach (PSObject item in NestedCommand.InvokeScoped(this, ConnectScript, instance, SqlCredential))
            {
                ErrorRecord? caught = ExtractCaughtError(item);
                if (caught is not null)
                    connectError = caught;
                else
                    server = PsAssignment.Unwrap(item) as Server;
            }
            if (connectError is not null || server is null)
            {
                StopFunction("Failure", target: instance, errorRecord: connectError, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            const int groupSize = 100;
            // PS: $RawPath = $Path; $Path = [string[]]$Path - $RawPath reads the CURRENT
            // (possibly already-narrowed) $Path, then the narrowing sticks (see _narrowedPath).
            object currentPath = _narrowedPath ?? Path;
            bool rawIsArray = PsAssignment.Unwrap(currentPath) is Array;
            string[] paths = (string[])LanguagePrimitives.ConvertTo(currentPath, typeof(string[]), CultureInfo.InvariantCulture);
            _narrowedPath = paths;
            // PS: single path + single instance + non-array raw input = bare-bool mode.
            bool scalarMode = paths.Length == 1 && SqlInstance.Length == 1 && !rawIsArray;

            for (int start = 0; start < paths.Length; start += groupSize)
            {
                int count = Math.Min(groupSize, paths.Length - start);
                string[] pathsBatch = new string[count];
                Array.Copy(paths, start, pathsBatch, 0, count);

                // PS: $query += "EXEC master.dbo.xp_fileexist '$p'"; $sql = $query -join ';'
                List<string> query = new List<string>();
                foreach (string p in pathsBatch)
                    query.Add("EXEC master.dbo.xp_fileexist '" + p + "'");
                string sql = string.Join(";", query);

                DataSet batchresult;
                try
                {
                    batchresult = server.ConnectionContext.ExecuteWithResults(sql);
                }
                catch (Exception ex)
                {
                    MethodInvocationException wrapped = WrapAsMethodInvocation(ex, "ExecuteWithResults", 1);
                    string instanceText = PSObject.AsPSObject(instance).ToString();
                    if (EnableException.ToBool())
                    {
                        // PS: Stop-Function "xp_fileexist execution failed for path(s) on $instance." ...; return
                        StopFunction("xp_fileexist execution failed for path(s) on " + instanceText + ".",
                            target: instance, errorRecord: new ErrorRecord(wrapped, "Test-DbaPath", ErrorCategory.NotSpecified, instance));
                        return;
                    }

                    WriteMessage(MessageLevel.Verbose, "xp_fileexist execution failed for path(s) on " + instanceText + ". The SQL Server service account may not have access to the specified path(s). Error: " + wrapped.Message);
                    if (scalarMode)
                    {
                        // PS: return $false - ends this record's processing entirely.
                        WriteObject(false);
                        return;
                    }
                    foreach (string p in pathsBatch)
                        WriteObject(BuildResult(server, p, false, false));
                    continue;
                }

                // PS: $batchresult.tables.rows - member enumeration flattens every table's rows.
                List<DataRow> rows = new List<DataRow>();
                foreach (DataTable table in batchresult.Tables)
                {
                    foreach (DataRow row in table.Rows)
                        rows.Add(row);
                }

                if (scalarMode)
                {
                    if (rows.Count == 0)
                    {
                        // PS: member enumeration over no rows is $null and $null[0] raises
                        // the engine's statement-terminating null-array error; the -or
                        // short-circuits the expression to ONE record and the function
                        // continues past the if with no output (codex r2 edge).
                        WriteError(new ErrorRecord(new PSInvalidOperationException("Cannot index into a null array."), "NullArray", ErrorCategory.InvalidOperation, null));
                        continue;
                    }
                    if (rows.Count == 1)
                    {
                        // PS: $batchresult.Tables.rows[0]/[1] - a SINGLE row flattens to the
                        // DataRow ITSELF, so the indexes read its COLUMNS (lab-proven).
                        DataRow row = rows[0];
                        WriteObject(EqTrue(row[0]) || EqTrue(row[1]));
                        return;
                    }
                    // Several rows (an injected path): rows[0]/rows[1] stay DataRow OBJECTS,
                    // which never compare -eq $true (codex r2).
                    WriteObject(false);
                    return;
                }

                int i = 0;
                foreach (DataRow r in rows)
                {
                    bool doesPass = EqTrue(r[0]) || EqTrue(r[1]);
                    // PS: $PathsBatch[$i] - out-of-range array indexing reads $null (an
                    // injected path can return surplus result rows - codex r1).
                    string? filePath = i < pathsBatch.Length ? pathsBatch[i] : null;
                    // PS: IsContainer = $r[1] -eq $true - the property stores the RAW
                    // operator result: a bool for scalar columns, the FILTERED MATCH ARRAY
                    // for an enumerable LHS (an injected varbinary renders "" when no byte
                    // matches - lab-proven; codex r3 refinement).
                    WriteObject(BuildResult(server, filePath, doesPass, EqTrueRaw(r[1])));
                    i += 1;
                }
            }
        }
    }

    private static PSObject BuildResult(Server server, string? filePath, bool fileExists, object? isContainer)
    {
        PSObject output = new PSObject();
        output.Properties.Add(new PSNoteProperty("SqlInstance", server.Name));
        output.Properties.Add(new PSNoteProperty("InstanceName", server.ServiceName));
        output.Properties.Add(new PSNoteProperty("ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetPSProperty(server, "ComputerName")));
        output.Properties.Add(new PSNoteProperty("FilePath", filePath));
        output.Properties.Add(new PSNoteProperty("FileExists", fileExists));
        output.Properties.Add(new PSNoteProperty("IsContainer", isContainer));
        return output;
    }

    /// <summary>PS boolean context of $value -eq $true (the -or operands): truthiness of
    /// the raw operator result.</summary>
    private static bool EqTrue(object? value)
    {
        return LanguagePrimitives.IsTrue(EqTrueRaw(value));
    }

    /// <summary>PS: $value -eq $true, the RAW operator result. A scalar LHS converts the
    /// RHS to its runtime type and returns a bool (a Byte column compares as 1; a STRING
    /// column compares case-insensitively against "True" - codex r1); an ENUMERABLE LHS
    /// FILTERS its elements and returns the match array (a varbinary column arrives as
    /// byte[] - codex r3); inconvertible values (DBNull) compare false.</summary>
    private static object EqTrueRaw(object? value)
    {
        if (value is null)
            return false;
        if (value is bool boolean)
            return boolean;
        if (value is string text)
            return PsString.Eq(text, "True");
        System.Collections.IEnumerable? enumerable = LanguagePrimitives.GetEnumerable(value);
        if (enumerable is not null)
        {
            List<object?> matches = new List<object?>();
            foreach (object? element in enumerable)
            {
                if (LanguagePrimitives.IsTrue(EqTrueRaw(element)))
                    matches.Add(element);
            }
            return matches.ToArray();
        }
        try
        {
            object converted = LanguagePrimitives.ConvertTo(true, value.GetType(), CultureInfo.InvariantCulture);
            return value.Equals(converted);
        }
        catch
        {
            return false;
        }
    }

    /// <summary>Rebuilds the MethodInvocationException the PS method binder raised for a
    /// failed .NET call: 'Exception calling "Name" with "N" argument(s): "inner"'.</summary>
    private static MethodInvocationException WrapAsMethodInvocation(Exception inner, string methodName, int argumentCount)
    {
        string text = "Exception calling \"" + methodName + "\" with \"" + argumentCount + "\" argument(s): \"" + inner.Message + "\"";
        return new MethodInvocationException(text, inner);
    }

    /// <summary>Detects the hop script's caught-error marker (outcome-as-data).</summary>
    private static ErrorRecord? ExtractCaughtError(PSObject? item)
    {
        if (item?.BaseObject is PSCustomObject)
        {
            PSPropertyInfo? marker = item.Properties["__dbatoolsCaughtError"];
            if (marker?.Value is not null)
                return PsAssignment.Unwrap(marker.Value) as ErrorRecord;
        }
        return null;
    }

    private const string ConnectScript = """
param($__instance, $__sqlCredential)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__instance, $__sqlCredential)
    try {
        Connect-DbaInstance -SqlInstance $__instance -SqlCredential $__sqlCredential 3>&1
    } catch {
        [PSCustomObject]@{ __dbatoolsCaughtError = $PSItem }
    }
} $__instance $__sqlCredential
""";
}
