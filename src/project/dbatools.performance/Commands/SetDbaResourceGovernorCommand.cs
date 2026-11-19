#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Configures SQL Server Resource Governor through SMO. Port of public/Set-DbaResourceGovernor.ps1.
/// <summary>Configures SQL Server Resource Governor to control workload resource allocation and sets classifier functions.</summary>
[Cmdlet(VerbsCommon.Set, "DbaResourceGovernor", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class SetDbaResourceGovernorCommand : DbaInstanceCmdlet
{
    private const string NullMethodText = "You cannot call a method on a null-valued expression.";

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    [Alias("Credential")]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Enable Resource Governor.</summary>
    [Parameter]
    public SwitchParameter Enabled { get; set; }

    /// <summary>Disable Resource Governor.</summary>
    [Parameter]
    public SwitchParameter Disabled { get; set; }

    /// <summary>The classifier UDF name, or NULL to clear it.</summary>
    [Parameter(Position = 2)]
    public string? ClassifierFunction { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;

            // Azure SQL Database has no Resource Governor (ALTER RESOURCE GOVERNOR is SQL Server and Managed Instance
            // only), so the command refuses it as Connect-DbaInstance -AzureUnsupported does: correction azure-unsupported.
            Server? server = ConnectInstance(instance, azureUnsupported: true);
            if (server is null)
                continue;

            if (ConfigureInstance(instance, server))
                WriteGovernor(server);
        }
    }

    /// <summary>The source body between the connect and the final Get-DbaResourceGovernor; false where it continues the loop.</summary>
    private bool ConfigureInstance(DbaInstanceParameter instance, Server server)
    {
        string target = instance.ToString();
        // PS member reads: a getter that throws reads as $null, and [bool]$null / [string]$null are False / "".
        ResourceGovernor? governor = PsProperty.Get(server, "ResourceGovernor") as ResourceGovernor;
        bool state = LanguagePrimitives.IsTrue(PsProperty.Get(governor, "Enabled"));
        string classifier = PsProperty.Get(governor, "ClassifierFunction")?.ToString() ?? String.Empty;

        bool disableRequested = false;
        if (Enabled.ToBool())
        {
            string action = String.Format(CultureInfo.InvariantCulture,
                "Changing Resource Governor enabled from '{0}' to 'True' at the instance level", PsBool.Text(state));
            if (ShouldProcess(target, action) && !TrySetEnabled(governor, true, "Couldn't enable Resource Governor"))
                return false;
        }
        else if (Disabled.ToBool())
        {
            string action = String.Format(CultureInfo.InvariantCulture,
                "Changing Resource Governor enabled from '{0}' to 'False' at the instance level", PsBool.Text(state));
            if (ShouldProcess(target, action))
            {
                if (!TrySetEnabled(governor, false, "Couldn't disable Resource Governor"))
                    return false;
                disableRequested = true;
            }
        }

        if (!String.IsNullOrEmpty(ClassifierFunction))
        {
            string action = String.Format(CultureInfo.InvariantCulture,
                "Changing Resource Governor Classifier Function from '{0}' to '{1}'", classifier, ClassifierFunction);
            if (ShouldProcess(target, action))
            {
                if (PsString.Eq(ClassifierFunction, "NULL"))
                {
                    SetClassifier(governor, ClassifierFunction!);
                }
                else
                {
                    object? function = FindClassifierFunction(server, ClassifierFunction!);
                    if (function is null)
                    {
                        StopFunction(String.Format(CultureInfo.InvariantCulture, "Classifier function '{0}' does not exist.", ClassifierFunction),
                            category: ErrorCategory.ObjectNotFound, continueLoop: true);
                        return false;
                    }
                    // PS assigns the Get-DbaDbUdf output to the string property: the SMO object's ToString, [schema].[name].
                    SetClassifier(governor, (string)LanguagePrimitives.ConvertTo(function, typeof(string), CultureInfo.InvariantCulture));
                }
            }
        }

        if (ShouldProcess(target, "Changing Resource Governor"))
        {
            ErrorRecord? alterFault = null;
            if (governor is null)
                alterFault = NullMethodFault();
            else
            {
                try
                {
                    governor.Alter();
                }
                catch (Exception ex) when (ex is not PipelineStoppedException)
                {
                    alterFault = MethodFault(ex, "Alter");
                }
                if (alterFault is null && disableRequested && !state)
                    alterFault = KeepDisabled(server);
            }
            // caller-try: continue -- the source's unguarded Alter() writes the error and runs Refresh() and Get-DbaResourceGovernor; Refresh reloads the server's real values, no further change is made and later instances are not dropped
            if (alterFault is not null)
                WriteError(alterFault);

            ErrorRecord? refreshFault = null;
            if (governor is null)
                refreshFault = NullMethodFault();
            else
            {
                try
                {
                    governor.Refresh();
                }
                catch (Exception ex) when (ex is not PipelineStoppedException)
                {
                    refreshFault = MethodFault(ex, "Refresh");
                }
            }
            // caller-try: terminate -- continuing would output governor values the server never confirmed, such as a change a failed Alter did not apply
            if (refreshFault is not null)
                ThrowTerminatingError(refreshFault); // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
        }

        return true;
    }

    /// <summary>
    /// Correction disabled-kept-disabled: SMO's ResourceGovernor.Alter scripts DISABLE only when Enabled changes, and
    /// adds RECONFIGURE, which enables Resource Governor, whenever the classifier function changes or a reconfigure is
    /// pending. So -Disabled on a governor that was already disabled left it enabled. The explicit DISABLE after a
    /// successful Alter keeps the requested state; a constant statement, no caller text.
    /// </summary>
    private static ErrorRecord? KeepDisabled(Server server)
    {
        try
        {
            server.Databases["master"].ExecuteNonQuery("ALTER RESOURCE GOVERNOR DISABLE;");
            return null;
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            return new ErrorRecord(ex, ex.GetType().Name, ErrorCategory.NotSpecified, null);
        }
    }

    /// <summary>The source's try { $server.ResourceGovernor.Enabled = ... } catch { Stop-Function ... -Continue }.</summary>
    private bool TrySetEnabled(ResourceGovernor? governor, bool value, string message)
    {
        ErrorRecord? fault;
        if (governor is null)
            fault = PropertyNotFoundFault("Enabled");
        else
        {
            try
            {
                governor.Enabled = value;
                return true;
            }
            catch (Exception ex) when (ex is not PipelineStoppedException)
            {
                fault = SetterFault(ex, "Enabled");
            }
        }
        StopFunction(message, errorRecord: fault, continueLoop: true);
        return false;
    }

    /// <summary>The source's unguarded $server.ResourceGovernor.ClassifierFunction = ... statement.</summary>
    private void SetClassifier(ResourceGovernor? governor, string value)
    {
        ErrorRecord? fault = null;
        if (governor is null)
            fault = PropertyNotFoundFault("ClassifierFunction");
        else
        {
            try
            {
                governor.ClassifierFunction = value;
            }
            catch (Exception ex) when (ex is not PipelineStoppedException)
            {
                fault = SetterFault(ex, "ClassifierFunction");
            }
        }
        // caller-try: terminate -- continuing would run Alter and apply the enabled change without the requested classifier function
        if (fault is not null)
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
    }

    /// <summary>
    /// PS: Get-DbaDbUdf -Database master -Name $ClassifierFunction. The pinned reader filters with a literal,
    /// case-insensitive Name -in over the functions and then the aggregates of master; -ClassifierFunction
    /// documents no wildcards, so * and ? stay literal. One match is the object itself, several an array.
    /// </summary>
    private static object? FindClassifierFunction(Server server, string name)
    {
        Microsoft.SqlServer.Management.Smo.Database master = server.Databases["master"];
        List<object> matches = new();
        foreach (UserDefinedFunction function in master.UserDefinedFunctions)
        {
            if (PsString.Eq(function.Name, name))
                matches.Add(function);
        }
        foreach (UserDefinedAggregate aggregate in master.UserDefinedAggregates)
        {
            if (PsString.Eq(aggregate.Name, name))
                matches.Add(aggregate);
        }
        if (matches.Count == 0)
            return null;
        return matches.Count == 1 ? matches[0] : matches.ToArray();
    }

    /// <summary>PS: Get-DbaResourceGovernor -SqlInstance $server.</summary>
    private void WriteGovernor(Server server)
    {
        // Its Connect-DbaInstance -MinimumVersion 10 warns and returns nothing below SQL Server 2008.
        if (server.VersionMajor != 0 && server.VersionMajor < 10)
        {
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture,
                "SQL Server version 10 required - {0} not supported.", server), target: server);
            return;
        }

        PSObject output = PSObject.AsPSObject(server.ResourceGovernor);
        // Add-Member -Force on the reused SMO object: earlier notes are replaced.
        foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance" })
            output.Properties.Remove(name);
        OutputHelper.AddInstanceProperties(output, server);
        OutputHelper.SetDefaultDisplayPropertySet(output, "ComputerName", "InstanceName", "SqlInstance", "ClassifierFunction",
            "Enabled", "MaxOutstandingIOPerVolume", "ReconfigurePending", "ResourcePools", "ExternalResourcePools");
        WriteObject(output);
    }

    /// <summary>The record PowerShell raises for a failed .NET method call: 'Exception calling "X" with "0" argument(s)'.</summary>
    private static ErrorRecord MethodFault(Exception failure, string method)
    {
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"{0}\" with \"0\" argument(s): \"{1}\"", method, failure.Message), failure);
        return new ErrorRecord(call, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    /// <summary>The record PowerShell raises for a method call on $null.</summary>
    private static ErrorRecord NullMethodFault()
    {
        return new ErrorRecord(new RuntimeException(NullMethodText), "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null);
    }

    /// <summary>The record PowerShell raises for a property assignment on $null.</summary>
    private static ErrorRecord PropertyNotFoundFault(string property)
    {
        RuntimeException missing = new(String.Format(CultureInfo.InvariantCulture,
            "The property '{0}' cannot be found on this object. Verify that the property exists and can be set.", property));
        return new ErrorRecord(missing, "PropertyNotFound", ErrorCategory.InvalidOperation, null);
    }

    /// <summary>The record PowerShell raises for a property setter that throws.</summary>
    private static ErrorRecord SetterFault(Exception failure, string property)
    {
        SetValueInvocationException setter = new(String.Format(CultureInfo.InvariantCulture,
            "Exception setting \"{0}\": \"{1}\"", property, failure.Message), failure);
        return new ErrorRecord(setter, "ExceptionWhenSetting", ErrorCategory.NotSpecified, null);
    }
}
