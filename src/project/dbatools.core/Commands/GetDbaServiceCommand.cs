#nullable enable
#pragma warning disable CA1416 // Windows-only command: WMI-based SQL service discovery

using System;
using System.Collections.Generic;
using System.Linq;
using System.Management;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Server-related Windows services from local or remote computers.
/// Port of public/Get-DbaService.ps1; surface pinned by migration/baselines/Get-DbaService.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaService", DefaultParameterSetName = "Search")]
[OutputType(typeof(PSObject))]
public sealed partial class GetDbaServiceCommand : DbaBaseCmdlet
{
    //Dictionary to transform service type IDs into the names from Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer.Services.Type
    internal static readonly (string Name, int[] Ids)[] ServiceIdMap =
    {
        ("Engine",    new[] { 1 }),
        ("Agent",     new[] { 2 }),
        ("FullText",  new[] { 3, 9 }),
        ("SSIS",      new[] { 4 }),
        ("SSAS",      new[] { 5 }),
        ("SSRS",      new[] { 6 }),
        ("Browser",   new[] { 7 }),
        ("PolyBase",  new[] { 10, 11 }),
        ("Launchpad", new[] { 12 }),
        ("Unknown",   new[] { 8 }),
    };

    private static readonly HashSet<string> ReportingServiceTypes =
        new(new[] { "SSRS", "PowerBI" }, StringComparer.OrdinalIgnoreCase);

    // Service names that always map to the MSSQLSERVER (default) instance
    private static readonly HashSet<string> DefaultInstanceServiceNames =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "MSSQLSERVER", "SQLSERVERAGENT", "ReportServer", "MSSQLServerOLAPService",
            "MSSQLFDLauncher", "SQLPBDMS", "SQLPBENGINE", "MSSQLLAUNCHPAD"
        };

    // Service types that carry an instance name suffix after '$' in the service name
    private static readonly HashSet<string> InstancedServiceTypes =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "Agent", "Engine", "SSRS", "SSAS", "FullText", "PolyBase", "Launchpad"
        };

    #region Parameters

    [Parameter(ValueFromPipeline = true, Position = 1)]
    [Alias("cn", "host", "Server")]
    public DbaInstanceParameter[] ComputerName { get; set; } = new[] { new DbaInstanceParameter(Environment.MachineName) };

    [Parameter(ParameterSetName = "Search")]
    [Alias("Instance")]
    public string[]? InstanceName { get; set; }

    [Parameter(ParameterSetName = "Search")]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    [Parameter]
    public PSCredential? Credential { get; set; }

    [Parameter(ParameterSetName = "Search")]
    [ValidateSet("Agent", "Browser", "Engine", "FullText", "SSAS", "SSIS", "SSRS", "PolyBase", "Launchpad", "PowerBI")]
    public string[]? Type { get; set; }

    [Parameter(ParameterSetName = "ServiceName")]
    public string[]? ServiceName { get; set; }

    [Parameter]
    public SwitchParameter AdvancedProperties { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    #endregion

    // null means "skip SQL WMI query" (only reporting types were requested)
    private string? _searchClause;
    private bool _includeReportingServices;
    // Assigned in BeginProcessing from BuildConnectionOptions - never constructed in the field
    // initializer. System.Management types throw PlatformNotSupportedException from their
    // constructor on non-Windows, and a field initializer runs during instantiation, so an eager
    // new() takes down anything that merely creates the cmdlet object before a single parameter
    // is bound - including the MAML help generator, which reflects over every cmdlet and calls
    // Activator.CreateInstance to read parameter default values.
    private ConnectionOptions _wmiOptions = null!;

    protected override void BeginProcessing()
    {
        // If SqlInstance is used, we select the list of computers for ComputerName
        if (TestBound(nameof(SqlInstance)) && SqlInstance != null)
        {
            ComputerName = SqlInstance
                .Select(s => s.ComputerName)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Select(c => new DbaInstanceParameter(c))
                .ToArray();
        }

        _wmiOptions = BuildConnectionOptions();

        if (ParameterSetName == "Search")
        {
            if (TestBound(nameof(Type)) && Type != null && Type.Length > 0)
            {
                var sqlTypes = Type.Where(t => !ReportingServiceTypes.Contains(t)).ToArray();
                var clauses = new List<string>();
                foreach (string itemType in sqlTypes)
                    foreach (var (name, ids) in ServiceIdMap)
                        if (string.Equals(name, itemType, StringComparison.OrdinalIgnoreCase))
                            foreach (int id in ids)
                                clauses.Add($"SQLServiceType = {id}");
                _searchClause = clauses.Count > 0 ? string.Join(" OR ", clauses) : null;
            }
            else
            {
                _searchClause = "SQLServiceType > 0";
            }
        }
        else // ServiceName parameter set
        {
            if (TestBound(nameof(ServiceName)) && ServiceName != null && ServiceName.Length > 0)
                _searchClause = string.Join(" OR ", ServiceName.Select(sn => $"ServiceName = '{WqlHelper.EscapeValue(sn)}'"));
            else
                _searchClause = "SQLServiceType > 0";
        }

        // $includeReportingServices = !$Type -or @($Type | Where-Object { $PSItem -in $reportingServiceTypes }).Count -gt 0
        _includeReportingServices = !TestBound(nameof(Type)) || Type == null ||
            Type.Any(t => ReportingServiceTypes.Contains(t));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted) return;

        foreach (DbaInstanceParameter computerParam in ComputerName)
        {
            if (Interrupted) return;

            string computer = computerParam.ComputerName;

            // If SqlInstance is used, we select the list of instances for the current computer
            string[]? instanceFilter = InstanceName;
            if (TestBound(nameof(SqlInstance)) && SqlInstance != null)
            {
                instanceFilter = SqlInstance
                    .Where(s => string.Equals(s.ComputerName, computer, StringComparison.OrdinalIgnoreCase))
                    .Select(s => s.InstanceName)
                    .ToArray();
            }

            string resolvedComputerName;
            try
            {
                resolvedComputerName = VerifyConnectivity(computer);
            }
            catch (Exception ex)
            {
                StopFunction($"Failed to resolve or to connect to {computer}.", target: computer,
                    exception: ex, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            var outputServices = new List<PSObject>();
            var reportingServiceNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            if (_includeReportingServices)
            {
                WriteMessage(MessageLevel.Verbose, $"Getting SQL Reporting Server services on {computer}", target: computer);
                var reportingServices = GetReportingServices(resolvedComputerName, instanceFilter, ServiceName);
                foreach (PSObject svc in reportingServices)
                {
                    if (svc.Properties["ServiceName"]?.Value is string sn) reportingServiceNames.Add(sn);
                }

                if (TestBound(nameof(Type)) && Type != null)
                {
                    foreach (PSObject svc in reportingServices)
                        if (svc.Properties["ServiceType"]?.Value is string st && Type.Contains(st, StringComparer.OrdinalIgnoreCase))
                            outputServices.Add(svc);
                }
                else
                {
                    outputServices.AddRange(reportingServices);
                }
            }

            if (_searchClause != null)
            {
                WriteMessage(MessageLevel.Verbose, $"Getting SQL Server namespaces on {computer}", target: computer);
                List<string> namespaces = GetComputerManagementNamespaces(resolvedComputerName, computer);

                foreach (string ns in namespaces)
                {
                    bool querySucceeded = false;
                    var services = new List<ManagementObject>();
                    try
                    {
                        WriteMessage(MessageLevel.Verbose, $"Getting Cim class SqlService in Namespace {ns} on {computer}.", target: computer);
                        var scope = new ManagementScope($@"\\{resolvedComputerName}\root\Microsoft\SQLServer\{ns}", _wmiOptions);
                        scope.Connect();
                        using var searcher = new ManagementObjectSearcher(scope, new ObjectQuery($"SELECT * FROM SqlService WHERE {_searchClause}"));
                        foreach (ManagementObject obj in searcher.Get())
                        {
                            WriteMessage(MessageLevel.Verbose, $"Found service {obj["ServiceName"]} in namespace {ns}.");
                            services.Add(obj);
                        }
                        querySucceeded = true;
                    }
                    catch (Exception ex)
                    {
                        WriteMessage(MessageLevel.Verbose, $"Failed to acquire services from namespace {ns}.", target: computer, exception: ex);
                    }

                    // Use highest namespace available, so break if services have been found
                    if (querySucceeded)
                    {
                        // Remove services returned by the SSRS namespace
                        foreach (ManagementObject svc in services)
                        {
                            if (svc["ServiceName"] is string svcName && reportingServiceNames.Contains(svcName)) continue;
                            PSObject? decorated = DecorateService(svc, computer, ns, instanceFilter, resolvedComputerName);
                            if (decorated != null) outputServices.Add(decorated);
                        }
                        break;
                    }
                }
            }

            string[] defaults = AdvancedProperties.IsPresent
                ? new[] { "ComputerName", "ServiceName", "ServiceType", "InstanceName", "SqlInstance", "DisplayName", "StartName", "State", "StartMode", "Version", "SPLevel", "SkuName", "Clustered", "VSName" }
                : new[] { "ComputerName", "ServiceName", "ServiceType", "InstanceName", "DisplayName", "StartName", "State", "StartMode" };

            if (outputServices.Count > 0)
            {
                foreach (PSObject svc in outputServices)
                {
                    ApplyTypeAndDefaultView(svc, defaults);
                    WriteObject(svc);
                }
            }
            else
            {
                WriteMessage(MessageLevel.Verbose, $"No services found in relevant namespaces on {computer}.");
            }
        }
    }

    // Decorate a raw SqlService WMI ManagementObject with NoteProperties and ScriptMethods.
    // Returns null when instanceFilter excludes this service.
    private PSObject? DecorateService(ManagementObject svc, string computer, string ns,
        string[]? instanceFilter, string resolvedComputerName)
    {
        string serviceName = svc["ServiceName"] as string ?? string.Empty;
        string hostName    = svc["HostName"]    as string ?? computer;
        int    sqlType     = Convert.ToInt32(svc["SQLServiceType"] ?? 0);
        int    stateVal    = Convert.ToInt32(svc["State"]          ?? 0);
        int    modeVal     = Convert.ToInt32(svc["StartMode"]      ?? 0);

        string serviceType = MapServiceType(sqlType);
        string? state      = MapState(stateVal);
        string? startMode  = MapStartMode(modeVal);
        string instance    = DeriveInstanceName(serviceName, serviceType);
        int    priority    = serviceType == "Engine" ? 200 : 100;

        //If only specific instances are selected
        if (instanceFilter != null && instanceFilter.Length > 0 &&
            !instanceFilter.Contains(instance, StringComparer.OrdinalIgnoreCase))
            return null;

        //Add other properties and methods
        var psObj = new PSObject(svc);
        psObj.Properties.Add(new PSNoteProperty("ComputerName",    hostName));
        psObj.Properties.Add(new PSNoteProperty("ServiceType",     serviceType));
        psObj.Properties.Add(new PSNoteProperty("State",           state));
        psObj.Properties.Add(new PSNoteProperty("StartMode",       startMode));
        psObj.Properties.Add(new PSNoteProperty("InstanceName",    instance));
        psObj.Properties.Add(new PSNoteProperty("ServicePriority", priority));
        AddScriptMethods(psObj);

        if (AdvancedProperties.IsPresent)
            AddAdvancedProperties(psObj, serviceName, resolvedComputerName, ns, sqlType);

        return psObj;
    }

    // Apply TypeName and DefaultDisplayPropertySet (mirrors Select-DefaultView -TypeName DbaSqlService).
    // TypeName creates a new type so that we can use ps1xml to modify the output
    private static void ApplyTypeAndDefaultView(PSObject psObj, string[] defaults)
    {
        psObj.TypeNames.Insert(0, "dbatools.DbaSqlService");
        var propSet    = new PSPropertySet("DefaultDisplayPropertySet", (IEnumerable<string>)defaults);
        var stdMembers = new PSMemberSet("PSStandardMembers", new PSMemberInfo[] { propSet });
        psObj.Members.Add(stdMembers);
    }
}
