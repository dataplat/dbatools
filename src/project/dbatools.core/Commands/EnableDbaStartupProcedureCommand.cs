#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Configures stored procedures in the master database to execute automatically when SQL Server service starts
/// </summary>
[Cmdlet(VerbsLifecycle.Enable, "DbaStartupProcedure", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "Default")]
public sealed class EnableDbaStartupProcedureCommand : DbaInstanceCmdlet
{
    /// <summary>
    /// The target SQL Server instance or instances.
    /// </summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>
    /// <para>Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).</para>
    /// <para>Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.</para>
    /// <para>For MFA support, please use Connect-DbaInstance.</para>
    /// </summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>
    /// Specifies the stored procedure(s) in the master database to enable for automatic startup execution. Accepts schema-qualified names like '[dbo].[MyStartupProc]' or simple names.
    /// Use this when you need specific procedures to run automatically after SQL Server service restarts, such as initialization scripts, monitoring setup, or custom configuration procedures.
    /// Multiple procedures can be specified as an array to enable several startup procedures in a single operation.
    /// </summary>
    [Parameter(Position = 2)]
    public object[]? StartupProcedure { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted || SqlInstance is null)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, azureUnsupported: true);
            if (server is null)
                continue;
            WriteMessage(MessageLevel.Verbose, String.Format("Getting startup procedures for {0}", instance));
            Microsoft.SqlServer.Management.Smo.Database database = server.Databases["master"];

            foreach (object procedure in StartupProcedure ?? Array.Empty<object>())
            {
                string name = LanguagePrimitives.ConvertTo<string>(procedure);
                WriteMessage(MessageLevel.Verbose, String.Format("Preparing to get object parts for {0}", name));
                ImportDbaCsvCommand.ObjectNameParts parts = ImportDbaCsvCommand.GetObjectNameParts(name);
                if (!parts.Parsed)
                {
                    StopFunction(String.Format("Requested procedure {0} could not be parsed.", name),
                        target: server, category: ErrorCategory.InvalidData, continueLoop: true);
                    continue;
                }

                StoredProcedure? storedProcedure = database.StoredProcedures[parts.Name, parts.Schema ?? "dbo"];
                if (storedProcedure is null)
                {
                    StopFunction(String.Format("Requested procedure {0} does not exist.", name),
                        target: server, category: ErrorCategory.InvalidData, continueLoop: true);
                    continue;
                }

                bool status;
                string note;
                try
                {
                    if (storedProcedure.Startup)
                    {
                        WriteMessage(MessageLevel.Verbose, "No work being performed. Startup property already True");
                        status = false;
                        note = "Action Enable already performed";
                    }
                    else if (ShouldProcess(instance.ToString(), String.Format("Setting Startup status of {0} to True", name)))
                    {
                        storedProcedure.Startup = true;
                        storedProcedure.Alter();
                        status = true;
                        note = "Enable succeded";
                    }
                    else
                    {
                        status = false;
                        note = "Enable skipped";
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception)
                {
                    status = false;
                    note = "Enable failed";
                }

                PSObject output = PSObject.AsPSObject(storedProcedure);
                foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance", "Database", "Action", "Status", "Note" })
                    output.Properties.Remove(property);
                OutputHelper.AddInstanceProperties(output, server);
                output.Properties.Add(new PSNoteProperty("Database", database.Name));
                output.Properties.Add(new PSNoteProperty("Action", "Enable"));
                output.Properties.Add(new PSNoteProperty("Status", status));
                output.Properties.Add(new PSNoteProperty("Note", note));
                OutputHelper.SetDefaultDisplayPropertySet(output,
                    "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name", "Startup", "Action", "Status", "Note");
                WriteObject(output);
            }
        }
    }
}
