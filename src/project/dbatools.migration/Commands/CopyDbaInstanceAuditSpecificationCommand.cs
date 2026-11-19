#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Copies server audit specifications between instances through SMO. Port of public/Copy-DbaInstanceAuditSpecification.ps1.
/// <summary>Copies server audit specifications from one SQL Server instance to another for compliance standardization.</summary>
[Cmdlet(VerbsCommon.Copy, "DbaInstanceAuditSpecification", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaInstanceAuditSpecificationCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance. Requires sysadmin and SQL Server 2008 or higher.</summary>
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

    /// <summary>Only copy the server audit specifications with these names.</summary>
    [Parameter(Position = 4)]
    public object[]? AuditSpecification { get; set; }

    /// <summary>Skip the server audit specifications with these names.</summary>
    [Parameter(Position = 5)]
    public object[]? ExcludeAuditSpecification { get; set; }

    /// <summary>Drop and recreate audit specifications that already exist on the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Server? _source;
    private ServerAuditSpecificationCollection? _specifications;

    protected override void BeginProcessing()
    {
        _source = Connect(Source, SourceSqlCredential, continueLoop: false);
        if (_source is null)
            return;

        if (!IsSysadmin(_source))
        {
            StopFunction(String.Format(CultureInfo.InvariantCulture, "Not a sysadmin on {0}. Quitting.", Source));
            return;
        }

        _specifications = _source.ServerAuditSpecifications;
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted || _source is null || _specifications is null)
            return;

        foreach (DbaInstanceParameter destination in Destination)
        {
            Server? server = Connect(destination, DestinationSqlCredential, continueLoop: true);
            if (server is null)
                continue;

            if (!IsSysadmin(server))
            {
                StopFunction(String.Format(CultureInfo.InvariantCulture, "Not a sysadmin on {0}. Quitting.", destination));
                return;
            }

            if (server.VersionMajor < _source.VersionMajor)
            {
                StopFunction(String.Format(CultureInfo.InvariantCulture, "Migration from version {0} to version {1} is not supported.",
                    server.VersionMajor, _source.VersionMajor));
                return;
            }

            ServerAuditSpecificationCollection destinationSpecifications = server.ServerAuditSpecifications;
            foreach (ServerAuditSpecification specification in _specifications)
            {
                CopySpecification(destination, server, destinationSpecifications, specification);
            }
        }
    }

    /// <summary>One pass of the source's inner foreach; every return is the source's continue.</summary>
    private void CopySpecification(DbaInstanceParameter destination, Server server,
        ServerAuditSpecificationCollection destinationSpecifications, ServerAuditSpecification specification)
    {
        string name = specification.Name;
        DateTime timestamp = DateTime.Now;

        if ((LanguagePrimitives.IsTrue(AuditSpecification) && !InList(name, AuditSpecification)) || InList(name, ExcludeAuditSpecification))
            return;

        server.Audits.Refresh();
        string auditName = specification.AuditName;
        bool auditExists = false;
        foreach (Audit audit in server.Audits)
        {
            if (LanguagePrimitives.Equals(audit.Name, auditName, true))
            {
                auditExists = true;
                break;
            }
        }
        if (!auditExists)
        {
            string missing = String.Format(CultureInfo.InvariantCulture, "Audit {0} does not exist on {1}. Skipping {2}.", auditName, destination, name);
            if (Approve(destination, missing))
            {
                WriteMessage(MessageLevel.Warning, missing);
                Emit(server, name, timestamp, "Skipped", missing);
            }
            return;
        }

        bool exists = false;
        foreach (ServerAuditSpecification current in destinationSpecifications)
        {
            if (LanguagePrimitives.Equals(current.Name, name, true))
            {
                exists = true;
                break;
            }
        }
        if (exists)
        {
            if (!Force)
            {
                string skipped = String.Format(CultureInfo.InvariantCulture, "Server audit {0} exists at destination. Use -Force to drop and migrate.", name);
                if (Approve(destination, skipped))
                {
                    WriteMessage(MessageLevel.Verbose, skipped);
                    Emit(server, name, timestamp, "Skipped", "Already exists on destination");
                }
                return;
            }

            if (Approve(destination, String.Format(CultureInfo.InvariantCulture, "Dropping server audit {0} and recreating", name)))
            {
                ErrorRecord? dropFault = null;
                WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Dropping server audit {0}", name));
                ServerAuditSpecification? existing = server.ServerAuditSpecifications[name];
                if (existing is null)
                    dropFault = NullMethodRecord();
                else
                {
                    try
                    {
                        existing.Drop();
                    }
                    catch (Exception ex) when (ex is not PipelineStoppedException)
                    {
                        dropFault = MethodRecord(ex, "Drop", 0);
                    }
                }
                if (dropFault is not null)
                {
                    Emit(server, name, timestamp, "Failed", MessageService.GetErrorMessage(dropFault));
                    WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
                        "Issue dropping audit specification {0} on {1} | {2}", name, destination, dropFault));
                    return;
                }
            }
        }

        if (!Approve(destination, String.Format(CultureInfo.InvariantCulture, "Creating server audit {0}", name)))
            return;

        ErrorRecord? createFault = null;
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Copying server audit {0}", name));
        string? sql = null;
        try
        {
            // PS: $auditSpec.Script() | Out-String
            StringBuilder script = new StringBuilder();
            foreach (string? line in specification.Script())
                script.AppendLine(line);
            sql = script.ToString();
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            createFault = MethodRecord(ex, "Script", 0);
        }

        if (sql is not null)
        {
            WriteMessage(MessageLevel.Debug, sql);
            try
            {
                // PS: $null = $destServer.Query($sql), the dbatools Server.Query script method.
                server.ConnectionContext.ExecuteWithResults(sql);
            }
            catch (Exception ex) when (ex is not PipelineStoppedException)
            {
                createFault = QueryRecord(ex);
            }
        }

        if (createFault is null)
        {
            Emit(server, name, timestamp, "Successful", null);
            return;
        }
        Emit(server, name, timestamp, "Failed", MessageService.GetErrorMessage(createFault));
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture,
            "Issue creating audit specification {0} on {1} | {2}", name, destination, createFault));
    }

    /// <summary>PS: Connect-DbaInstance -MinimumVersion 10 in a try whose catch is Stop-Function "Failure" -Category ConnectionError.</summary>
    private Server? Connect(DbaInstanceParameter target, PSCredential? credential, bool continueLoop)
    {
        SmoConnectionRequest request = new SmoConnectionRequest
        {
            Instance = target,
            SqlCredential = credential,
            MinimumVersion = 10,
            // Server audit specifications exist only in SQL Server and Managed Instance, so Azure SQL Database is
            // refused as Connect-DbaInstance -AzureUnsupported does: correction azure-unsupported.
            AzureUnsupported = true,
            BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "MinimumVersion" },
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
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            ErrorRecord record = new ErrorRecord(ex, "dbatools_Copy-DbaInstanceAuditSpecification", ErrorCategory.ConnectionError, target);
            StopFunction("Failure", target: target, errorRecord: record, category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    /// <summary>PS private Test-SqlSa on a Server: ConnectionContext.FixedServerRoles -match "SysAdmin"; any failure is $false.</summary>
    private static bool IsSysadmin(Server server)
    {
        try
        {
            return Regex.IsMatch(server.ConnectionContext.FixedServerRoles.ToString(), "SysAdmin", RegexOptions.IgnoreCase);
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            // Test-SqlSa: catch { return $false }
            return false;
        }
    }

    /// <summary>PS: $name -in $list, case-insensitive with the name on the left.</summary>
    private static bool InList(string name, object[]? list)
    {
        if (list is null)
            return false;
        foreach (object? value in list)
        {
            if (LanguagePrimitives.Equals(name, value, true))
                return true;
        }
        return false;
    }

    /// <summary>PS: if ($Force) { $ConfirmPreference = 'none' } in begin, so -Force never prompts.</summary>
    private bool Approve(DbaInstanceParameter target, string action)
    {
        if (!Force)
            return ShouldProcess(target.ToString(), action);
        // Binary cmdlets share the caller's preference scope, unlike advanced functions.
        object? previous = SessionState.PSVariable.GetValue("ConfirmPreference");
        try
        {
            SessionState.PSVariable.Set("ConfirmPreference", ConfirmImpact.None);
            return ShouldProcess(target.ToString(), action);
        }
        finally
        {
            SessionState.PSVariable.Set("ConfirmPreference", previous);
        }
    }

    /// <summary>The source's $copyAuditSpecStatus | Select-DefaultView ... -TypeName MigrationObject.</summary>
    private void Emit(Server destination, string name, DateTime timestamp, string status, string? notes)
    {
        PSObject result = new PSObject();
        result.Properties.Add(new PSNoteProperty("SourceServer", _source!.Name));
        result.Properties.Add(new PSNoteProperty("DestinationServer", destination.Name));
        result.Properties.Add(new PSNoteProperty("Type", "Server Audit Specification"));
        result.Properties.Add(new PSNoteProperty("Name", name));
        result.Properties.Add(new PSNoteProperty("Status", status));
        result.Properties.Add(new PSNoteProperty("Notes", notes));
        result.Properties.Add(new PSNoteProperty("DateTime", new DbaDateTime(timestamp)));
        OutputHelper.InsertTypeName(result, "MigrationObject");
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        WriteObject(result);
    }

    /// <summary>The record a script catch receives for a failed .NET method call.</summary>
    private static ErrorRecord MethodRecord(Exception failure, string method, int argumentCount)
    {
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"", method, argumentCount, failure.Message), failure);
        return new ErrorRecord(call, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    /// <summary>The record a script catch receives for a method call on $null.</summary>
    private static ErrorRecord NullMethodRecord()
    {
        return new ErrorRecord(new RuntimeException("You cannot call a method on a null-valued expression."),
            "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null);
    }

    /// <summary>
    /// The record a failed Server.Query call raises: its catch concatenates the messages of the failure's
    /// exception chain without separators and throws that string, which the method binder reports as the
    /// ScriptMethodRuntimeException of 'Exception calling "Query" with "1" argument(s)'.
    /// </summary>
    private static ErrorRecord QueryRecord(Exception failure)
    {
        StringBuilder message = new StringBuilder();
        Exception current = failure;
        while (current.InnerException is not null)
        {
            message.Append(current.Message);
            current = current.InnerException;
        }
        message.Append(current.Message);
        string text = message.ToString();
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", text), new RuntimeException(text, failure));
        return new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }
}
