#nullable enable

using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text.RegularExpressions;
using System.Threading;
using Dataplat.Dbatools.Message;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Common;

namespace Dataplat.Dbatools.Commands;

public sealed partial class InvokeDbaQueryCommand
{
    private static readonly Regex GoSplitterRegex = new("(?smi)^[\\s]*GO[\\s]*$");

    /// <summary>
    /// The absorbed private/functions/Invoke-DbaAsync.ps1 engine: GO-splits the query, binds
    /// SqlParameters, fills a DataSet per piece (streaming PRINT/RAISERROR messages when
    /// requested) and emits in the requested -As shape. queryOverride carries the -Query
    /// value of the File/SMO call sites; null means the bound -Query (splat) value.
    /// </summary>
    private void RunAsync(ServerConnection sqlConnection, string? queryOverride)
    {
        // PS: if (Test-Bound -Not -ParameterName "QueryTimeout") { $QueryTimeout = $SqlConnection.StatementTimeout }
        // (the splat forwards QueryTimeout only when bound)
        int queryTimeout = TestBound("QueryTimeout") ? QueryTimeout : sqlConnection.StatementTimeout;
        string query = queryOverride ?? Query ?? "";

        // $SqlConnection.SqlConnectionObject is a no longer a System.Data connection, woo!
        SqlConnection conn = (SqlConnection)sqlConnection.SqlConnectionObject;

        WriteMessage(MessageLevel.Debug, "Stripping GOs from source");
        List<string> pieces = SplitGoBatches(query);

        foreach (string piece in pieces)
        {
            string runningStatement = piece;
            if (QuotedIdentifier.IsPresent)
                runningStatement = "SET QUOTED_IDENTIFIER ON; " + runningStatement;
            if (NoExec.IsPresent)
                runningStatement = "SET NOEXEC ON; " + runningStatement + " ;SET NOEXEC OFF;";

            SqlCommand cmd = new();
            cmd.CommandText = runningStatement;
            cmd.Connection = conn;
            cmd.CommandType = CommandType;
            cmd.CommandTimeout = queryTimeout;

            if (SqlParameter is not null)
                BindSqlParameters(cmd);

            DataSet ds = new();
            SqlDataAdapter da = new(cmd);

            // Register the in-flight command so StopProcessing (Ctrl-C) can Cancel() it; cleared
            // in finally once execution returns (DbaBaseCmdlet.SetActiveCommand/StopProcessing seam).
            SetActiveCommand(cmd);
            try
            {
                if (MessagesToOutput.IsPresent)
                {
                    FillStreamingMessages(conn, da, ds);
                }
                else
                {
                    //Following EventHandler is used for PRINT and RAISERROR T-SQL statements. Executed when -Verbose parameter specified by caller and no -MessageToOutput
                    // PS uses raw Write-Verbose here (private/functions/Invoke-DbaAsync.ps1:290), NOT
                    // Write-Message -Level Verbose, so this DELIBERATELY bypasses the WriteMessage seam:
                    // PRINT/RAISERROR text must reach the verbose stream unprefixed and unattributed the
                    // way the PS source emits it. Routing it through WriteMessage would add the message
                    // system's function/timestamp prefix and a message-log entry - an observable
                    // divergence, so faithfulness (code wins) keeps the raw WriteVerbose. da.Fill below
                    // is SYNCHRONOUS on the pipeline thread, so this handler fires inline on that same
                    // thread - no cross-thread WriteVerbose. (The -MessagesToOutput path instead fills on
                    // a worker thread and queues to a ConcurrentQueue drained on the pipeline thread; see
                    // FillStreamingMessages.)
                    SqlInfoMessageEventHandler? handler = null;
                    if (_verboseRequested)
                    {
                        conn.FireInfoMessageEventOnUserErrors = false;
                        handler = (sender, e) => WriteVerbose(e.ToString());
                        conn.InfoMessage += handler;
                    }
                    Exception? err = null;
                    try
                    {
                        da.Fill(ds);
                    }
                    catch (Exception ex)
                    {
                        // PS: [void]$da.fill($ds) is a METHOD invocation - the caught $_ carries
                        // a MethodInvocationException wrapping the provider exception, so
                        // Resolve-SqlError's SqlException branch never matches (codex r2 F2).
                        err = WrapAsMethodInvocation(ex, "Fill", 1);
                    }
                    finally
                    {
                        if (_verboseRequested)
                            conn.InfoMessage -= handler;
                    }
                    ResolveSqlError(err);
                }
            }
            finally
            {
                SetActiveCommand(null);
            }

            if (AppendServerInstance.IsPresent)
            {
                //Basics from Chad Miller
                DataColumn column = new();
                column.ColumnName = "ServerInstance";

                if (ds.Tables.Count != 0)
                {
                    ds.Tables[0].Columns.Add(column);
                    foreach (DataRow row in ds.Tables[0].Rows)
                        row["ServerInstance"] = sqlConnection.ServerInstance;
                }
            }

            cmd.Parameters.Clear();

            EmitResults(ds);
        }
    }

    /// <summary>The Invoke-DbaAsync SqlParameter binding block: a SqlParameter array adds
    /// each; a single dictionary adds per entry with the PS null/nested-parameter rules.</summary>
    private void BindSqlParameters(SqlCommand cmd)
    {
        object? first = SqlParameter!.Length > 0 ? (object?)SqlParameter[0] : null;
        object? firstBase = first is PSObject wrappedFirst ? wrappedFirst.BaseObject : first;
        if (firstBase is Microsoft.Data.SqlClient.SqlParameter)
        {
            foreach (PSObject sqlparam in SqlParameter)
            {
                // PS: $cmd.Parameters.Add($sqlparam) - validation deliberately checks only
                // the FIRST element, so a later non-parameter element must reach the
                // collection's own type check (its InvalidCastException text), not a C#
                // cast (codex r2 F3). The object overload matches the PS binder's pick.
                cmd.Parameters.Add((object)sqlparam.BaseObject);
            }
        }
        else
        {
            // PS: ($SqlParameter | Select-Object -First 1).GetEnumerator() on an EMPTY
            // array is a method call on $null (codex r1 F3).
            if (firstBase is not IDictionary dictionary)
                throw new RuntimeException("You cannot call a method on a null-valued expression.");
            foreach (DictionaryEntry entry in dictionary)
            {
                object? entryValue = entry.Value is PSObject wrappedValue ? wrappedValue.BaseObject : entry.Value;
                string entryKey = (string)LanguagePrimitives.ConvertTo(entry.Key, typeof(string), CultureInfo.InvariantCulture);
                if (entryValue is not null)
                {
                    if (entryValue is Microsoft.Data.SqlClient.SqlParameter nestedParameter)
                    {
                        // PS: if ($_.Value.ParameterName -ne $_.Key) - case-insensitive, so a
                        // case-only difference keeps the parameter's own name.
                        if (!PsString.Eq(nestedParameter.ParameterName, entryKey))
                            nestedParameter.ParameterName = entryKey;
                        cmd.Parameters.Add(nestedParameter);
                    }
                    else
                    {
                        cmd.Parameters.AddWithValue(entryKey, entryValue);
                    }
                }
                else
                {
                    cmd.Parameters.AddWithValue(entryKey, DBNull.Value);
                }
            }
        }
    }

    /// <summary>
    /// The -MessagesToOutput branch: the PS original fills on a runspace-pool worker while
    /// the pipeline thread drains a ConcurrentQueue of InfoMessage texts to the OUTPUT
    /// stream; a plain worker thread reproduces the streaming semantics.
    /// </summary>
    private void FillStreamingMessages(SqlConnection conn, SqlDataAdapter da, DataSet ds)
    {
        ConcurrentQueue<string> queue = new();
        Exception? fillError = null;
        Thread worker = new(() =>
        {
            conn.FireInfoMessageEventOnUserErrors = false;
            SqlInfoMessageEventHandler handler = (sender, e) => queue.Enqueue(e.ToString());
            conn.InfoMessage += handler;
            try
            {
                da.Fill(ds);
            }
            catch (Exception ex)
            {
                // Same MethodInvocationException wrap as the non-streaming path: the PS
                // runspace worker's catch also observed the method-invocation record.
                fillError = WrapAsMethodInvocation(ex, "Fill", 1);
            }
            finally
            {
                conn.InfoMessage -= handler;
            }
        });
        worker.IsBackground = true;
        worker.Start();
        // While streaming ... (the PS loop busy-polls the queue exactly like this)
        while (worker.IsAlive)
        {
            if (queue.TryDequeue(out string? item))
                WriteObject(item);
        }
        worker.Join();
        // Drain the stream as the runspace is closed, just to be safe
        while (queue.TryDequeue(out string? item))
            WriteObject(item);
        ResolveSqlError(fillError);
    }

    /// <summary>
    /// Rebuilds the MethodInvocationException the PS method binder raised for a failed
    /// .NET call: 'Exception calling "Name" with "N" argument(s): "inner"' (the reflected
    /// member name, casing-independent of the call site - lab probe-miecase, both editions).
    /// </summary>
    private static MethodInvocationException WrapAsMethodInvocation(Exception inner, string methodName, int argumentCount)
    {
        string text = "Exception calling \"" + methodName + "\" with \"" + argumentCount + "\" argument(s): \"" + inner.Message + "\"";
        return new MethodInvocationException(text, inner);
    }

    /// <summary>The absorbed Resolve-SqlError helper: swallows under
    /// SilentlyContinue/Ignore, rethrows otherwise (the caller catch turns it into the
    /// "[target] Failed during execution" Stop-Function). The SqlException branch is dead
    /// in the PS source (the caught record's exception is always the method-invocation
    /// wrapper) and stays dead here now that Fill failures arrive wrapped.</summary>
    private void ResolveSqlError(Exception? err)
    {
        if (err is null)
            return;
        if (string.Equals(err.GetType().Name, "SqlException", StringComparison.OrdinalIgnoreCase))
        {
            // For SQL exception
            WriteMessage(MessageLevel.Debug, "Capture SQL Error");
        }
        else
        {
            // For other exception
            WriteMessage(MessageLevel.Debug, "Capture Other Error");
        }
        // PS: the nested Resolve-SqlError's own $PSBoundParameters never contains Verbose,
        // so its "SQL Error:"/"Other Error:" verbose lines are DEAD CODE (codex r1 F2).
        string preference = GetEffectiveErrorActionPreference();
        bool swallow = string.Equals(preference, "SilentlyContinue", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(preference, "Ignore", StringComparison.OrdinalIgnoreCase);
        if (swallow)
        {
            // The PS method-invocation RAISE landed one record in the caller's -ErrorVariable/
            // $error even though Resolve-SqlError swallows it (lab: both 1, both worlds).
            // WriteError reproduces that, and under SilentlyContinue/Ignore it does not
            // display, so the record is bookkeeping only - exactly like the source.
            WriteError(RecordFrom(err));
            return;
        }
        if (string.Equals(preference, "Continue", StringComparison.OrdinalIgnoreCase))
        {
            // Under Continue - the DEFAULT - WriteError would DISPLAY the record, and the PS
            // Resolve-SqlError never wrote to the error stream on any branch: it swallowed or
            // threw, and the throw came back as the caller's Stop-Function warning. Lab, a
            // malformed query under default preferences: the function printed the warning
            // alone, WriteError printed a red block on top of it. So the record goes straight
            // into $error instead, the way Stop-Function's own non-EnableException branch
            // does it ($null = Write-Error ... 2>&1) - $error keeps both records in the
            // source's order, and nothing is displayed.
            //
            // The caller's -ErrorVariable is the one thing this cannot carry: there is no
            // "error stream without display", and the source's own count comes from PS
            // copying the record per frame as the throw unwinds (lab: 12), which a single C#
            // catch frame accumulates none of. It was already divergent at 1-vs-12 and is
            // ledgered accepted-class; the visible half is the half a user sees.
            InnerCommand.InsertGlobalError(this, RecordFrom(err));
        }
        // Stop/Default skip both: WriteError would itself convert to the terminating
        // preference exception and replace the record chain the outer catch must observe.
        throw err;
    }

    private string GetEffectiveErrorActionPreference()
    {
        object? bound;
        if (MyInvocation.BoundParameters.TryGetValue("ErrorAction", out bound) && bound is not null)
            return bound.ToString()!;
        object? preference = SessionState.PSVariable.GetValue("ErrorActionPreference");
        return preference?.ToString() ?? "Continue";
    }

    /// <summary>PS: splits the query on GO separators (GoSplitterRegex) and keeps only the
    /// statements that are non-empty after Trim. Extracted from the process loop verbatim so
    /// the split-and-filter can be pinned without a live connection.</summary>
    internal static List<string> SplitGoBatches(string query)
    {
        string[] rawPieces = GoSplitterRegex.Split(query);
        List<string> pieces = new();
        foreach (string rawPiece in rawPieces)
        {
            if (rawPiece.Trim().Length > 0)
                pieces.Add(rawPiece);
        }
        return pieces;
    }

    /// <summary>The embedded DBNullScrubber (props to Dave Wyatt), native.</summary>
    internal static PSObject DataRowToPSObject(DataRow? row)
    {
        PSObject psObject = new();

        if (row is not null && (row.RowState & DataRowState.Detached) != DataRowState.Detached)
        {
            foreach (DataColumn column in row.Table.Columns)
            {
                object? value = null;
                if (!row.IsNull(column))
                    value = row[column];

                psObject.Properties.Add(new PSNoteProperty(column.ColumnName, value));
            }
        }

        return psObject;
    }

    /// <summary>The Invoke-DbaAsync output switch over -As.</summary>
    private void EmitResults(DataSet ds)
    {
        if (string.Equals(As, "DataSet", StringComparison.OrdinalIgnoreCase))
        {
            WriteObject(ds);
        }
        else if (string.Equals(As, "DataTable", StringComparison.OrdinalIgnoreCase))
        {
            // PS emits $ds.Tables - the pipeline enumerates the collection to DataTables.
            WriteObject(ds.Tables, true);
        }
        else if (string.Equals(As, "DataRow", StringComparison.OrdinalIgnoreCase))
        {
            if (ds.Tables.Count != 0)
            {
                // PS emits $ds.Tables[0] - the pipeline enumerates a DataTable to its rows.
                WriteObject(ds.Tables[0], true);
            }
        }
        else if (string.Equals(As, "PSObject", StringComparison.OrdinalIgnoreCase))
        {
            foreach (DataTable table in ds.Tables)
            {
                //Scrub DBNulls - Provides convenient results you can use comparisons with
                foreach (DataRow row in table.Rows)
                    WriteObject(DataRowToPSObject(row));
            }
        }
        else if (string.Equals(As, "PSObjectArray", StringComparison.OrdinalIgnoreCase))
        {
            foreach (DataTable table in ds.Tables)
            {
                List<PSObject> rows = new();
                foreach (DataRow row in table.Rows)
                    rows.Add(DataRowToPSObject(row));
                // PS: , $rows - the comma-wrap emits the collected value as ONE object
                // (the single object for one row, object[] for many - the element type is
                // object[], not PSObject[], and GetType is observable). An EMPTY table
                // leaves $rows as AutomationNull, and , $rows unwraps to it in the
                // pipeline: NOTHING reaches the caller (codex r2 F1).
                object? shaped;
                if (rows.Count == 0)
                {
                    continue;
                }
                else if (rows.Count == 1)
                {
                    shaped = rows[0];
                }
                else
                {
                    object[] collected = new object[rows.Count];
                    for (int i = 0; i < rows.Count; i++)
                        collected[i] = rows[i];
                    shaped = collected;
                }
                WriteObject(shaped, false);
            }
        }
        else if (string.Equals(As, "SingleValue", StringComparison.OrdinalIgnoreCase))
        {
            if (ds.Tables.Count != 0)
            {
                // PS: $ds.Tables[0] | Select-Object -ExpandProperty <first column name> -
                // the REAL Select-Object rides nested for expansion semantics.
                Hashtable selectParams = new();
                selectParams["ExpandProperty"] = ds.Tables[0].Columns[0].ColumnName;
                Collection<PSObject> expanded = NestedCommand.Invoke(this, "Select-Object", selectParams, ds.Tables[0]);
                foreach (PSObject item in expanded)
                    WriteObject(item);
            }
        }
    }

}
