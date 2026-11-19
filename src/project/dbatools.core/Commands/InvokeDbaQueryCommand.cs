#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Data;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Runs T-SQL queries, script files or SMO object scripts against SQL Server instances or
/// piped databases. Port of public/Invoke-DbaQuery.ps1 with the private engine
/// Invoke-DbaAsync (and its Resolve-SqlError/DBNullScrubber helpers) absorbed;
/// Connect-DbaInstance, Disconnect-DbaInstance, Export-DbaScript, Get-DbatoolsPath and the
/// provider cmdlets ride the REAL commands nested. Surface pinned by
/// migration/baselines/Invoke-DbaQuery.json (sets Query/File/SMO, default Query,
/// SqlInstance pipeline set-less + per-set position 0). Invoke-DbaQuery is the first ported
/// command that CALLS Test-FunctionInterrupt, so ProcessRecord guards on Interrupted.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaQuery", DefaultParameterSetName = "Query")]
public sealed partial class InvokeDbaQueryCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true)]
    [Parameter(ParameterSetName = "Query", Position = 0)]
    [Parameter(ParameterSetName = "File", Position = 0)]
    [Parameter(ParameterSetName = "SMO", Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database to run the query against.</summary>
    [Parameter]
    public string? Database { get; set; }

    /// <summary>The T-SQL statement(s) to run.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Query")]
    [PsStringCast]
    public string? Query { get; set; }

    /// <summary>Number of seconds before the queries time out.</summary>
    [Parameter]
    public int QueryTimeout { get; set; }

    /// <summary>Script files, directories or http links to run.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "File")]
    [Alias("InputFile")]
    public object[]? File { get; set; }

    /// <summary>SMO objects whose scripts are executed.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "SMO")]
    public SqlSmoObject[]? SqlObject { get; set; }

    /// <summary>Output shape.</summary>
    [Parameter]
    [PsStringCast]
    [ValidateSet("DataSet", "DataTable", "DataRow", "PSObject", "PSObjectArray", "SingleValue")]
    public string As { get; set; } = "DataRow";

    /// <summary>A hashtable of parameters or New-DbaSqlParameter output for parameterized queries.</summary>
    [Parameter]
    [Alias("SqlParameters")]
    public PSObject[]? SqlParameter { get; set; }

    /// <summary>The type of command represented by the query string.</summary>
    [Parameter]
    public CommandType CommandType { get; set; } = CommandType.Text;

    /// <summary>Appends the SQL Server instance to PSObject and DataRow output.</summary>
    [Parameter]
    public SwitchParameter AppendServerInstance { get; set; }

    /// <summary>Also emits T-SQL messages (e.g. PRINT) on the output stream.</summary>
    [Parameter]
    public SwitchParameter MessagesToOutput { get; set; }

    /// <summary>Piped database objects to run the query against.</summary>
    [Parameter(ValueFromPipeline = true)]
    public SmoDatabase[]? InputObject { get; set; }

    /// <summary>Connects with ApplicationIntent ReadOnly.</summary>
    [Parameter]
    public SwitchParameter ReadOnly { get; set; }

    /// <summary>Prepends SET NOEXEC ON and appends SET NOEXEC OFF to each statement.</summary>
    [Parameter]
    public SwitchParameter NoExec { get; set; }

    /// <summary>Prepends SET QUOTED_IDENTIFIER ON to each statement.</summary>
    [Parameter]
    public SwitchParameter QuotedIdentifier { get; set; }

    /// <summary>Appends to the connection string of a new connection.</summary>
    [Parameter]
    public string? AppendConnectionString { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Function-scope state shared by begin/process/end.
    private readonly List<string?> _files = new();
    private readonly List<string> _temporaryFiles = new();
    private bool _verboseRequested;
    private bool _connectParamsCreated;

    protected override void BeginProcessing()
    {
        WriteMessage(MessageLevel.Debug, "Bound parameters: " + string.Join(", ", MyInvocation.BoundParameters.Keys));

        // PS: if ($PSBoundParameters.SqlParameter) - value truthiness
        if (BoundTruthy("SqlParameter"))
        {
            object? first = SqlParameter!.Length > 0 ? (object?)SqlParameter[0] : null;
            object? firstBase = first is PSObject wrapped ? wrapped.BaseObject : first;
            // PS: $first -isnot [SqlParameter] -and ($first -isnot [IDictionary] -or $SqlParameter -is [IDictionary[]])
            bool isSqlParam = firstBase is Microsoft.Data.SqlClient.SqlParameter;
            bool isDictionary = firstBase is IDictionary;
            if (!isSqlParam && !isDictionary)
            {
                StopFunction("SqlParameter only accepts a single hashtable or Microsoft.Data.SqlClient.SqlParameter");
                return;
            }
        }

        _verboseRequested = BoundTruthy("Verbose");

        if (TestBound("File"))
        {
            int temporaryFilesCount = 0;
            string temporaryFilesPrefix = NewTemporaryFilesPrefix();

            foreach (object? rawItem in File!)
            {
                if (rawItem is null)
                    continue;
                object item = rawItem is PSObject wrappedItem ? wrappedItem.BaseObject : rawItem;

                string type = item.GetType().FullName!;

                switch (type)
                {
                    case "System.IO.DirectoryInfo":
                        {
                            System.IO.DirectoryInfo directory = (System.IO.DirectoryInfo)item;
                            if (!directory.Exists)
                            {
                                StopFunction("Directory not found", category: ErrorCategory.ObjectNotFound);
                                return;
                            }
                            foreach (System.IO.FileInfo candidate in directory.GetFiles())
                            {
                                // PS: ($item.GetFiles() | Where-Object Extension -EQ ".sql").FullName
                                if (PsString.Eq(candidate.Extension, ".sql"))
                                    _files.Add(candidate.FullName);
                            }
                            break;
                        }
                    case "System.IO.FileInfo":
                        {
                            System.IO.FileInfo fileInfo = (System.IO.FileInfo)item;
                            if (!fileInfo.Exists)
                            {
                                StopFunction("Directory not found.", category: ErrorCategory.ObjectNotFound);
                                return;
                            }
                            _files.Add(fileInfo.FullName);
                            break;
                        }
                    case "System.String":
                        {
                            string text = (string)item;
                            string? uriScheme;
                            try
                            {
                                Uri uri = new(text);
                                uriScheme = uri.Scheme;
                            }
                            catch
                            {
                                uriScheme = null;
                            }

                            // PS: switch -regex ($uriScheme) { "http" ... } - substring regex match
                            if (uriScheme is not null && System.Text.RegularExpressions.Regex.IsMatch(uriScheme, "http", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                            {
                                string tempfile = GetDbatoolsTempPath() + "\\" + temporaryFilesPrefix + "-" + temporaryFilesCount + ".sql";
                                ErrorRecord? downloadFailure = DownloadSqlFile(text, tempfile);
                                if (downloadFailure is not null)
                                {
                                    StopFunction("Failed to download file " + text, errorRecord: downloadFailure);
                                    return;
                                }
                                _files.Add(tempfile);
                                temporaryFilesCount++;
                                _temporaryFiles.Add(tempfile);
                            }
                            else
                            {
                                List<PSObject> paths;
                                try
                                {
                                    paths = ResolvePathItems(text);
                                }
                                catch (PipelineStoppedException)
                                {
                                    throw;
                                }
                                catch (Exception ex)
                                {
                                    StopFunction("Failed to resolve path: " + text, errorRecord: RecordFrom(ex));
                                    return;
                                }

                                foreach (PSObject path in paths)
                                {
                                    object? pathBase = path.BaseObject;
                                    bool isContainer = LanguagePrimitives.IsTrue(PsProperty.Get(path, "PSIsContainer"));
                                    if (!isContainer)
                                    {
                                        string fullName = PsText(PsProperty.Get(path, "FullName"));
                                        // PS: (New-Object uri -ArgumentList $path).Scheme -ne 'file'
                                        // (the uri is built from the item's string form)
                                        if (!PsString.Eq(new Uri(PsText(path)).Scheme, "file"))
                                        {
                                            StopFunction("Could not resolve path " + PsText(path) + " as filesystem object");
                                            return;
                                        }
                                        _files.Add(fullName);
                                    }
                                }
                            }
                            break;
                        }
                    default:
                        StopFunction("Unkown input type: " + type, category: ErrorCategory.InvalidArgument);
                        return;
                }
            }
        }

        if (TestBound("SqlObject"))
        {
            _files.Clear();
            _temporaryFiles.Clear();
            int temporaryFilesCount = 0;
            string temporaryFilesPrefix = NewTemporaryFilesPrefix();

            foreach (SqlSmoObject sqlObject in SqlObject!)
            {
                // PS: try { $code = Export-DbaScript -InputObject $object -Passthru -EnableException }
                Hashtable exportParams = new();
                exportParams["InputObject"] = sqlObject;
                exportParams["Passthru"] = new SwitchParameter(true);
                exportParams["EnableException"] = new SwitchParameter(true);
                // Scripting the object is the PORT'S OWN scratch step, not a user-facing side effect,
                // which is why the retired function never gated it: a module script function resolved
                // $WhatIfPreference and $ConfirmPreference through the MODULE scope chain, so a
                // caller-local or wrapper-inherited value never reached its nested calls. A cmdlet's
                // hop reads the CALLER'S scope, so without these the script is never generated.
                exportParams["WhatIf"] = new SwitchParameter(false);
                exportParams["Confirm"] = new SwitchParameter(false);
                Collection<PSObject> code = InvokeNestedPreservingWarnings("Export-DbaScript", exportParams, null, out ErrorRecord? exportFailure);
                if (exportFailure is not null)
                {
                    StopFunction("Failed to generate script for object " + PsText(sqlObject), errorRecord: exportFailure);
                    return;
                }

                try
                {
                    string newfile = GetDbatoolsTempPath() + "\\" + temporaryFilesPrefix + "-" + temporaryFilesCount + ".sql";
                    Hashtable setContentParams = new();
                    setContentParams["Value"] = ShapePipelineValue(code);
                    setContentParams["Path"] = newfile;
                    setContentParams["Force"] = new SwitchParameter(true);
                    setContentParams["ErrorAction"] = "Stop";
                    setContentParams["Encoding"] = "UTF8";
                    // The temp .sql file is the PORT'S OWN scratch state, not a user-facing side
                    // effect, which is why the retired function never gated it - see the note at the
                    // Export-DbaScript hop above. Without these the file is never written and the
                    // command fails on the file it is about to execute.
                    setContentParams["WhatIf"] = new SwitchParameter(false);
                    setContentParams["Confirm"] = new SwitchParameter(false);
                    NestedCommand.Invoke(this, "Set-Content", setContentParams);
                    _files.Add(newfile);
                    temporaryFilesCount++;
                    _temporaryFiles.Add(newfile);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    StopFunction("Failed to write sql script to temp", errorRecord: RecordFrom(ex));
                    return;
                }
            }
        }
    }

    protected override void EndProcessing()
    {
        // Execute end even when interrupting, as only used for cleanup

        if (_temporaryFiles.Count > 0)
        {
            // Clean up temporary files that were downloaded
            foreach (string item in _temporaryFiles)
            {
                Hashtable removeParams = new();
                removeParams["Path"] = item;
                removeParams["ErrorAction"] = "Ignore";
                // Cleanup of the port's own scratch files - see the note at the Export-DbaScript hop.
                // A caller's dry run must not strand them on disk when the command itself ran.
                removeParams["WhatIf"] = new SwitchParameter(false);
                removeParams["Confirm"] = new SwitchParameter(false);
                try
                {
                    NestedCommand.Invoke(this, "Remove-Item", removeParams);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch
                {
                    // -ErrorAction Ignore swallows provider failures
                }
            }
        }
    }

    /// <summary>PS: (97..122 | Get-Random -Count 10 | ForEach-Object {[char]$_}) -join ''.</summary>
    private static string NewTemporaryFilesPrefix()
    {
        Random random = new();
        char[] pool = new char[26];
        for (int i = 0; i < 26; i++)
            pool[i] = (char)(97 + i);
        // Get-Random -Count 10 samples WITHOUT replacement.
        for (int i = 25; i > 0; i--)
        {
            int j = random.Next(i + 1);
            (pool[i], pool[j]) = (pool[j], pool[i]);
        }
        return new string(pool, 0, 10);
    }

    /// <summary>Whether the named parameter was bound AND its bound value is PS-truthy.</summary>
    private bool BoundTruthy(string parameterName)
    {
        object? value;
        if (!MyInvocation.BoundParameters.TryGetValue(parameterName, out value))
            return false;
        return LanguagePrimitives.IsTrue(value);
    }
}
