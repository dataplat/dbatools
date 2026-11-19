#nullable enable
#pragma warning disable CA1416 // Windows-oriented discovery: SQL Browser UDP, TCP probes, AD/LDAP, WMI services

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Management.Automation;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Discovery;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Discovers SQL Server instances across networks using multiple scanning methods.
/// Port of public/Find-DbaInstance.ps1 (surface pinned by migration/baselines/Find-DbaInstance.json:
/// three sets Computer/Discover/Default, ComputerName pipeline in the Computer set, no positions).
///
/// The gated path is the Computer set with -ScanType Browser, SqlConnect: the SQL Browser UDP
/// query, the TCP port probes and the DbaInstanceReport assembly are native C# here (the retired
/// function's -Tag UnitTests New-Object mock lives outside the IntegrationTests gate). The cold,
/// Windows-only discovery paths (AD/LDAP SPN and DomainServer searches, SSMS DataSource
/// enumeration) run their verbatim PS expressions through the engine - the sanctioned pattern for
/// System.DirectoryServices / SqlDataSourceEnumerator (Test-DbaSpn precedent), so dbatools.core
/// takes no new package dependency. Nested *-Dba* calls (Get-DbaService, Connect-DbaInstance) go
/// through NestedCommand so they resolve to whichever implementation is live during the hybrid
/// period.
/// </summary>
[Cmdlet(VerbsCommon.Find, "DbaInstance", DefaultParameterSetName = "Default")]
[OutputType(typeof(DbaInstanceReport))]
public sealed class FindDbaInstanceCommand : DbaBaseCmdlet
{
    /// <summary>Target computers to scan. Only the computer-name portion is used.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "Computer")]
    public DbaInstanceParameter[]? ComputerName { get; set; }

    /// <summary>Automatic discovery method(s) used to find SQL Server targets across the network.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Discover")]
    public DbaInstanceDiscoveryType DiscoveryType { get; set; }

    /// <summary>Windows credential for domain-controller SPN lookups and CIM/WMI service scans.</summary>
    [Parameter]
    public PSCredential? Credential { get; set; }

    /// <summary>SQL credential used by the SqlConnect scan.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Verification methods used to detect and validate instances on each target.</summary>
    [Parameter]
    [ValidateSet("Default", "SQLService", "Browser", "TCPPort", "All", "SPN", "Ping", "SqlConnect", "DNSResolve")]
    public DbaInstanceScanType[] ScanType { get; set; } = new[] { DbaInstanceScanType.Default };

    /// <summary>Custom IP ranges to scan under IPRange discovery.</summary>
    [Parameter(ParameterSetName = "Discover")]
    public string[]? IpAddress { get; set; }

    /// <summary>Specific domain controller for the AD SPN / DomainServer queries.</summary>
    [Parameter]
    public string? DomainController { get; set; }

    /// <summary>TCP ports probed for SQL Server connectivity (default 1433).</summary>
    [Parameter]
    public int[] TCPPort { get; set; } = new[] { 1433 };

    /// <summary>Only instances at or above this confidence level are returned.</summary>
    [Parameter]
    public DbaInstanceConfidenceLevel MinimumConfidence { get; set; } = DbaInstanceConfidenceLevel.Low;

    // EnableException is inherited from DbaBaseCmdlet.

    // The combined scan flags (the retired function coerces the ScanType[] into a single flags
    // value when it splats Test-SqlInstance's scalar -ScanType).
    private DbaInstanceScanType _scanType;

    // The steppable pipeline's begin-block ArrayList: one Test-SqlInstance instance spanned the
    // whole pipeline, so every target (pipeline items AND discovery output) dedups against the
    // same list. ArrayList.Contains is an ordinal string compare.
    private readonly List<string> _computersScanned = new List<string>();

    /// <inheritdoc/>
    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        DbaInstanceScanType combined = 0;
        if (ScanType != null)
        {
            foreach (DbaInstanceScanType single in ScanType)
                combined |= single;
        }
        _scanType = combined;
    }

    /// <inheritdoc/>
    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        switch (ParameterSetName)
        {
            case "Computer":
                if (ComputerName != null)
                {
                    foreach (DbaInstanceParameter computer in ComputerName)
                        ProcessTarget(computer);
                }
                break;

            case "Discover":
                RunDiscovery();
                break;

            case "Default":
                StopFunction("Please specify DiscoveryType or ScanType. Try Get-Help Find-DbaInstance -Examples for working examples.");
                return;

            default:
                StopFunction("Invalid parameterset, some developer probably had a beer too much. Please file an issue so we can fix this.");
                return;
        }
    }

    #region Discovery (Discover parameter set)
    private void RunDiscovery()
    {
        // Discovery: DataSource Enumeration
        if (HasFlag(DiscoveryType, DbaInstanceDiscoveryType.DataSourceEnumeration))
        {
            try
            {
                foreach (string dataSource in EnumerateDataSources())
                    ProcessTarget(new DbaInstanceParameter(dataSource));
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                WriteMessage(MessageLevel.Warning, "Datasource enumeration failed", exception: ex);
            }
        }

        // Discovery: SPN Search
        if (HasFlag(DiscoveryType, DbaInstanceDiscoveryType.DomainSPN))
        {
            try
            {
                foreach (string host in GetDomainSpn(DomainController, Credential, "*", getSpn: false))
                    ProcessTarget(new DbaInstanceParameter(host));
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                WriteMessage(MessageLevel.Warning, "Failed to execute Service Principal Name discovery", exception: ex);
            }
        }

        // Discovery: IP Range
        if (HasFlag(DiscoveryType, DbaInstanceDiscoveryType.IPRange))
        {
            if (IpAddress != null && IpAddress.Length > 0)
            {
                foreach (string address in IpAddress)
                {
                    foreach (string resolved in ResolveIpRange(address))
                        ProcessTarget(new DbaInstanceParameter(resolved));
                }
            }
            else
            {
                foreach (string resolved in ResolveIpRange(null))
                    ProcessTarget(new DbaInstanceParameter(resolved));
            }
        }

        // Discovery: Windows Server Search
        if (HasFlag(DiscoveryType, DbaInstanceDiscoveryType.DomainServer))
        {
            try
            {
                foreach (string host in GetDomainServer(DomainController, Credential))
                    ProcessTarget(new DbaInstanceParameter(host));
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                WriteMessage(MessageLevel.Warning, "Failed to execute Windows Server discovery", exception: ex);
            }
        }
    }
    #endregion Discovery

    #region Test-SqlInstance (the core scan)
    private void ProcessTarget(DbaInstanceParameter computer)
    {
        if (computer == null)
            return;

        // Skip computers already scanned by this cmdlet invocation (ordinal compare, like ArrayList).
        if (_computersScanned.Contains(computer.ComputerName))
            return;
        _computersScanned.Add(computer.ComputerName);

        Progress($"Processing: {computer}", "Starting");
        WriteMessage(MessageLevel.Verbose, $"Processing: {computer}");

        // Null variables to prevent scope lookup on conditional existence
        IPHostEntry? resolution = null;
        PingReply? pingReply = null;
        string[] sPNs = new string[0];
        List<DbaPortReport> ports = new List<DbaPortReport>();
        List<int> browserFallbackPorts = new List<int>();
        List<DbaBrowserReply>? browseResult = null;
        Collection<PSObject>? services = null;

        #region Gather data
        if (HasFlag(_scanType, DbaInstanceScanType.DNSResolve))
        {
            try
            {
                Progress($"Processing: {computer}", "Performing DNS resolution");
                resolution = Dns.GetHostEntry(computer.ComputerName);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch
            {
                // here to avoid an empty catch
            }
        }

        if (HasFlag(_scanType, DbaInstanceScanType.Ping))
        {
            using (Ping ping = new Ping())
            {
                try
                {
                    Progress($"Processing: {computer}", "Waiting for ping response");
                    pingReply = ping.Send(computer.ComputerName);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch
                {
                    // here to avoid an empty catch
                }
            }
        }

        if (HasFlag(_scanType, DbaInstanceScanType.SPN))
        {
            string computerByName = computer.ComputerName;
            if (resolution != null && !string.IsNullOrEmpty(resolution.HostName))
                computerByName = resolution.HostName;
            if (!Regex.IsMatch(computerByName, RegexHelper.IPv4) && !Regex.IsMatch(computerByName, RegexHelper.IPv6))
            {
                try
                {
                    Progress($"Processing: {computer}", "Finding SPNs");
                    sPNs = GetDomainSpn(DomainController, Credential, computerByName, getSpn: true).ToArray();
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch
                {
                    // here to avoid an empty catch
                }
            }
        }

        // $ports required for all scans
        Progress($"Processing: {computer}", "Testing TCP ports");

        if (HasFlag(_scanType, DbaInstanceScanType.Browser))
        {
            try
            {
                Progress($"Processing: {computer}", "Probing Browser service");
                browseResult = GetSqlInstanceBrowserUdp(computer, enableException: true);
                WriteMessage(MessageLevel.Verbose, $"Browser returned {browseResult.Count} instance(s): {string.Join(", ", browseResult.Select(b => $"{b.InstanceName}:{b.TCPPort}"))}");
                List<int> portsToScan = new List<int>();
                List<int> browserReportedPorts = browseResult.Select(b => b.TCPPort).Where(p => p > 0).ToList();
                if (browserReportedPorts.Count > 0)
                    portsToScan.AddRange(browserReportedPorts);
                if (browseResult.Any(b => b.TCPPort == 0))
                {
                    browserFallbackPorts = Distinct(TCPPort);
                    WriteMessage(MessageLevel.Verbose, $"Browser has instance(s) without TCPPort, adding fallback ports: {string.Join(", ", browserFallbackPorts)}");
                    portsToScan.AddRange(browserFallbackPorts);
                }
                if (portsToScan.Count > 0)
                    ports = TestTcpPort(computer, Distinct(portsToScan));
                WriteMessage(MessageLevel.Verbose, $"Port test results from Browser: {string.Join(", ", ports.Select(p => $"Port {p.Port}={p.IsOpen}"))}");
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                WriteMessage(MessageLevel.Verbose, $"Browser scan failed: {ex.Message}");
                // here to avoid an empty catch
            }

            // Fall back to default port testing if Browser returned no port info
            // (e.g. SQL Server 2022+ where Browser is deprecated, or default instances
            // which don't report a TCP port via Browser UDP)
            if (ports.Count == 0)
            {
                browserFallbackPorts = Distinct(TCPPort);
                WriteMessage(MessageLevel.Verbose, $"No port info from Browser, falling back to default ports: {string.Join(", ", browserFallbackPorts)}");
                ports = TestTcpPort(computer, browserFallbackPorts);
                WriteMessage(MessageLevel.Verbose, $"Fallback port test results: {string.Join(", ", ports.Select(p => $"Port {p.Port}={p.IsOpen}"))}");
            }
        }
        else
        {
            ports = TestTcpPort(computer, TCPPort);
        }

        if (HasFlag(_scanType, DbaInstanceScanType.SqlService))
        {
            Progress($"Processing: {computer}", "Finding SQL services using SQL WMI");
            Hashtable splatService = new Hashtable();
            splatService["ComputerName"] = computer;
            splatService["ErrorAction"] = "Ignore";
            splatService["WarningAction"] = "SilentlyContinue";
            if (Credential != null)
            {
                splatService["Credential"] = Credential;
                splatService["EnableException"] = true;
            }
            services = NestedCommand.Invoke(this, "Get-DbaService", splatService);
        }
        #endregion Gather data

        #region Gather list of found instance indicators
        List<string> instanceNames = new List<string>();
        if (services != null)
        {
            foreach (PSObject service in services)
            {
                string? inm = PropStr(service, "InstanceName");
                if (!string.IsNullOrEmpty(inm) && !ContainsIgnoreCase(instanceNames, inm))
                    instanceNames.Add(inm!);
            }
        }
        if (browseResult != null && browseResult.Count > 0)
        {
            foreach (DbaBrowserReply reply in browseResult)
            {
                string inm = reply.InstanceName;
                if (!string.IsNullOrEmpty(inm) && !ContainsIgnoreCase(instanceNames, inm))
                    instanceNames.Add(inm);
            }
        }

        List<int> portsDetected = new List<int>();
        foreach (DbaPortReport portResult in ports)
        {
            if (portResult.IsOpen)
                portsDetected.Add(portResult.Port);
        }
        foreach (string sPN in sPNs)
        {
            string[] pieces = sPN.Split(':');
            if (pieces.Length < 2)
                continue;
            string inst = pieces[1];

            if (int.TryParse(inst, out int portNumber))
            {
                if (portNumber != 0 && !portsDetected.Contains(portNumber))
                    portsDetected.Add(portNumber);
            }
            else
            {
                if (!string.IsNullOrEmpty(inst) && !ContainsIgnoreCase(instanceNames, inst))
                    instanceNames.Add(inst);
            }
        }
        #endregion Gather list of found instance indicators

        #region Case: Nothing found
        if (instanceNames.Count == 0 && portsDetected.Count == 0)
        {
            if (resolution != null || (pingReply != null && pingReply.Status == IPStatus.Success))
            {
                if (MinimumConfidence == DbaInstanceConfidenceLevel.None)
                {
                    DbaInstanceReport report = new DbaInstanceReport();
                    report.MachineName = computer.ComputerName;
                    report.ComputerName = computer.ComputerName;
                    report.Ping = pingReply != null && pingReply.Status == IPStatus.Success;
                    WriteObject(report);
                }
                else
                {
                    WriteMessage(MessageLevel.Verbose, $"Computer {computer} could be contacted, but no trace of an SQL Instance was found. Skipping...");
                }
            }
            else
            {
                WriteMessage(MessageLevel.Verbose, $"Computer {computer} could not be contacted, skipping.");
            }

            return;
        }
        #endregion Case: Nothing found

        List<DbaInstanceReport> masterList = new List<DbaInstanceReport>();

        #region Case: Named instance found
        foreach (string instance in instanceNames)
        {
            WriteMessage(MessageLevel.Verbose, $"Processing named instance: {instance}");
            DbaInstanceReport report = new DbaInstanceReport();
            report.MachineName = computer.ComputerName;
            report.ComputerName = computer.ComputerName;
            report.InstanceName = instance;
            report.DnsResolution = resolution;
            report.Ping = pingReply != null && pingReply.Status == IPStatus.Success;
            report.ScanTypes = _scanType;
            report.Services = FilterServices(services, s => string.Equals(PropStr(s, "InstanceName"), instance, StringComparison.OrdinalIgnoreCase));
            report.SystemServices = FilterServices(services, s => string.IsNullOrEmpty(PropStr(s, "InstanceName")));
            report.SPNs = sPNs;

            if (browseResult != null)
            {
                DbaBrowserReply? match = browseResult.FirstOrDefault(b => string.Equals(b.InstanceName, instance, StringComparison.OrdinalIgnoreCase));
                if (match != null)
                    report.BrowseReply = match;
            }
            if (ports.Count > 0)
                report.PortsScanned = ports.ToArray();

            if (report.BrowseReply != null)
            {
                report.Confidence = DbaInstanceConfidenceLevel.Medium;
                if (report.BrowseReply.TCPPort != 0)
                {
                    report.Port = report.BrowseReply.TCPPort;
                    WriteMessage(MessageLevel.Verbose, $"Browser reported TCPPort {report.Port}, checking PortsScanned: {string.Join(", ", PortsScannedText(report))}");

                    foreach (DbaPortReport pr in EnumeratePortsScanned(report))
                    {
                        if (pr.Port == report.Port)
                        {
                            report.TcpConnected = pr.IsOpen;
                            WriteMessage(MessageLevel.Verbose, $"Port {pr.Port} IsOpen={pr.IsOpen}, TcpConnected set to {report.TcpConnected}");
                        }
                    }
                }
                else
                {
                    // Default instance - Browser doesn't report a specific TCP port,
                    // check if any of the fallback ports we tested is open
                    List<DbaPortReport> defaultPortResults = EnumeratePortsScanned(report)
                        .Where(pr => browserFallbackPorts.Contains(pr.Port)).ToList();
                    WriteMessage(MessageLevel.Verbose, $"Browser has no TCPPort (default instance), checking fallback PortsScanned for any open port: {string.Join(", ", defaultPortResults.Select(pr => $"Port {pr.Port}={pr.IsOpen}"))}");
                    DbaPortReport? firstOpen = defaultPortResults.FirstOrDefault(pr => pr.IsOpen);
                    if (firstOpen != null)
                    {
                        report.Port = firstOpen.Port;
                        report.TcpConnected = true;
                        WriteMessage(MessageLevel.Verbose, $"Found open port {firstOpen.Port}, TcpConnected set to True");
                    }
                }
            }
            if (report.Services != null && report.Services.Length > 0)
            {
                report.Confidence = DbaInstanceConfidenceLevel.High;

                object? engine = report.Services.FirstOrDefault(s => string.Equals(PropStr(s, "ServiceType"), "Engine", StringComparison.OrdinalIgnoreCase));
                if (engine != null)
                {
                    string? state = PropStr(engine, "State");
                    if (string.Equals(state, "Running", StringComparison.OrdinalIgnoreCase))
                        report.Availability = DbaInstanceAvailability.Available;
                    else if (string.Equals(state, "Stopped", StringComparison.OrdinalIgnoreCase))
                        report.Availability = DbaInstanceAvailability.Unavailable;
                    else
                        report.Availability = DbaInstanceAvailability.Unknown;
                }
            }

            report.Timestamp = DateTime.Now;

            masterList.Add(report);
        }
        #endregion Case: Named instance found

        #region Case: Port number found
        foreach (int port in portsDetected)
        {
            if (masterList.Any(r => r.Port == port))
                continue;

            DbaInstanceReport report = new DbaInstanceReport();
            report.MachineName = computer.ComputerName;
            report.ComputerName = computer.ComputerName;
            report.Port = port;
            report.DnsResolution = resolution;
            report.Ping = pingReply != null && pingReply.Status == IPStatus.Success;
            report.ScanTypes = _scanType;
            report.SystemServices = FilterServices(services, s => string.IsNullOrEmpty(PropStr(s, "InstanceName")));
            report.SPNs = sPNs;
            report.Confidence = DbaInstanceConfidenceLevel.Low;
            if (ports.Count > 0)
            {
                report.PortsScanned = ports.ToArray();

                if (ports.Where(p => p.IsOpen).Any(p => p.Port == 1433))
                    report.Confidence = DbaInstanceConfidenceLevel.Medium;
            }

            if (ports.Any(p => p.Port == port) && sPNs.Any(s => LikeSuffix(s, port)))
                report.Confidence = DbaInstanceConfidenceLevel.Medium;

            foreach (DbaPortReport pr in EnumeratePortsScanned(report))
            {
                if (pr.Port == report.Port)
                    report.TcpConnected = pr.IsOpen;
            }
            report.Timestamp = DateTime.Now;

            if (masterList.Any(r => string.Equals(r.SqlInstance, report.SqlInstance, StringComparison.OrdinalIgnoreCase)))
                continue;

            masterList.Add(report);
        }
        #endregion Case: Port number found

        if (HasFlag(_scanType, DbaInstanceScanType.SqlConnect))
        {
            // PS hashtables key case-insensitively; match that so DomainInstanceName dedup parity holds.
            Dictionary<string, DbaInstanceReport> instanceHash = new Dictionary<string, DbaInstanceReport>(StringComparer.OrdinalIgnoreCase);
            List<DbaInstanceReport> toDelete = new List<DbaInstanceReport>();
            foreach (DbaInstanceReport dataSet in masterList)
            {
                try
                {
                    Hashtable splatConnect = new Hashtable();
                    splatConnect["SqlInstance"] = dataSet.SqlInstance;
                    splatConnect["SqlCredential"] = SqlCredential;
                    Collection<PSObject> connectResult = NestedCommand.Invoke(this, "Connect-DbaInstance", splatConnect);
                    object? server = connectResult.Count > 0 ? connectResult[0] : null;
                    dataSet.SqlConnected = true;
                    dataSet.Confidence = DbaInstanceConfidenceLevel.High;

                    // Remove duplicates
                    string? domainInstanceName = server != null ? PropStr(server, "DomainInstanceName") : null;
                    if (domainInstanceName != null && instanceHash.ContainsKey(domainInstanceName))
                    {
                        toDelete.Add(dataSet);
                    }
                    else
                    {
                        if (domainInstanceName != null)
                            instanceHash[domainInstanceName] = dataSet;

                        try
                        {
                            if (server != null)
                                dataSet.MachineName = PropStr(server, "ComputerNamePhysicalNetBIOS");
                        }
                        catch (PipelineStoppedException)
                        {
                            throw;
                        }
                        catch
                        {
                            // here to avoid an empty catch
                        }
                    }
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    // Error class definitions
                    // https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/database-engine-error-severities
                    // 24 or less means an instance was found, but had some issues
                    if (SqlErrorClassBelow(ex, 25))
                    {
                        // There IS an SQL Instance and it listened to network traffic
                        dataSet.SqlConnected = true;
                        dataSet.Confidence = DbaInstanceConfidenceLevel.High;
                    }
                    else
                    {
                        dataSet.SqlConnected = false;
                    }
                }
            }

            foreach (DbaInstanceReport item in toDelete)
                masterList.Remove(item);
        }

        foreach (DbaInstanceReport report in masterList)
        {
            if (report.Confidence >= MinimumConfidence)
                WriteObject(report);
        }
    }
    #endregion Test-SqlInstance

    #region Native scan helpers (the gated hot path)
    // Requests a list of instances from the browser service (SSRP over UDP 1434).
    private List<DbaBrowserReply> GetSqlInstanceBrowserUdp(DbaInstanceParameter computer, bool enableException, int udpTimeout = 2)
    {
        List<DbaBrowserReply> result = new List<DbaBrowserReply>();
        UdpClient? udpClient = null;
        try
        {
            udpClient = new UdpClient();
            udpClient.Client.ReceiveTimeout = udpTimeout * 1000;
            udpClient.Connect(computer.ComputerName, 1434);
            byte[] udpPacket = new byte[] { 0x03 };
            IPEndPoint udpEndpoint = new IPEndPoint(IPAddress.Any, 0);
            udpClient.Client.Blocking = true;
            udpClient.Send(udpPacket, udpPacket.Length);
            byte[] bytesReceived = udpClient.Receive(ref udpEndpoint);
            // Response contains the full SSRP payload; the retired code strips nothing.
            string response = Encoding.ASCII.GetString(bytesReceived);

            // Select-String in the retired function is case-insensitive; match that.
            foreach (Match match in Regex.Matches(response, "(ServerName;([a-zA-Z0-9_-]+);InstanceName;(\\w+);IsClustered;(\\w+);Version;(\\d+\\.\\d+\\.\\d+\\.\\d+);(tcp;(\\d+)){0,1})", RegexOptions.IgnoreCase))
            {
                DbaBrowserReply reply = new DbaBrowserReply();
                reply.MachineName = computer.ComputerName;
                reply.ComputerName = match.Groups[2].Value;
                reply.SqlInstance = $"{match.Groups[2].Value}\\{match.Groups[3].Value}";
                reply.InstanceName = match.Groups[3].Value;
                reply.Version = match.Groups[5].Value;
                reply.IsClustered = string.Equals("Yes", match.Groups[4].Value, StringComparison.OrdinalIgnoreCase);
                if (match.Groups[7].Success)
                    reply.TCPPort = int.Parse(match.Groups[7].Value);
                result.Add(reply);
            }

            udpClient.Close();
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch
        {
            try
            {
                if (udpClient != null)
                    udpClient.Close();
            }
            catch
            {
                // here to avoid an empty catch
            }

            if (enableException)
                throw;
        }
        return result;
    }

    // Tests whether each TCP port is open on the target.
    private List<DbaPortReport> TestTcpPort(DbaInstanceParameter computer, IEnumerable<int> ports)
    {
        List<DbaPortReport> result = new List<DbaPortReport>();
        foreach (int item in ports)
        {
            TcpClient client = new TcpClient();
            try
            {
                client.Connect(computer.ComputerName, item);
                result.Add(new DbaPortReport(computer.ComputerName, item, client.Connected));
            }
            catch
            {
                result.Add(new DbaPortReport(computer.ComputerName, item, false));
            }
            finally
            {
                client.Dispose();
            }
        }
        return result;
    }
    #endregion Native scan helpers

    #region IP range math (native)
    // Streams addresses (yield) exactly like the retired Get-IPrange/Resolve-IPRange: a large
    // range must never be materialized into a list at once (a /8 is 16M addresses), and a stop
    // request can break the enumeration between addresses.
    private IEnumerable<string> ResolveIpRange(string? ipAddress)
    {
        if (!string.IsNullOrEmpty(ipAddress))
        {
            // net472's PowerShellStandard reference lacks the [NotNullWhen] on IsNullOrEmpty,
            // so pin non-nullness here; ipAddress is non-null inside this branch.
            string ipAddress0 = ipAddress!;
            string mode = "Unknown";
            string? address = null;
            string? mask = null;
            int cidr = 0;
            string? rangeStart = null;
            string? rangeEnd = null;

            if (ipAddress0.Contains("/"))
            {
                string[] parts = ipAddress0.Split('/');
                address = parts[0];
                if (parts.Length > 1 && Regex.IsMatch(parts[1], RegexHelper.IPv4))
                {
                    mask = parts[1];
                    mode = "Mask";
                }
                // PS: "0" -as [int] is falsy, so a zero cidr is NOT a cidr - it falls through
                // to the "not a valid IP range" branch, not the cidr-mask branch.
                else if (parts.Length > 1 && int.TryParse(parts[1], out int parsedCidr) && parsedCidr != 0)
                {
                    cidr = parsedCidr;
                    if (cidr < 8 || cidr > 31)
                    {
                        StopFunction($"{ipAddress0} does not contain a valid cidr mask");
                        yield break;
                    }
                    mode = "CIDR";
                }
                else
                {
                    StopFunction($"{ipAddress0} is not a valid IP range");
                }
            }
            else if (ipAddress0.Contains("-"))
            {
                rangeStart = ipAddress0.Split('-')[0];
                rangeEnd = ipAddress0.Split('-')[1];

                if (!Regex.IsMatch(rangeStart, RegexHelper.IPv4))
                {
                    StopFunction($"{ipAddress0} is not a valid IP range");
                    yield break;
                }
                if (!Regex.IsMatch(rangeEnd, RegexHelper.IPv4))
                {
                    StopFunction($"{ipAddress0} is not a valid IP range");
                    yield break;
                }

                mode = "Range";
            }
            else
            {
                if (!Regex.IsMatch(ipAddress0, RegexHelper.IPv4))
                {
                    StopFunction($"{ipAddress0} is not a valid IP address");
                    yield break;
                }
                yield return ipAddress0;
                yield break;
            }

            IEnumerable<string> generated = mode switch
            {
                "CIDR" => GetIpRange(address, null, null, cidr),
                "Mask" => GetIpRange(address, null, mask, 0),
                "Range" => GetIpRange(null, null, null, 0, rangeStart, rangeEnd),
                _ => new string[0]
            };
            foreach (string ip in generated)
            {
                if (CancellationToken.IsCancellationRequested)
                    yield break;
                yield return ip;
            }
        }
        else
        {
            foreach (NetworkInterface iface in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (iface.NetworkInterfaceType.ToString().IndexOf("Ethernet", StringComparison.OrdinalIgnoreCase) < 0)
                    continue;
                foreach (UnicastIPAddressInformation property in iface.GetIPProperties().UnicastAddresses)
                {
                    if (property.Address.AddressFamily != AddressFamily.InterNetwork)
                        continue;
                    foreach (string ip in GetIpRange(property.Address.ToString(), null, null, property.PrefixLength))
                    {
                        if (CancellationToken.IsCancellationRequested)
                            yield break;
                        yield return ip;
                    }
                }
            }
        }
    }

    private static IEnumerable<string> GetIpRange(string? ipAddress, string? start, string? mask, int cidr, string? rangeStart = null, string? rangeEnd = null)
    {
        long startAddr;
        long endAddr;

        if (!string.IsNullOrEmpty(ipAddress))
        {
            IPAddress maskAddr;
            if (cidr > 0)
                maskAddr = IPAddress.Parse(Int64ToIp(Convert.ToInt64(new string('1', cidr) + new string('0', 32 - cidr), 2)));
            else
                maskAddr = IPAddress.Parse(mask!);

            IPAddress ipAddr = IPAddress.Parse(ipAddress);
            long maskLong = IpToInt64(maskAddr.ToString());
            long ipLong = IpToInt64(ipAddr.ToString());
            long networkLong = maskLong & ipLong;
            long broadcastLong = (IpToInt64("255.255.255.255") ^ maskLong) | networkLong;
            startAddr = networkLong;
            endAddr = broadcastLong;
        }
        else
        {
            startAddr = IpToInt64((start ?? rangeStart)!);
            endAddr = IpToInt64(rangeEnd!);
        }

        for (long i = startAddr; i <= endAddr; i++)
            yield return Int64ToIp(i);
    }

    private static long IpToInt64(string ip)
    {
        string[] octets = ip.Split('.');
        return (long)Convert.ToInt64(octets[0]) * 16777216
            + (long)Convert.ToInt64(octets[1]) * 65536
            + (long)Convert.ToInt64(octets[2]) * 256
            + (long)Convert.ToInt64(octets[3]);
    }

    private static string Int64ToIp(long value)
    {
        long a = value / 16777216;
        long b = (value % 16777216) / 65536;
        long c = (value % 65536) / 256;
        long d = value % 256;
        return $"{a}.{b}.{c}.{d}";
    }
    #endregion IP range math

    #region Windows-only discovery via the engine (cold paths, not gated)
    // Returns all computernames with registered MSSQL SPNs (or the service SPNs when getSpn).
    // Runs the retired Get-DomainSPN body verbatim so the System.DirectoryServices adapter
    // semantics hold; dbatools.core takes no System.DirectoryServices dependency.
    private List<string> GetDomainSpn(string? domainController, PSCredential? credential, string computerName, bool getSpn)
    {
        const string script = @"
param($DomainController, $Credential, $ComputerName, $GetSPN)
if (-not $ComputerName) { $ComputerName = '*' }
try {
    if ($DomainController) {
        if ($Credential) {
            $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList ""LDAP://$DomainController"", $Credential.UserName, $Credential.GetNetworkCredential().Password
        } else {
            $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList ""LDAP://$DomainController""
        }
    } else {
        $entry = [ADSI]''
    }
    $objSearcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher -ArgumentList $entry

    $objSearcher.PageSize = 200
    $objSearcher.Filter = ""(&(servicePrincipalName=MSSQLsvc*)(|(name=$ComputerName)(dnshostname=$ComputerName)))""
    $objSearcher.SearchScope = 'Subtree'

    $results = $objSearcher.FindAll()
    foreach ($computer in $results) {
        if ($GetSPN) {
            $computer.Properties[""serviceprincipalname""] | Where-Object { $_ -like ""MSSQLsvc*:*"" }
        } else {
            if ($computer.Properties[""dnshostname""] -and $computer.Properties[""dnshostname""] -ne '') {
                $computer.Properties[""dnshostname""][0]
            } else {
                $computer.Properties[""serviceprincipalname""][0] -match '(?<=/)[^:]*' > $null
                if ($matches) {
                    $matches[0]
                } else {
                    $computer.Properties[""name""][0]
                }
            }
        }
    }
} catch {
    throw
}
";
        return InvokeStringScript(script, domainController, credential, computerName, getSpn);
    }

    // Returns all enabled Windows Server computer objects in the domain.
    private List<string> GetDomainServer(string? domainController, PSCredential? credential)
    {
        const string script = @"
param($DomainController, $Credential)
try {
    if ($DomainController) {
        if ($Credential) {
            $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList ""LDAP://$DomainController"", $Credential.UserName, $Credential.GetNetworkCredential().Password
        } else {
            $entry = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList ""LDAP://$DomainController""
        }
    } else {
        $entry = [ADSI]''
    }
    $objSearcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher -ArgumentList $entry

    $objSearcher.PageSize = 200
    $objSearcher.Filter = ""(&(objectcategory=computer)(operatingSystem=*windows*server*)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))""
    $objSearcher.SearchScope = 'Subtree'

    $results = $objSearcher.FindAll()
    foreach ($computer in $results) {
        if ($computer.Properties[""dnshostname""]) {
            $computer.Properties[""dnshostname""][0]
        } else {
            $computer.Properties[""name""][0]
        }
    }
} catch { throw }
";
        return InvokeStringScript(script, domainController, credential);
    }

    // SSMS UDP-broadcast based instance enumeration. SqlDataSourceEnumerator is Windows-only and
    // absent from Microsoft.Data.SqlClient, so it runs through the engine like the retired code.
    private List<string> EnumerateDataSources()
    {
        const string script = @"
foreach ($instance in ([System.Data.Sql.SqlDataSourceEnumerator]::Instance.GetDataSources())) {
    if ($instance.InstanceName -ne [System.DBNull]::Value) {
        ""$($instance.Servername)\$($instance.InstanceName)""
    } else {
        $instance.Servername
    }
}
";
        return InvokeStringScript(script);
    }

    private List<string> InvokeStringScript(string script, params object?[] args)
    {
        ScriptBlock scriptBlock = ScriptBlock.Create(script);
        Collection<PSObject> raw = InvokeCommand.InvokeScript(false, scriptBlock, null, args);
        List<string> output = new List<string>();
        foreach (PSObject item in raw)
        {
            if (item == null)
                continue;
            object value = item.BaseObject;
            if (value == null)
                continue;
            output.Add(value.ToString() ?? string.Empty);
        }
        return output;
    }
    #endregion Windows-only discovery

    #region Small helpers
    private static bool HasFlag(DbaInstanceScanType value, DbaInstanceScanType flag)
    {
        return (value & flag) == flag;
    }

    private static bool HasFlag(DbaInstanceDiscoveryType value, DbaInstanceDiscoveryType flag)
    {
        return (value & flag) == flag;
    }

    private static List<int> Distinct(IEnumerable<int> values)
    {
        List<int> result = new List<int>();
        foreach (int value in values)
        {
            if (!result.Contains(value))
                result.Add(value);
        }
        return result;
    }

    private static bool ContainsIgnoreCase(List<string> list, string? value)
    {
        foreach (string item in list)
        {
            if (string.Equals(item, value, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    // PS: $spns | Where-Object { $_ -like "*:$port" }
    private static bool LikeSuffix(string spn, int port)
    {
        if (string.IsNullOrEmpty(spn))
            return false;
        return spn.EndsWith(":" + port.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    private static object[]? FilterServices(Collection<PSObject>? services, Func<PSObject, bool> predicate)
    {
        if (services == null)
            return null;
        List<object> matched = new List<object>();
        foreach (PSObject service in services)
        {
            if (predicate(service))
                matched.Add(service);
        }
        // PS Where-Object emits nothing (=> $null) when there is no match.
        return matched.Count > 0 ? matched.ToArray() : null;
    }

    private static IEnumerable<DbaPortReport> EnumeratePortsScanned(DbaInstanceReport report)
    {
        if (report.PortsScanned == null)
            return new DbaPortReport[0];
        return report.PortsScanned;
    }

    private static IEnumerable<string> PortsScannedText(DbaInstanceReport report)
    {
        foreach (DbaPortReport pr in EnumeratePortsScanned(report))
            yield return $"Port {pr.Port}={pr.IsOpen}";
    }

    private static string? PropStr(object? obj, string name)
    {
        if (obj == null)
            return null;
        PSObject pso = obj as PSObject ?? new PSObject(obj);
        PSPropertyInfo? property = pso.Properties[name];
        object? value = property != null ? property.Value : null;
        return value != null ? value.ToString() : null;
    }

    // PS: catch { if ($_.Exception.InnerException.Errors.Class -lt 25) {...} }
    // A missing Errors collection maps to PS's ($null -lt 25) => $true; a present one is $true when
    // ANY error Class is below the threshold.
    private static bool SqlErrorClassBelow(Exception? exception, int threshold)
    {
        bool foundErrors = false;
        Exception? cursor = exception;
        while (cursor != null)
        {
            System.Reflection.PropertyInfo? errorsProperty = cursor.GetType().GetProperty("Errors");
            if (errorsProperty != null)
            {
                object? errors = errorsProperty.GetValue(cursor);
                if (errors is IEnumerable enumerable && !(errors is string))
                {
                    foreach (object? error in enumerable)
                    {
                        if (error == null)
                            continue;
                        System.Reflection.PropertyInfo? classProperty = error.GetType().GetProperty("Class");
                        if (classProperty == null)
                            continue;
                        object? classValue = classProperty.GetValue(error);
                        if (classValue == null)
                            continue;
                        foundErrors = true;
                        try
                        {
                            if (Convert.ToInt32(classValue) < threshold)
                                return true;
                        }
                        catch
                        {
                            // non-numeric class - ignore
                        }
                    }
                }
            }
            cursor = cursor.InnerException;
        }
        return !foundErrors;
    }

    private void Progress(string activity, string message)
    {
        ProgressBridge.Write(this, 1, activity, message);
    }
    #endregion Small helpers
}
