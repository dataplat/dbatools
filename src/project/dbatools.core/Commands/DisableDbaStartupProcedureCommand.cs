#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes stored procedures from SQL Server's automatic startup execution list
/// </summary>
/// <para>
/// Prevents stored procedures from automatically executing when the SQL Server service starts by clearing their startup designation in the master database.
/// This is essential when troubleshooting startup issues or removing procedures that were previously configured to run at service startup.
/// Equivalent to running sp_procoption with @OptionValue = off, but provides object-based management with detailed status reporting.
/// Returns enhanced SMO StoredProcedure objects showing the action results and current startup status.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Disable-DbaStartupProcedure -SqlInstance SqlBox1\Instance2 -StartupProcedure '[dbo].[StartUpProc1]'
/// </code>
/// <para>
/// Attempts to clear the automatic execution of the procedure '[dbo].[StartUpProc1]' in the master database of SqlBox1\Instance2 when the instance is started.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $cred = Get-Credential sqladmin
/// PS C:\&gt; Disable-DbaStartupProcedure -SqlInstance winserver\sqlexpress, sql2016 -SqlCredential $cred -StartupProcedure '[dbo].[StartUpProc1]'
/// </code>
/// <para>
/// Attempts to clear the automatic execution of the procedure '[dbo].[StartUpProc1]' in the master database of winserver\sqlexpress and sql2016 when the instance is started. Connects using sqladmin credential
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaStartupProcedure -SqlInstance sql2016 | Disable-DbaStartupProcedure
/// </code>
/// <para>
/// Get all startup procedures for the sql2016 instance and disables them by piping to Disable-DbaStartupProcedure
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Procedure, Startup, StartupProcedure
/// Author: Patrick Flynn (@sqllensman)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Disable-DbaStartupProcedure" />
[Cmdlet(VerbsLifecycle.Disable, "DbaStartupProcedure", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "Default")]
public sealed class DisableDbaStartupProcedureCommand : DbaBaseCmdlet
{
    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Specifies the stored procedure names to remove from automatic startup execution. Accepts schema-qualified names like '[dbo].[MyStartupProc]'.
    /// Use this when you know the specific procedure names that need their startup designation disabled.
    /// </para>
    [Parameter(Position = 2)]
    public string[]? StartupProcedure { get; set; }

    /// <para>
    /// Accepts stored procedure objects from Get-DbaStartupProcedure via pipeline input.
    /// Use this when working with the results of Get-DbaStartupProcedure to disable multiple startup procedures at once.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public object[]? InputObject { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        List<StoredProcedure> procedures = new List<StoredProcedure>();
        if (TestBound(nameof(InputObject)))
        {
            foreach (object input in InputObject ?? Array.Empty<object>())
                procedures.Add(LanguagePrimitives.ConvertTo<StoredProcedure>(input));
        }
        else
        {
            if (!TestBound(nameof(SqlInstance)))
            {
                StopFunction("You must supply either a SqlInstance or an InputObject .");
                return;
            }
            if (!TestBound(nameof(StartupProcedure)))
            {
                StopFunction("You must specify one or more Startup Procedures when using the SqlInstance parameter.");
                return;
            }

            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                CancellationToken.ThrowIfCancellationRequested();
                WriteMessage(MessageLevel.Verbose, String.Format("Getting startup procedures for {0}", instance));
                Server? server = Connect(instance);
                if (server is null)
                    continue;
                Microsoft.SqlServer.Management.Smo.Database database = server.Databases["master"];
                foreach (string procedure in StartupProcedure ?? Array.Empty<string>())
                {
                    ImportDbaCsvCommand.ObjectNameParts parts = ImportDbaCsvCommand.GetObjectNameParts(procedure);
                    if (!parts.Parsed)
                    {
                        StopFunction(String.Format("Requested procedure {0} could not be parsed.", procedure),
                            target: server, category: ErrorCategory.InvalidData, continueLoop: true);
                        continue;
                    }
                    StoredProcedure? storedProcedure = database.StoredProcedures[parts.Name, parts.Schema ?? "dbo"];
                    if (storedProcedure is null)
                    {
                        StopFunction(String.Format("Requested procedure {0} does not exist.", procedure),
                            target: server, category: ErrorCategory.InvalidData, continueLoop: true);
                        continue;
                    }
                    WriteMessage(MessageLevel.Verbose, String.Format("Adding {0} {1} for {2}", parts.Name, parts.Schema, instance));
                    procedures.Add(storedProcedure);
                }
            }
        }

        foreach (StoredProcedure procedure in procedures)
        {
            CancellationToken.ThrowIfCancellationRequested();
            if (procedure.Parent.Parent.DatabaseEngineType == Microsoft.SqlServer.Management.Common.DatabaseEngineType.SqlAzureDatabase)
            {
                // Use the same connection refusal for supplied SMO objects as for SqlInstance.
                if (Connect(new DbaInstanceParameter(procedure.Parent.Parent)) is null)
                    continue;
            }
            bool status;
            string note;
            try
            {
                if (!procedure.Startup)
                {
                    WriteMessage(MessageLevel.Verbose, "No work being performed. Startup property already False");
                    status = false;
                    note = "Action Disable already performed";
                }
                else if (ShouldProcess(procedure.Parent.Parent.Name, String.Format("Setting Startup status of [{0}].[{1}] to False",
                    procedure.Schema.Replace("]", "]]"), procedure.Name.Replace("]", "]]"))))
                {
                    procedure.Startup = false;
                    procedure.Alter();
                    status = true;
                    note = "Disable succeded";
                }
                else
                {
                    status = false;
                    note = "Disable skipped";
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception)
            {
                // The pinned function reports alteration failures through the result, even with EnableException.
                // Alter can fail after Startup changed only in the SMO cache.
                procedure.Refresh();
                status = false;
                note = "Disable failed";
            }
            Emit(procedure, status, note);
        }
    }

    private Server? Connect(DbaInstanceParameter instance)
    {
        SmoConnectionRequest request = new SmoConnectionRequest
        {
            Instance = instance,
            SqlCredential = SqlCredential,
            AzureUnsupported = true,
            BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "AzureUnsupported" },
            MessageCallback = (level, text) => WriteAttributedMessage("Connect-DbaInstance", level, text)
        };
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            Server server = ConnectionService.GetServer(request);
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception exception)
        {
            StopFunction("Failure", errorRecord: new ErrorRecord(exception, "dbatools_Disable-DbaStartupProcedure",
                ErrorCategory.ConnectionError, instance), target: instance, category: ErrorCategory.ConnectionError, continueLoop: true);
            return null;
        }
    }

    private void Emit(StoredProcedure procedure, bool status, string note)
    {
        PSObject output = PSObject.AsPSObject(procedure);
        foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance", "Database", "Action", "Status", "Note" })
            output.Properties.Remove(property);
        OutputHelper.AddInstanceProperties(output, procedure.Parent.Parent);
        output.Properties.Add(new PSNoteProperty("Database", procedure.Parent.Name));
        output.Properties.Add(new PSNoteProperty("Action", "Disable"));
        output.Properties.Add(new PSNoteProperty("Status", status));
        output.Properties.Add(new PSNoteProperty("Note", note));
        OutputHelper.SetDefaultDisplayPropertySet(output,
            "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "Name", "Startup", "Action", "Status", "Note");
        WriteObject(output);
    }
}
