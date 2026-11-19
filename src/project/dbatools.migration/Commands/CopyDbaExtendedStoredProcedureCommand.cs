#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>Copies custom Extended Stored Procedures (XPs) and their associated DLL files between SQL Server instances</summary>
[Cmdlet(VerbsCommon.Copy, "DbaExtendedStoredProcedure", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaExtendedStoredProcedureCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance. Requires sysadmin and SQL Server 2005 or higher.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The destination SQL Server instances.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only copy the Extended Stored Procedures with these names.</summary>
    [Parameter(Position = 4)]
    public string[]? ExtendedProcedure { get; set; }

    /// <summary>Skip the Extended Stored Procedures with these names.</summary>
    [Parameter(Position = 5)]
    public string[]? ExcludeExtendedProcedure { get; set; }

    /// <summary>Where the DLL files are copied to; the destination Binn directory by default.</summary>
    [Parameter(Position = 6)]
    public string? DestinationPath { get; set; }

    /// <summary>Drop and recreate procedures that already exist on the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Custom Extended Stored Procedures, read on the connection's database (master by default), as the pinned
    // query does through Server.Query.
    // Upstream correction (wrong data): sys.sql_modules has no row for an extended stored procedure, so the pinned
    // DllPath is always NULL. The DLL path is sys.extended_procedures.dll_name (Microsoft Learn, sys.extended_procedures).
    private const string ProcedureQuery = @"SELECT
    p.name AS ProcedureName,
    SCHEMA_NAME(p.schema_id) AS SchemaName,
    p.object_id,
    COALESCE(m.definition, e.dll_name) AS DllPath
FROM sys.procedures p
INNER JOIN sys.all_objects o ON p.object_id = o.object_id
LEFT JOIN sys.sql_modules m ON p.object_id = m.object_id
LEFT JOIN sys.extended_procedures e ON p.object_id = e.object_id
WHERE p.type = 'X'
    AND p.is_ms_shipped = 0
ORDER BY p.name";

    // The pinned statements. Upstream correction (injection): the pinned code placed the procedure name and the
    // server-supplied DLL path into these N'...' literals unescaped; each value is escaped (' to '') by Literal.
    private const string DropStatement = "EXEC dbo.sp_dropextendedproc @functname = N'{0}'";
    private const string HelpStatement = "EXEC dbo.sp_helpextendedproc @funcname = N'{0}'";
    private const string CreateStatement = "EXEC dbo.sp_addextendedproc @functname = N'{0}', @dllname = N'{1}'";

    private Server? _source;
    private List<DataRow> _sourceProcedures = new();

    protected override void BeginProcessing()
    {
        _source = Connect(Source, SourceSqlCredential, false);
        if (_source is null)
            return;

        try
        {
            _sourceProcedures = Query(_source, ProcedureQuery);
        }
        catch (ServerQueryException failure)
        {
            StopFunction("Failed to query Extended Stored Procedures from source: " + failure.Message, target: Source, errorRecord: failure.Record());
            return;
        }

        if (_sourceProcedures.Count == 0)
            WriteMessage(MessageLevel.Verbose, "No custom Extended Stored Procedures found on source server");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _source is null)
            return;

        foreach (DbaInstanceParameter destInstance in Destination)
        {
            CancellationToken.ThrowIfCancellationRequested();
            Server? destServer = Connect(destInstance, DestinationSqlCredential, true);
            if (destServer is null)
                continue;

            List<DataRow> destProcedures;
            try
            {
                destProcedures = Query(destServer, ProcedureQuery);
            }
            catch (ServerQueryException failure)
            {
                StopFunction("Failed to query Extended Stored Procedures from destination: " + failure.Message, target: destInstance,
                    errorRecord: failure.Record(), continueLoop: true);
                continue;
            }

            string? destBinnPath;
            if (String.IsNullOrEmpty(DestinationPath))
                destBinnPath = BinnPath(destServer, "Could not determine destination Binn directory. DLL files will not be copied.");
            else
                destBinnPath = DestinationPath;
            string? sourceBinnPath = BinnPath(_source, "Could not determine source Binn directory. DLL files will not be copied.");

            foreach (DataRow currentXP in _sourceProcedures)
            {
                CancellationToken.ThrowIfCancellationRequested();
                CopyProcedure(currentXP, destInstance, destServer, destProcedures, sourceBinnPath, destBinnPath);
            }
        }
    }

    private void CopyProcedure(DataRow currentXP, DbaInstanceParameter destInstance, Server destServer, List<DataRow> destProcedures,
        string? sourceBinnPath, string? destBinnPath)
    {
        string xpName = Text(currentXP["ProcedureName"]) ?? "";
        string xpSchema = Text(currentXP["SchemaName"]) ?? "";
        string xpFullName = xpSchema + "." + xpName;
        PSObject copyXPStatus = Status(destServer, xpName, xpSchema);

        if (LanguagePrimitives.IsTrue(ExtendedProcedure) && !Contains(ExtendedProcedure!, xpName))
            return;
        if (LanguagePrimitives.IsTrue(ExcludeExtendedProcedure) && Contains(ExcludeExtendedProcedure!, xpName))
            return;

        bool existsOnDest = false;
        foreach (DataRow destXP in destProcedures)
        {
            if (LanguagePrimitives.Equals(destXP["ProcedureName"], xpName, true, CultureInfo.InvariantCulture))
            {
                existsOnDest = true;
                break;
            }
        }

        if (existsOnDest)
        {
            if (!Force)
            {
                string action = String.Format("Extended Stored Procedure {0} exists at destination. Use -Force to drop and migrate.", xpFullName);
                if (Confirm(destInstance, action))
                {
                    Emit(copyXPStatus, "Skipped", "Already exists on destination");
                    WriteMessage(MessageLevel.Verbose, action);
                }
                return;
            }
            if (Confirm(destInstance, String.Format("Dropping Extended Stored Procedure {0} and recreating", xpFullName)))
            {
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Dropping Extended Stored Procedure " + xpFullName);
                    Query(destServer, String.Format(CultureInfo.InvariantCulture, DropStatement, Literal(xpFullName)));
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    Emit(copyXPStatus, "Failed", MessageService.GetErrorMessage(Record(failure)));
                    WriteMessage(MessageLevel.Verbose, String.Format("Issue dropping Extended Stored Procedure {0} on {1} | {2}", xpFullName, destInstance, failure.Message));
                    return;
                }
            }
        }

        if (!Confirm(destInstance, "Creating Extended Stored Procedure " + xpFullName))
            return;

        try
        {
            string? sourceDllPath = Text(currentXP["DllPath"]);
            if (String.IsNullOrEmpty(sourceDllPath))
            {
                List<DataRow> dllInfo = Query(_source!, String.Format(CultureInfo.InvariantCulture, HelpStatement, Literal(xpFullName)));
                // Upstream correction (wrong data): the pinned $dllInfo[0].DLL indexes a single returned DataRow as
                // its first column (the procedure name), which has no DLL; the dll column of the first row is read.
                if (dllInfo.Count > 0)
                    sourceDllPath = Text(dllInfo[0]["dll"]);
            }

            if (String.IsNullOrEmpty(sourceDllPath))
            {
                Emit(copyXPStatus, "Failed", "Could not determine DLL path for Extended Stored Procedure");
                WriteMessage(MessageLevel.Warning, String.Format("Could not determine DLL path for Extended Stored Procedure {0}. Manual intervention required.", xpFullName));
                return;
            }

            string dllFileName = Leaf(sourceDllPath!);
            bool dllCopied = false;
            string? dllCopyNotes = null;
            string? destDllFullPath = null;

            if (!String.IsNullOrEmpty(sourceBinnPath) && !String.IsNullOrEmpty(destBinnPath))
            {
                string sourceDllFullPath = JoinPath(sourceBinnPath!, dllFileName);
                destDllFullPath = JoinPath(destBinnPath!, dllFileName);
                string sourceComputerName = SmoServerExtensions.GetComputerName(_source!);
                string destComputerName = SmoServerExtensions.GetComputerName(destServer);
                try
                {
                    // UNC paths for remote copying: the drive colon becomes the administrative share's dollar sign.
                    string sourceUncPath = "\\\\" + sourceComputerName + "\\" + sourceDllFullPath.Replace(":", "$");
                    string destUncPath = "\\\\" + destComputerName + "\\" + destDllFullPath.Replace(":", "$");
                    if (File.Exists(sourceUncPath) || Directory.Exists(sourceUncPath))
                    {
                        WriteMessage(MessageLevel.Verbose, String.Format("Copying DLL from {0} to {1}", sourceUncPath, destUncPath));
                        ForceCopy(sourceUncPath, destUncPath);
                        dllCopied = true;
                        WriteMessage(MessageLevel.Verbose, "Successfully copied DLL file");
                    }
                    else
                    {
                        dllCopyNotes = "Source DLL not found at expected path: " + sourceDllFullPath;
                        WriteMessage(MessageLevel.Warning, dllCopyNotes);
                    }
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    dllCopyNotes = String.Format("Failed to copy DLL file: {0}. DLL may need to be copied manually or recompiled for OS/SQL version compatibility.", failure.Message);
                    WriteMessage(MessageLevel.Warning, dllCopyNotes);
                }
            }
            else
            {
                dllCopyNotes = "Could not determine source or destination Binn paths. DLL must be copied manually.";
                WriteMessage(MessageLevel.Warning, dllCopyNotes);
            }

            string destDllPath = dllCopied ? destDllFullPath! : sourceDllPath!;
            string createSql = String.Format(CultureInfo.InvariantCulture, CreateStatement, Literal(xpFullName), Literal(destDllPath));

            WriteMessage(MessageLevel.Verbose, "Creating Extended Stored Procedure " + xpFullName);
            WriteMessage(MessageLevel.Debug, createSql);
            Query(destServer, createSql);

            Emit(copyXPStatus, dllCopied ? "Successful" : "Successful (DLL not copied)", dllCopyNotes);
            if (!dllCopied)
                WriteMessage(MessageLevel.Warning, String.Format("Extended Stored Procedure {0} created but DLL was not copied. You may need to manually copy the DLL file and ensure it's compatible with the destination OS/SQL version.", xpFullName));
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            Emit(copyXPStatus, "Failed", MessageService.GetErrorMessage(Record(failure)));
            WriteMessage(MessageLevel.Verbose, String.Format("Issue creating Extended Stored Procedure {0} on {1} | {2}", xpFullName, destInstance, failure.Message));
        }
    }

    private Server? Connect(DbaInstanceParameter instance, PSCredential? credential, bool continueLoop)
    {
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            Server server = ConnectionService.GetServer(new SmoConnectionRequest
            {
                Instance = instance,
                SqlCredential = credential,
                MinimumVersion = 9,
                // Upstream correction (azure-unsupported): Azure SQL Database has no extended stored procedures; it is
                // refused as Connect-DbaInstance -AzureUnsupported does.
                AzureUnsupported = true,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
            });
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            StopFunction("Failure", target: instance,
                errorRecord: new ErrorRecord(failure, "dbatools_Copy-DbaExtendedStoredProcedure", ErrorCategory.ConnectionError, instance),
                category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    // Copy-Item -Path $sourceUncPath -Destination $destUncPath -Force -ErrorAction Stop for one file, as the
    // FileSystem provider does it: copy with overwrite; on an access denial clear the destination's ReadOnly and
    // Hidden attributes and copy again. When the attributes cannot be cleared, the original denial is the error.
    private static void ForceCopy(string source, string destination)
    {
        try
        {
            File.Copy(source, destination, true);
        }
        catch (UnauthorizedAccessException)
        {
            bool cleared;
            try
            {
                FileInfo destinationItem = new FileInfo(destination);
                destinationItem.Attributes &= ~(FileAttributes.ReadOnly | FileAttributes.Hidden);
                cleared = true;
            }
            catch (Exception attributeFailure) when (attributeFailure is FileNotFoundException || attributeFailure is DirectoryNotFoundException
                || attributeFailure is System.Security.SecurityException || attributeFailure is ArgumentException || attributeFailure is IOException)
            {
                // The provider writes the original access denial when it cannot force the copy.
                cleared = false;
            }

            if (!cleared)
                throw;
            File.Copy(source, destination, true);
        }
    }

    // $server.RootDirectory + "\Binn"; a failing read warns and copies no DLL.
    private string? BinnPath(Server server, string warning)
    {
        try
        {
            return server.RootDirectory + "\\Binn";
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WriteMessage(MessageLevel.Warning, warning);
            return null;
        }
    }

    // -Force sets $ConfirmPreference to 'none' for the whole function in the pinned begin block.
    private bool Confirm(DbaInstanceParameter instance, string action)
    {
        if (!Force)
            return ShouldProcess(instance.ToString(), action);
        object? previousPreference = SessionState.PSVariable.GetValue("ConfirmPreference");
        try
        {
            SessionState.PSVariable.Set("ConfirmPreference", ConfirmImpact.None);
            return ShouldProcess(instance.ToString(), action);
        }
        finally
        {
            SessionState.PSVariable.Set("ConfirmPreference", previousPreference);
        }
    }

    // Server.Query: the rows of the first result table, none when the batch returns no table.
    private static List<DataRow> Query(Server server, string sql)
    {
        DataSet result;
        try
        {
            result = server.ConnectionContext.ExecuteWithResults(sql);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            throw new ServerQueryException(failure);
        }
        List<DataRow> rows = new();
        if (result.Tables.Count > 0)
        {
            foreach (DataRow row in result.Tables[0].Rows)
                rows.Add(row);
        }
        return rows;
    }

    private static ErrorRecord Record(Exception failure)
    {
        if (failure is ServerQueryException query)
            return query.Record();
        if (failure is IContainsErrorRecord contained)
            return contained.ErrorRecord;
        return new ErrorRecord(failure, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    // The text of an N'...' literal: each single quote doubled.
    private static string Literal(string text)
    {
        return text.Replace("'", "''");
    }

    private static string? Text(object value)
    {
        if (value is null || value is DBNull)
            return null;
        return Convert.ToString(value, CultureInfo.InvariantCulture);
    }

    private static bool Contains(string[] values, string name)
    {
        foreach (string value in values)
        {
            if (LanguagePrimitives.Equals(value, name, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    // Split-Path -Leaf of a Windows path.
    private static string Leaf(string path)
    {
        string trimmed = path.TrimEnd('\\', '/');
        int index = trimmed.LastIndexOfAny(new[] { '\\', '/' });
        return index < 0 ? trimmed : trimmed.Substring(index + 1);
    }

    // Join-Path of a Windows path: one separator between parent and child.
    private static string JoinPath(string parent, string child)
    {
        return parent.TrimEnd('\\', '/') + "\\" + child.TrimStart('\\', '/');
    }

    private PSObject Status(Server destServer, string name, string schema)
    {
        PSObject result = new();
        result.Properties.Add(new PSNoteProperty("SourceServer", _source!.Name));
        result.Properties.Add(new PSNoteProperty("DestinationServer", destServer.Name));
        result.Properties.Add(new PSNoteProperty("Name", name));
        result.Properties.Add(new PSNoteProperty("Schema", schema));
        result.Properties.Add(new PSNoteProperty("Type", "Extended Stored Procedure"));
        result.Properties.Add(new PSNoteProperty("Status", null));
        result.Properties.Add(new PSNoteProperty("Notes", null));
        result.Properties.Add(new PSNoteProperty("DateTime", new DbaDateTime(DateTime.Now)));
        return result;
    }

    // Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
    private void Emit(PSObject result, string status, string? notes)
    {
        result.Properties["Status"].Value = status;
        result.Properties["Notes"].Value = notes;
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        OutputHelper.InsertTypeName(result, "MigrationObject");
        WriteObject(result);
    }

    // The fault the pinned catch receives from $server.Query: the script method joins the messages of the failure
    // chain and throws that text, which the engine reports as a method fault of "Query" called with one argument.
    private sealed class ServerQueryException : Exception
    {
        private readonly string _text;

        public ServerQueryException(Exception failure)
            : base(Describe(Join(failure)), failure)
        {
            _text = Join(failure);
        }

        public ErrorRecord Record()
        {
            MethodInvocationException fault = new(Describe(_text), new RuntimeException(_text));
            return new ErrorRecord(fault, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
        }

        private static string Describe(string text)
        {
            return String.Format(CultureInfo.InvariantCulture, "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", text);
        }

        private static string Join(Exception failure)
        {
            string message = "";
            Exception current = failure;
            while (current.InnerException is not null)
            {
                message += current.Message;
                current = current.InnerException;
            }
            return message + current.Message;
        }
    }
}
