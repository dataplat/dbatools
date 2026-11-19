#nullable enable

using System;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves the stored procedures that SQL Server runs at startup directly through SMO.</summary>
[Cmdlet(VerbsCommon.Get, "DbaStartupProcedure", DefaultParameterSetName = "Default")]
public sealed class GetDbaStartupProcedureCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Startup procedure name(s) to filter by (schema.name).</summary>
    [Parameter(Position = 2)]
    public string[]? StartupProcedure { get; set; }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;
            Server? server = ConnectInstance(instance);
            if (server is null)
                continue;

            // The source interpolates an undefined $servername here.
            WriteMessage(MessageLevel.Verbose, "Getting startup procedures for ");

            DataTable startupProcs;
            try
            {
                startupProcs = server.EnumStartupProcedures();
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception exception)
            {
                // caller-try: terminate -- continuing would reuse the previous instance's startup procedure list for this server
                ThrowTerminatingError(MethodFault("EnumStartupProcedures", exception)); // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
                return;
            }

            if (startupProcs.Rows.Count == 0)
                continue;

            SmoDatabase? db = server.Databases["master"];
            foreach (DataRow startupProc in startupProcs.Rows)
            {
                if (Interrupted)
                    return;
                if (TestBound(nameof(StartupProcedure)) && !IsRequested(startupProc))
                    continue;

                if (db is null)
                {
                    // caller-try: terminate -- the source's .Item() call on a missing master database emits nothing usable
                    ThrowTerminatingError(new ErrorRecord( // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
                        new RuntimeException("You cannot call a method on a null-valued expression."),
                        "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null));
                    return;
                }
                string procName = LanguagePrimitives.ConvertTo<string>(startupProc["Name"]);
                string procSchema = LanguagePrimitives.ConvertTo<string>(startupProc["Schema"]);
                StoredProcedure? proc = db.StoredProcedures[procName, procSchema];
                if (proc is null)
                {
                    // The source's Add-Member binder fault; its Add-Member owner suffix is not reproduced.
                    // caller-try: terminate -- baseline 20261023T2026151276901Z terminates with -EnableException; non-EnableException unmeasured; gate 5 default
                    ThrowTerminatingError(new ErrorRecord( // style-ok: cs-raw-streams binder fault outside Stop-Function, as in the source
                        new ParameterBindingException("Cannot bind argument to parameter 'InputObject' because it is null."),
                        "ParameterArgumentValidationErrorNullNotAllowed",
                        ErrorCategory.InvalidData, null));
                    return;
                }

                PSObject output = PSObject.AsPSObject(proc);
                // SMO reuses collection members, so repeated reads replace the Add-Member -Force notes.
                foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance", "Database", "ObjectId" })
                    output.Properties.Remove(property);
                OutputHelper.AddInstanceProperties(output, server);
                output.Properties.Add(new PSNoteProperty("Database", db.Name));
                OutputHelper.AddAliasProperty(output, "ObjectId", "ID");
                OutputHelper.SetDefaultDisplayPropertySet(output,
                    "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "ObjectId", "CreateDate",
                    "DateLastModified", "Name", "ImplementationType", "Startup");
                WriteObject(output);
            }
        }
    }

    /// <summary>The source's -StartupProcedure loop: the first parsed name matching name and schema wins.</summary>
    private bool IsRequested(DataRow startupProc)
    {
        foreach (string proc in StartupProcedure ?? Array.Empty<string>())
        {
            ImportDbaCsvCommand.ObjectNameParts procParts = ImportDbaCsvCommand.GetObjectNameParts(proc ?? "");
            if (!procParts.Parsed)
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Requested procedure {0} could not be parsed.", proc));
                continue;
            }
            // The help documents a one-part name as schema dbo; the source compared the null schema
            // and never matched (correction recorded in quality/corrections).
            string requestedSchema = procParts.Schema ?? "dbo";
            // PS -eq: the parsed part is the left operand and compares case-insensitively.
            if (LanguagePrimitives.Equals(procParts.Name, startupProc["Name"], true, CultureInfo.InvariantCulture) &&
                LanguagePrimitives.Equals(requestedSchema, startupProc["Schema"], true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    /// <summary>The ErrorRecord PowerShell builds when a .NET method call in the source throws.</summary>
    private static ErrorRecord MethodFault(string method, Exception exception)
    {
        MethodInvocationException wrapped = new MethodInvocationException(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"{0}\" with \"0\" argument(s): \"{1}\"", method, exception.Message), exception);
        return new ErrorRecord(wrapped, exception.GetType().Name, ErrorCategory.NotSpecified, null);
    }
}
