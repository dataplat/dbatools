#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves the Resource Governor classifier function configured for workload group assignment</summary>
/// <remarks>
/// Retrieves the Resource Governor classifier function from master directly through SMO.
/// Corrected upstream wrong-data defect: the source refetches the governors of the WHOLE SqlInstance array
/// on every SqlInstance iteration (Get-DbaResourceGovernor -SqlInstance $SqlInstance) and compares each
/// function name with the member-enumerated $InputObject.ClassifierFunction, so two or more governors in
/// one record compare against their joined text and return nothing. Here every SqlInstance is read once
/// per record and each governor is matched against its own ClassifierFunction on its own server; one
/// governor behaves exactly as the source. The accumulated list stays fresh per record, and the nested
/// Get-DbaResourceGovernor never receives EnableException, so its connection failures always warn under
/// its own name.
/// </remarks>
[Cmdlet(VerbsCommon.Get, "DbaRgClassifierFunction")]
public sealed class GetDbaRgClassifierFunctionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Resource Governor objects piped in from Get-DbaResourceGovernor.</summary>
    [Parameter(ValueFromPipeline = true, Position = 2)]
    public ResourceGovernor[]? InputObject { get; set; }

    protected override void ProcessRecord()
    {
        List<ResourceGovernor?> governors = new(InputObject ?? Array.Empty<ResourceGovernor>());
        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            ResourceGovernor? governor = GetResourceGovernor(instance);
            if (governor is not null)
                governors.Add(governor);
        }

        foreach (ResourceGovernor? resourcegov in governors)
        {
            Server? server = resourcegov?.Parent;
            if (server is null)
            {
                // caller-try: terminate -- the source indexes a null Databases collection before any output
                ThrowTerminatingError(new ErrorRecord( // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
                    new RuntimeException("Cannot index into a null array."), "NullArray", ErrorCategory.InvalidOperation, null));
                return;
            }

            // Each governor is matched against its own classifier name (the source compares the joined list).
            string? comparand = resourcegov!.ClassifierFunction;
            UserDefinedFunction? classifierFunction = null;
            Microsoft.SqlServer.Management.Smo.Database? master = server.Databases["master"];
            if (master is not null)
            {
                foreach (UserDefinedFunction currentFunction in master.UserDefinedFunctions)
                {
                    string fullyQualifiedFunctionName = String.Format(CultureInfo.InvariantCulture, "[{0}].[{1}]", currentFunction.Schema, currentFunction.Name);
                    // PS -eq: case-insensitive string comparison, as in the source.
                    if (LanguagePrimitives.Equals(fullyQualifiedFunctionName, comparand, true, CultureInfo.InvariantCulture))
                        classifierFunction = currentFunction;
                }
            }

            // Select-DefaultView returns nothing for a null function.
            if (classifierFunction is null)
                continue;

            PSObject output = PSObject.AsPSObject(classifierFunction);
            foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance" })
            {
                // Native reads refuse script-backed members instead of running their getters.
                object? value = SmoServerExtensions.GetPSProperty(resourcegov, property);
                output.Properties.Remove(property);
                output.Properties.Add(new PSNoteProperty(property, value));
            }
            output.Properties.Remove("Database");
            output.Properties.Add(new PSNoteProperty("Database", "master"));
            OutputHelper.SetDefaultDisplayPropertySet(output,
                "ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "CreateDate",
                "DateLastModified", "Name", "DataType");
            WriteObject(output);
        }
    }

    /// <summary>
    /// The nested Get-DbaResourceGovernor for one instance: connects with MinimumVersion 10, warns
    /// under that command's name without EnableException, and decorates the governor as it does.
    /// </summary>
    private ResourceGovernor? GetResourceGovernor(DbaInstanceParameter instance)
    {
        Server server;
        try
        {
            WriteConnectionMessage(MessageLevel.Debug, "Starting process block");
            SmoConnectionRequest request = new()
            {
                Instance = instance,
                SqlCredential = SqlCredential,
                MinimumVersion = 10,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                MessageCallback = WriteConnectionMessage
            };
            server = ConnectionService.GetServer(request);
            SetActiveConnection(server.ConnectionContext);
            WriteConnectionMessage(MessageLevel.Debug, "We are finished with this instance");
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception exception)
        {
            WarnNestedConnection(exception, instance);
            return null;
        }

        ResourceGovernor? governor = server.ResourceGovernor;
        if (governor is null)
            return null;
        PSObject output = PSObject.AsPSObject(governor);
        // SMO can reuse the governor object; preserve Add-Member -Force on repeated calls.
        foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance" })
            output.Properties.Remove(name);
        OutputHelper.AddInstanceProperties(output, server);
        OutputHelper.SetDefaultDisplayPropertySet(output,
            "ComputerName", "InstanceName", "SqlInstance", "ClassifierFunction", "Enabled",
            "MaxOutstandingIOPerVolume", "ReconfigurePending", "ResourcePools", "ExternalResourcePools");
        return governor;
    }

    private void WriteConnectionMessage(MessageLevel level, string message)
    {
        MessageService.Write(this, new MessageService.MessageRequest
        {
            FunctionName = "Connect-DbaInstance", ModuleName = "dbatools", Level = level,
            Message = message, EnableException = false,
            File = MyInvocation.ScriptName, Line = MyInvocation.ScriptLineNumber
        });
    }

    /// <summary>Get-DbaResourceGovernor's Stop-Function -Continue for a failed connection.</summary>
    private void WarnNestedConnection(Exception exception, DbaInstanceParameter instance)
    {
        MessageService.MessageRequest request = new()
        {
            FunctionName = "Get-DbaResourceGovernor", ModuleName = "dbatools", Level = MessageLevel.Warning,
            Message = "Failure", EnableException = false, FromStopFunction = true,
            File = MyInvocation.ScriptName, Line = MyInvocation.ScriptLineNumber
        };
        object target = MessageService.CollapseTarget(MessageService.ResolveTarget(this, request, instance));
        Exception transformed = MessageService.ResolveException(this, request, exception);
        ErrorRecord input = new(transformed, "dbatools_Get-DbaResourceGovernor", ErrorCategory.ConnectionError, target);
        ErrorRecord record = new(new Exception(MessageService.GetErrorMessage(input), transformed),
            "dbatools_Get-DbaResourceGovernor", ErrorCategory.ConnectionError, target);
        request.Target = target;
        request.ErrorRecord = new[] { record };
        MessageService.Write(this, request);
        try
        {
            if (SessionState.PSVariable.GetValue("global:Error") is ArrayList errors)
            {
                errors.Insert(0, record);
                int limit;
                if (!Int32.TryParse(Convert.ToString(SessionState.PSVariable.GetValue("MaximumErrorCount"), CultureInfo.InvariantCulture), out limit))
                    limit = 256;
                if (limit >= 0 && errors.Count > limit)
                    errors.RemoveRange(limit, errors.Count - limit);
            }
        }
        catch (Exception)
        {
            // Restricted session state must not replace the original connection failure.
        }
    }
}
