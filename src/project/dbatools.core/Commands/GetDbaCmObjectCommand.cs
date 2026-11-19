#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves Windows system information from SQL Server hosts using WMI/CIM with intelligent connection fallback.
/// </summary>
/// <para>
/// Queries Windows Management Instrumentation (WMI) or Common Information Model (CIM) classes on SQL Server hosts to gather system-level information like hardware specs, operating system details, services, and performance counters. This function automatically tries multiple connection protocols in order of preference (CIM over WinRM, CIM over DCOM, WMI, then WMI over PowerShell Remoting) and remembers which methods work for each server to optimize future connections.
/// </para>
/// <para>
/// Essential for collecting host-level information that complements SQL Server monitoring, such as checking available memory, CPU utilization, disk space, or Windows service status across your SQL Server infrastructure. The intelligent credential and connection caching prevents repeated authentication failures and speeds up bulk operations across multiple servers.
/// </para>
/// <para>
/// Much of its behavior can be configured using Test-DbaCmConnection to pre-test and configure optimal connection methods for your environment.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaCmObject win32_OperatingSystem
/// </code>
/// <para>
/// Retrieves the common operating system information from the local computer.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaCmObject -Computername "sql2014" -ClassName Win32_OperatingSystem -Credential $cred -DoNotUse CimRM
/// </code>
/// <para>
/// Retrieves the common operating system information from the server sql2014.
/// It will use the Credentials stored in $cred to connect, unless they are known to not work, in which case they will default to windows credentials (unless another default has been set).
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: ComputerManagement, CIM
/// Author: Friedrich Weinmann (@FredWeinmann)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaCmObject" />
[Cmdlet(VerbsCommon.Get, "DbaCmObject", DefaultParameterSetName = "Class")]
public sealed class GetDbaCmObjectCommand : DbaBaseCmdlet
{
    /// <para>
    /// Specifies the WMI or CIM class name to query from the target servers. Common classes include Win32_OperatingSystem for OS details, Win32_ComputerSystem for hardware info, or Win32_Service for Windows services.
    /// Use this when you need to retrieve all instances and properties of a specific Windows management class across your SQL Server infrastructure.
    /// </para>
    [Parameter(Mandatory = true, ParameterSetName = "Class", Position = 0)]
    [Alias("Class")]
    [PsStringCast]
    public string ClassName { get; set; } = null!;

    /// <para>
    /// Specifies a custom WQL (WMI Query Language) query to execute against the target servers. Allows for complex filtering and specific property selection beyond simple class retrieval.
    /// Use this when you need advanced filtering like "SELECT Name, State FROM Win32_Service WHERE StartMode='Auto'" to get specific data rather than entire class instances.
    /// </para>
    [Parameter(Mandatory = true, ParameterSetName = "Query")]
    [PsStringCast]
    public string Query { get; set; } = null!;

    /// <para>
    /// Specifies the target computer names or SQL Server host names to query for Windows management information. Accepts multiple values and pipeline input.
    /// Defaults to the local machine when not specified, but typically used to gather system-level data from remote SQL Server hosts for infrastructure monitoring.
    /// </para>
    [Parameter(ValueFromPipeline = true)]
    public DbaCmConnectionParameter[]? ComputerName { get; set; }

    /// <para>
    /// Credentials to use. Invalid credentials will be stored in a credentials cache and not be reused.
    /// </para>
    [Parameter]
    public PSCredential? Credential { get; set; }

    /// <para>
    /// Specifies the WMI namespace path where the target class or query should be executed. The default "root\cimv2" contains most Windows system classes.
    /// Change this when querying specialized namespaces like "root\SQLSERVER" for SQL Server-specific WMI classes or "root\MSCluster" for cluster information.
    /// </para>
    [Parameter]
    [PsStringCast]
    public string Namespace { get; set; } = "root\\cimv2";

    /// <para>
    /// Excludes specific connection protocols from the automatic fallback sequence. Valid values are CimRM, CimDCOM, Wmi, and PowerShellRemoting.
    /// Use this when certain protocols are blocked by network policies or cause issues in your environment, forcing the function to skip problematic connection methods.
    /// </para>
    [Parameter]
    public ManagementConnectionType[]? DoNotUse { get; set; } = new[] { ManagementConnectionType.None };

    /// <para>
    /// Bypasses timeout protections on connections that have previously failed, allowing retry attempts on servers marked as problematic.
    /// Use this when you suspect connection issues have been resolved or when you need to override cached failure states during troubleshooting.
    /// </para>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <para>
    /// Converts terminating connection failures into non-terminating errors when used with EnableException, allowing processing to continue with remaining servers.
    /// Use this when querying multiple servers where some may be unavailable, and you want to collect data from accessible servers rather than stopping on the first failure.
    /// </para>
    [Parameter]
    public SwitchParameter SilentlyContinue { get; set; }

    protected override void BeginProcessing()
    {
        base.BeginProcessing();
        WriteMessage(MessageLevel.Verbose, "Configuration loaded | Cache disabled: " + ConnectionHost.DisableCache);
    }

    protected override void ProcessRecord()
    {
        DbaCmConnectionParameter?[]? targets = ComputerName;
        if (targets is null && !TestBound("ComputerName"))
        {
            targets = LocalComputer();
        }

        if (targets is null)
        {
            return;
        }

        foreach (DbaCmConnectionParameter? target in targets)
        {
            if (target is null || !target.Success)
            {
                // The pin prints $connectionObject.Input, a member this type does not have (it is
                // InputObject), so the text ends after the colon and the target is empty.
                StopFunction("Failed to interpret input: ", category: ErrorCategory.InvalidArgument, continueLoop: true, silentlyContinue: SilentlyContinue.ToBool());
                continue;
            }

            string computer = target.Connection.ComputerName.ToLowerInvariant();
            WriteMessage(MessageLevel.VeryVerbose, Tagged(computer, "Retrieving Management Information"), computer);
            QueryComputer(target.Connection, computer);
        }
    }

    // A property default would create the local connection cache entry even when -ComputerName is bound.
    private static DbaCmConnectionParameter[]? LocalComputer()
    {
        string? name = Environment.GetEnvironmentVariable("COMPUTERNAME");
        return name is null ? null : new[] { new DbaCmConnectionParameter(name) };
    }

    private static string Tagged(string computer, string text)
    {
        return string.Concat("[", computer, "] ", text);
    }

    private void QueryComputer(ManagementConnection connection, string computer)
    {
        ManagementConnectionType excluded = ManagementConnectionType.None;
        if (DoNotUse is not null)
        {
            foreach (ManagementConnectionType protocol in DoNotUse)
            {
                excluded |= protocol;
            }
        }

        ManagementConnectionType lastRung = ManagementConnectionType.None;
        CimService.CmObjectFailure? failure = null;
        CimService.CmObjectObserver observer = new()
        {
            Rung = (rung, step, error) =>
            {
                lastRung = rung;
                ReportRung(computer, rung, step, error);
            },
            Output = WriteObject,
            Failure = reported => failure = reported
        };

        bool isClass = ParameterSetName == "Class";
        CimService.CmObjectRequest request = new()
        {
            ComputerName = computer,
            Credential = Credential,
            ClassName = isClass ? ClassName : null,
            Query = isClass ? null : Query,
            Namespace = TestBound("Namespace") ? Namespace : null,
            DoNotUse = excluded,
            Force = Force.ToBool(),
            Observer = observer
        };

        // GetCmObject reads the connection from the cache, and a connection object the caller bound
        // need not be the cached one. With the cache disabled the entry goes back to what it was.
        bool wasCached = ConnectionHost.Connections.TryGetValue(computer, out ManagementConnection? previous);
        ConnectionHost.Connections[computer] = connection;
        try
        {
            CimService.CmObjectResult result = CimService.GetCmObject(this, request);
            foreach (ErrorRecord record in result.PassthroughErrors)
            {
                WriteError(record);
            }
        }
        catch (Exception) when (failure is not null)
        {
            ReportFailure(failure!, connection, computer, lastRung);
        }
        finally
        {
            if (ConnectionHost.DisableCache)
            {
                if (wasCached)
                {
                    ConnectionHost.Connections[computer] = previous!;
                }
                else
                {
                    ConnectionHost.Connections.Remove(computer);
                }
            }
        }
    }

    private void ReportRung(string computer, ManagementConnectionType rung, CimService.CmObjectRungStep step, Exception? error)
    {
        string access = Tagged(computer, "Accessing computer using " + RungName(rung));
        switch (step)
        {
            case CimService.CmObjectRungStep.Started:
                WriteMessage(MessageLevel.Verbose, access);
                break;
            case CimService.CmObjectRungStep.Succeeded:
                WriteMessage(MessageLevel.Verbose, access + " - Success");
                break;
            default:
                if (rung == ManagementConnectionType.Wmi)
                {
                    // PS: Write-Message -Level Verbose -Message "... WMI - Failed" -ErrorRecord $_. The pin passes this Write-Message
                    // no -EnableException, so it logs the error and writes no record, even when the command runs with -EnableException.
                    MessageService.MessageRequest failed = new()
                    {
                        Level = MessageLevel.Verbose,
                        Message = access + " - Failed",
                        FunctionName = MyInvocation.MyCommand.Name,
                        ModuleName = "dbatools",
                        Exception = error,
                        EnableException = false,
                        File = MyInvocation.ScriptName,
                        Line = MyInvocation.ScriptLineNumber
                    };
                    MessageService.Write(this, failed);
                }
                else if (rung != ManagementConnectionType.PowerShellRemoting)
                {
                    WriteMessage(MessageLevel.Verbose, access + " - Failed");
                }

                break;
        }
    }

    private static string RungName(ManagementConnectionType rung) => rung switch
    {
        ManagementConnectionType.CimRM => "Cim over WinRM",
        ManagementConnectionType.CimDCOM => "Cim over DCOM",
        ManagementConnectionType.Wmi => "WMI",
        _ => "PowerShell Remoting"
    };

    // The pin's Stop-Function call for each failure kind, shared with the ports that call Get-DbaCmObject (CmObjectFailureRecord).
    private void ReportFailure(CimService.CmObjectFailure failure, ManagementConnection connection, string computer, ManagementConnectionType rung)
    {
        CmObjectFailureRecord? report = CmObjectFailureRecord.Build(failure, connection, computer, rung, ParameterSetName == "Class", ClassName, Namespace);
        if (report is null)
        {
            return;
        }

        StopFunction(report.Message, target: report.Target, errorRecord: report.Record, category: report.Category, continueLoop: true,
            silentlyContinue: report.PassesSilentlyContinue && SilentlyContinue.ToBool(), overrideExceptionMessage: report.OverrideExceptionMessage);
    }
}
