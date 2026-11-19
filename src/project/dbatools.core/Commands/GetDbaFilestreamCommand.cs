#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaFilestream.ps1 at refs/pins/dbatools-2026-10-22: the FILESTREAM level of each instance's
// service (the SQL WMI FilestreamSettings class) and of the instance (sp_configure 'filestream access level'), one
// object per instance with the pin's default view.
/// <summary>Retrieves FileStream configuration status at both the SQL Server service and instance levels.</summary>
/// <para>
/// Retrieves FileStream configuration status by checking both the SQL Server service configuration and the instance-level sp_configure settings. This function helps DBAs quickly identify FileStream configuration mismatches between service and instance levels, which are common causes of FileStream functionality issues. The function returns detailed access levels, share names, and indicates whether a restart is pending to apply configuration changes.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaFilestream -SqlInstance server1\instance2
/// </code>
/// <para>
/// Will return the status of Filestream configuration for the service and instance server1\instance2
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaFilestream -SqlInstance server1\instance2 -SqlCredential sqladmin
/// </code>
/// <para>
/// Prompts for the password to the SQL Login "sqladmin" then returns the status of Filestream configuration for the service and instance server1\instance2
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Filestream
/// Author: Stuart Moore (@napalmgram) | Chrissy LeMaire (@cl)
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaFilestream" />
[Cmdlet(VerbsCommon.Get, "DbaFilestream")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaFilestreamCommand : DbaInstanceCmdlet
{
    private const string SqlServerNamespace = @"root\Microsoft\SQLServer";

    // PS begin: $idServiceFS and $idInstanceFS. Both are [ordered] hashtables indexed with an [int], which PowerShell
    // reads by position; their keys 0..n sit at those positions, so a plain array lookup gives the same entry.
    private static readonly string[] ServiceAccessText =
    {
        "Disabled",
        "FileStream enabled for T-Sql access",
        "FileStream enabled for T-Sql and IO streaming access",
        "FileStream enabled for T-Sql, IO streaming, and remote clients"
    };

    private static readonly string[] InstanceAccessText =
    {
        "Disabled",
        "T-SQL access enabled",
        "Full access enabled"
    };

    // PS: $serviceFS lives in the function's process scope, so it keeps its value across instances and piped records.
    // Only an instance whose computer shows no ComputerManagement namespace leaves it unassigned (the pin's warning path).
    // Correction service-state-per-instance: the pin then reports the previous instance's service level under this one; the
    // port clears it for each instance, so that instance gets what the pin gives a first instance on that path.
    private PSObject? _serviceFS;

    /// <para>
    /// The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

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
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Login to the target Windows server using alternative credentials.
    /// </para>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
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

        // PS: foreach over a null -SqlInstance runs no iteration.
        if (SqlInstance is null)
            return;

        foreach (DbaInstanceParameter? instance in SqlInstance)
        {
            string? computer = instance?.ComputerName;
            string? instanceName = instance?.InstanceName;
            _serviceFS = null;

            // PS: Get Service-Level information
            string? computerName = instance is not null && instance.IsLocalHost ? computer : ResolveComputer(instance);

            WriteMessage(MessageLevel.Verbose, "Attempting to connect to " + computer);
            if (!ReadServiceLevel(computer, computerName, instanceName, instance is null || !instance.IsLocalHost))
                continue;

            // PS: Get Instance-Level information. Connect-DbaInstance declares -SqlInstance mandatory, so a null element
            // faults in its binder inside the pinned try, and the catch runs Stop-Function -Message "Failure".
            if (instance is null)
            {
                ParameterBindingException refused = new("Cannot bind argument to parameter 'SqlInstance' because it is null.");
                StopFunction("Failure", errorRecord: new ErrorRecord(refused, "ParameterArgumentValidationErrorNullNotAllowed", ErrorCategory.InvalidData, null),
                    category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            Server? server = ConnectInstance(instance, "Failure", minimumVersion: 10);
            if (server is null)
                continue;

            // PS: Get-DbaSpConfigure -SqlInstance $server -Name FilestreamAccessLevel | Select-Object ConfiguredValue, RunningValue.
            // Its rows are SMO's Configuration properties, so the FilestreamAccessLevel ConfigProperty is that row's ConfigValue
            // and RunValue. The pin reads it twice (also for $runvalue); the second read returns the same cached SMO values.
            int configuredValue;
            int runningValue;
            try
            {
                ConfigProperty level = server.Configuration.FilestreamAccessLevel;
                configuredValue = level.ConfigValue;
                runningValue = level.RunValue;
            }
            catch (Exception ex) when (ex is not PipelineStoppedException)
            {
                // PS: catch { Stop-Function -Message "Issue collection instance-level configuration on $instanceName" -Target $server -ErrorRecord $_ -Exception $_.Exception -Continue }
                StopFunction("Issue collection instance-level configuration on " + instanceName, target: server,
                    errorRecord: new ErrorRecord(ex, ex.GetType().Name, ErrorCategory.NotSpecified, null), exception: ex, continueLoop: true);
                continue;
            }

            object? serviceAccessLevel = PropertyValue(_serviceFS, "AccessLevel");
            bool pendingRestart = configuredValue != runningValue;

            // PS: if (($serviceFS.AccessLevel -ne 0) -and ($instanceFS.RunningValue -ne 0)) { if (($serviceFS.AccessLevel -eq
            // $instanceFS.RunningValue) -and $pendingRestart) { ... } }. A null AccessLevel passes the first test and fails the second.
            if (serviceAccessLevel is not null && runningValue != 0 && pendingRestart)
            {
                long service = Convert.ToInt64(serviceAccessLevel, CultureInfo.InvariantCulture);
                if (service != 0 && service == runningValue)
                    WriteMessage(MessageLevel.Verbose, "A restart of the instance is pending before Filestream is configured.");
            }

            // PS: $servicelevel = [int]$serviceFS.AccessLevel, which is 0 for a null.
            int serviceLevel = serviceAccessLevel is null ? 0 : Convert.ToInt32(serviceAccessLevel, CultureInfo.InvariantCulture);

            PSObject result = new();
            OutputHelper.AddInstanceProperties(result, server);
            result.Properties.Add(new PSNoteProperty("InstanceAccess", Lookup(InstanceAccessText, runningValue)));
            result.Properties.Add(new PSNoteProperty("ServiceAccess", Lookup(ServiceAccessText, serviceLevel)));
            result.Properties.Add(new PSNoteProperty("ServiceShareName", PropertyValue(_serviceFS, "ShareName")));
            result.Properties.Add(new PSNoteProperty("InstanceAccessLevel", runningValue));
            result.Properties.Add(new PSNoteProperty("ServiceAccessLevel", serviceAccessLevel));
            result.Properties.Add(new PSNoteProperty("Credential", Credential));
            result.Properties.Add(new PSNoteProperty("SqlCredential", SqlCredential));
            OutputHelper.SetDefaultDisplayPropertySet(result, "ComputerName", "InstanceName", "SqlInstance", "InstanceAccess", "ServiceAccess", "ServiceShareName");
            WriteObject(result);
        }
    }

    // PS: $computerName = (Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential).FullComputerName, with no
    // -EnableException. A null $computer binds and resolves nothing, so the name is null with no message. A name DNS cannot
    // resolve is Resolve-DbaNetworkName's Stop-Function -Continue: its warning, and again a null name.
    private string? ResolveComputer(DbaInstanceParameter? instance)
    {
        if (instance is null)
            return null;

        NetworkResolutionService.NetworkResolutionResult? resolution;
        try
        {
            resolution = NetworkResolutionService.Resolve(this, new DbaInstanceParameter(instance.ComputerName), Credential, turbo: false);
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            WarnNestedStopFunction("Resolve-DbaNetworkName", "DNS name " + instance.ComputerName + " not found", errorRecord: new ErrorRecord(ex, ex.GetType().Name, ErrorCategory.NotSpecified, null));
            return null;
        }

        if (resolution is null)
        {
            WarnNestedStopFunction("Resolve-DbaNetworkName", "DNS name " + instance.ComputerName + " not found", errorRecord: DnsFailure(instance.ComputerName));
            return null;
        }

        return resolution.FullComputerName;
    }

    // Resolve-DbaNetworkName's record holds the failed Dns.GetHostEntry call; the service returns null without it, so the
    // lookup is repeated here only to carry that failure. A lookup that now succeeds leaves the warning without a record.
    private static ErrorRecord? DnsFailure(string name)
    {
        try
        {
            System.Net.Dns.GetHostEntry(name);
            return null;
        }
        catch (Exception ex)
        {
            return new ErrorRecord(ex, ex.GetType().Name, ErrorCategory.NotSpecified, null);
        }
    }

    // PS: the try around the three Get-DbaCmObject -EnableException calls, whose catch runs Stop-Function -Continue.
    // Returns false when that catch ran, so the instance gets no object.
    private bool ReadServiceLevel(string? computer, string? computerName, string? instanceName, bool remote)
    {
        try
        {
            // PS: $ognamespace = Get-DbaCmObject -Namespace root\Microsoft\SQLServer -Query "SELECT NAME FROM __NAMESPACE ..."
            List<PSObject> namespaces = QueryCmObject(computerName, remote, SqlServerNamespace, "SELECT NAME FROM __NAMESPACE WHERE NAME LIKE 'ComputerManagement%'", null);

            // PS: $ognamespace | Where-Object { (Get-DbaCmObject -Namespace (... + $_.Name) -ClassName FilestreamSettings).Count -gt 0 }
            //     | Sort-Object Name -Descending | Select-Object -First 1. Each namespace is read once, in the order WMI listed them;
            // the descending sort is stable, so the first of equal names stays first.
            string? chosen = null;
            bool found = false;
            foreach (PSObject item in namespaces)
            {
                string name = Convert.ToString(PropertyValue(item, "Name"), CultureInfo.InvariantCulture) ?? string.Empty;
                if (QueryCmObject(computerName, remote, SqlServerNamespace + @"\" + name, null, "FilestreamSettings").Count == 0)
                    continue;
                if (!found || string.Compare(name, chosen, CultureInfo.CurrentCulture, CompareOptions.IgnoreCase) > 0)
                    chosen = name;
                found = true;
            }

            // PS: if (-not $namespace) { $namespace = $ognamespace }, then "root\Microsoft\SQLServer\" + $namespace.Name. Over
            // several namespaces .Name is their names, which the string concatenation joins with spaces.
            string? namespaceName = found ? chosen : NamespaceNames(namespaces);

            if (!string.IsNullOrEmpty(namespaceName))
            {
                // PS: $serviceFS = Get-DbaCmObject ... -ClassName FilestreamSettings | Where-Object InstanceName -eq $instanceName | Select-Object -First 1
                _serviceFS = null;
                foreach (PSObject setting in QueryCmObject(computerName, remote, SqlServerNamespace + @"\" + namespaceName, null, "FilestreamSettings"))
                {
                    string? settingInstance = Convert.ToString(PropertyValue(setting, "InstanceName"), CultureInfo.InvariantCulture);
                    if (settingInstance is not null && instanceName is not null && string.Equals(settingInstance, instanceName, StringComparison.OrdinalIgnoreCase))
                    {
                        _serviceFS = setting;
                        break;
                    }
                }
            }
            else
            {
                WriteMessage(MessageLevel.Warning, "No ComputerManagement was found on " + computer + ". Service level information may not be collected.", computer);
            }

            return true;
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            // PS: catch { Stop-Function -Message "Issue collecting service-level information on $computer for $instanceName" -Target $computer -ErrorRecord $_ -Continue }
            StopFunction("Issue collecting service-level information on " + computer + " for " + instanceName, target: computer,
                errorRecord: CmObjectFailure(ex, computerName), continueLoop: true);
            return false;
        }
    }

    // PS: Get-DbaCmObject -EnableException -ComputerName $computerName ... A null name binds and queries nothing. When the run gives
    // up, the nested command's Stop-Function throws its record (CmObjectFailureRecord gives the pin's call for each kind), which the
    // pinned catch receives. Correction service-credential: the pin passes these reads no -Credential, so they ran under the caller's
    // own identity whatever -Credential said; a remote computer is now read with it, as Resolve-DbaNetworkName already was. A local
    // instance, which the pin reads without resolving its name, keeps the caller's identity: WMI takes no credential locally.
    private List<PSObject> QueryCmObject(string? computerName, bool remote, string cimNamespace, string? query, string? className)
    {
        if (string.IsNullOrEmpty(computerName))
            return new List<PSObject>();

        string computer = new DbaInstanceParameter(computerName).ComputerName.ToLowerInvariant();
        ManagementConnectionType lastRung = ManagementConnectionType.None;
        CimService.CmObjectFailure? failure = null;
        CimService.CmObjectRequest request = new()
        {
            ComputerName = computer,
            Credential = remote ? Credential : null,
            Namespace = cimNamespace,
            Query = query,
            ClassName = className,
            Observer = new CimService.CmObjectObserver
            {
                Rung = (rung, step, error) => lastRung = rung,
                Failure = reported => failure = reported
            }
        };

        CimService.CmObjectResult result;
        try
        {
            result = CimService.GetCmObject(this, request);
        }
        catch (Exception) when (failure is not null)
        {
            ConnectionHost.Connections.TryGetValue(computer, out ManagementConnection? connection);
            CmObjectFailureRecord? report = CmObjectFailureRecord.Build(failure!, connection!, computer, lastRung, className is not null, className!, cimNamespace);
            if (report is null)
                throw;
            throw new NestedCmObjectFault(CaughtNestedStopFunction("Get-DbaCmObject", report.Message, report.Target, report.Record, report.Category,
                report.OverrideExceptionMessage));
        }

        foreach (ErrorRecord record in result.PassthroughErrors)
            WriteError(record);
        return result.Instances;
    }

    // The record the pinned catch receives as $_: the nested Get-DbaCmObject's thrown record, or the failure itself.
    private static ErrorRecord CmObjectFailure(Exception failure, string? computerName)
    {
        if (failure is NestedCmObjectFault nested)
            return nested.Record;
        return new ErrorRecord(failure, failure.GetType().Name, ErrorCategory.NotSpecified, computerName);
    }

    // Carries the nested Get-DbaCmObject's thrown record from the call to the pinned catch.
    private sealed class NestedCmObjectFault : Exception
    {
        internal NestedCmObjectFault(ErrorRecord record)
            : base(record.Exception.Message, record.Exception)
        {
            Record = record;
        }

        internal ErrorRecord Record { get; }
    }

    // PS: $ognamespace.Name: one namespace gives its name, several give their names joined by the string concatenation, none gives null.
    private static string? NamespaceNames(List<PSObject> namespaces)
    {
        if (namespaces.Count == 0)
            return null;
        List<string> names = new();
        foreach (PSObject item in namespaces)
            names.Add(Convert.ToString(PropertyValue(item, "Name"), CultureInfo.InvariantCulture) ?? string.Empty);
        return string.Join(" ", names);
    }

    private static object? PropertyValue(PSObject? item, string name)
    {
        return item?.Properties[name]?.Value;
    }

    private static string? Lookup(string[] texts, int index)
    {
        return index >= 0 && index < texts.Length ? texts[index] : null;
    }
}
