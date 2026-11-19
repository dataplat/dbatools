#nullable enable
#pragma warning disable CA1416 // Windows-only command: WMI (StdRegProv), the local registry and WinRM remoting

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Net;
using System.Net.Sockets;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Management.Infrastructure;
using Microsoft.Management.Infrastructure.Options;
using Microsoft.Win32;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves comprehensive hardware and system information from Windows computers hosting SQL Server instances.
/// </summary>
/// <para>Collects detailed system specifications including processor details, memory configuration, domain membership, and hardware information from target computers. This function is essential for SQL Server capacity planning, pre-installation system verification, and troubleshooting performance issues by providing complete hardware inventory data.</para>
/// <para>The function queries WMI classes (Win32_ComputerSystem and Win32_Processor) to gather CPU details, determines hyperthreading status, checks total physical memory, and identifies domain roles. It also detects pending reboots that could affect SQL Server operations and optionally retrieves AWS EC2 metadata for cloud-hosted instances.</para>
/// <para>Use this command when documenting SQL Server environments, verifying system requirements before installations or upgrades, or investigating hardware-related performance bottlenecks.</para>
/// <example>
///   <code>PS C:\&gt; Get-DbaComputerSystem</code>
///   <para>Returns information about the local computer's computer system</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaComputerSystem -ComputerName sql2016</code>
///   <para>Returns information about the sql2016's computer system</para>
/// </example>
/// <example>
///   <code>PS C:\&gt; Get-DbaComputerSystem -ComputerName sql2016 -IncludeAws</code>
///   <para>Returns information about the sql2016's computer system and includes additional properties around the EC2 instance.</para>
/// </example>
[Cmdlet(VerbsCommon.Get, "DbaComputerSystem")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaComputerSystemCommand : DbaBaseCmdlet
{
    // private/functions/Test-PendingReboot.ps1 registry locations (HKEY_LOCAL_MACHINE).
    private const uint HkeyLocalMachine = 2147483650;
    private const string CbsKey = "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Component Based Servicing";
    private const string WuauKey = "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\WindowsUpdate\\Auto Update";
    private const string SessionManagerKey = "SYSTEM\\CurrentControlSet\\Control\\Session Manager";


    /// <summary>
    /// <para>Specifies the target computer(s) to collect system information from. Defaults to the local computer when not specified.</para>
    /// <para>Use this to inventory multiple SQL Server hosts at once or to gather system details from remote servers for capacity planning and troubleshooting.</para>
    /// </summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [Alias("cn", "host", "Server")]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Alternate credential object to use for accessing the target computer(s).</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>
    /// <para>Retrieves additional AWS EC2 metadata when the target computer is hosted on Amazon Web Services. Adds properties like AMI ID, instance type, availability zone, and IAM role information.</para>
    /// <para>Use this switch when documenting cloud-hosted SQL Server environments or when you need AWS-specific details for compliance or cost management purposes.</para>
    /// </summary>
    [Parameter]
    public SwitchParameter IncludeAws { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (ComputerName is null)
        {
            return;
        }

        foreach (DbaInstanceParameter? computer in ComputerName)
        {
            try
            {
                // PS: $server = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Credential $Credential
                // The nested function's own EnableException stays false (not forwarded), so a
                // resolution failure is ITS "DNS name ... not found" warning plus a null result.
                NetworkResolutionService.NetworkResolutionResult? resolution = ResolveComputer(computer);
                string? computerResolved = resolution?.FullComputerName;

                if (string.IsNullOrEmpty(computerResolved))
                {
                    // PS: Stop-Function -Message "Unable to resolve hostname of $computer. Skipping." -Continue
                    // sits INSIDE the function's own try — under EnableException the throw lands in
                    // the catch below and surfaces as its "Failure" wrap, exactly like PS.
                    // ToString is the text "$computer" gives; + would take the type's implicit string conversion, which faults on a null element.
                    string unresolved = "Unable to resolve hostname of " + computer?.ToString() + ". Skipping.";
                    if (EnableException.ToBool())
                    {
                        throw CaughtNestedStopFunction("Get-DbaComputerSystem", unresolved).Exception;
                    }
                    StopFunction(unresolved, continueLoop: true);
                    continue;
                }

                // PS: Get-DbaCmObject -ClassName Win32_ComputerSystem/Win32_Processor WITHOUT
                // -EnableException: a chain failure is the nested command's own warning (the
                // exact composed message) and a null result; this command keeps going.
                PSObject? computerSystem = QueryFirst(computerResolved!, "Win32_ComputerSystem");
                List<PSObject> computerProcessor = QueryAll(computerResolved!, "Win32_Processor");

                // PS: switch with a default branch — but switch($null) runs NO branch, so a
                // missing value stays null instead of "Unknown".
                object? adminRaw = GetRawValue(computerSystem, "AdminPasswordStatus");
                string? adminPasswordStatus = null;
                if (adminRaw is not null)
                {
                    switch (Convert.ToInt64(adminRaw, CultureInfo.InvariantCulture))
                    {
                        case 0: adminPasswordStatus = "Disabled"; break;
                        case 1: adminPasswordStatus = "Enabled"; break;
                        case 2: adminPasswordStatus = "Not Implemented"; break;
                        case 3: adminPasswordStatus = "Unknown"; break;
                        default: adminPasswordStatus = "Unknown"; break;
                    }
                }

                // PS: switch with NO default — unmatched (and null) yields $null.
                object? domainRoleRaw = GetRawValue(computerSystem, "DomainRole");
                string? domainRole = null;
                if (domainRoleRaw is not null)
                {
                    switch (Convert.ToInt64(domainRoleRaw, CultureInfo.InvariantCulture))
                    {
                        case 0: domainRole = "Standalone Workstation"; break;
                        case 1: domainRole = "Member Workstation"; break;
                        case 2: domainRole = "Standalone Server"; break;
                        case 3: domainRole = "Member Server"; break;
                        case 4: domainRole = "Backup Domain Controller"; break;
                        case 5: domainRole = "Primary Domain Controller"; break;
                    }
                }

                // PS: -gt converts $null to 0 on either side.
                bool isHyperThreading = ToLongOrZero(GetRawValue(computerSystem, "NumberOfLogicalProcessors")) > ToLongOrZero(GetRawValue(computerSystem, "NumberOfProcessors"));

                bool isAws = false;
                PSObject? awsProps = null;
                if (IncludeAws.ToBool())
                {
                    // PS: Invoke-Command2 runs the probe on the target: in this process for the
                    // local computer, through a WinRM session otherwise. The metadata endpoint is
                    // link-local, so only the instance itself can reach it.
                    DbaInstanceParameter awsTarget = new DbaInstanceParameter(computerResolved!);
                    if (awsTarget.IsLocalHost)
                    {
                        string awsComputer = computerResolved!;
                        awsProps = ReadAws((string method, string path, Dictionary<string, string>? headers, int timeoutSeconds, AwsFailure failure, out object? response) => SendLocal(awsComputer, method, path, headers, timeoutSeconds, failure, out response), out isAws);
                    }
                    else
                    {
                        awsProps = ReadAwsRemote(awsTarget.ComputerName, out isAws);
                    }
                }

                object? pendingReboot = null;
                try
                {
                    WriteMessage(MessageLevel.Verbose, "Getting information about pending reboots.");
                    pendingReboot = TestPendingReboot(computerResolved!);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch
                {
                    WriteMessage(MessageLevel.Verbose, "Not able to get information about pending reboots.");
                }

                object? totalPhysicalMemoryRaw = GetRawValue(computerSystem, "TotalPhysicalMemory");

                PSObject inputObject = new();
                inputObject.Properties.Add(new PSNoteProperty("ComputerName", computerResolved));
                inputObject.Properties.Add(new PSNoteProperty("Domain", GetRawValue(computerSystem, "Domain")));
                inputObject.Properties.Add(new PSNoteProperty("DomainRole", domainRole));
                inputObject.Properties.Add(new PSNoteProperty("Manufacturer", GetRawValue(computerSystem, "Manufacturer")));
                inputObject.Properties.Add(new PSNoteProperty("Model", GetRawValue(computerSystem, "Model")));
                inputObject.Properties.Add(new PSNoteProperty("SystemFamily", GetRawValue(computerSystem, "SystemFamily")));
                inputObject.Properties.Add(new PSNoteProperty("SystemSkuNumber", GetRawValue(computerSystem, "SystemSKUNumber")));
                inputObject.Properties.Add(new PSNoteProperty("SystemType", GetRawValue(computerSystem, "SystemType")));
                inputObject.Properties.Add(new PSNoteProperty("ProcessorName", EnumerateMember(computerProcessor, "Name")));
                inputObject.Properties.Add(new PSNoteProperty("ProcessorCaption", EnumerateMember(computerProcessor, "Caption")));
                inputObject.Properties.Add(new PSNoteProperty("ProcessorMaxClockSpeed", EnumerateMember(computerProcessor, "MaxClockSpeed")));
                inputObject.Properties.Add(new PSNoteProperty("NumberLogicalProcessors", GetRawValue(computerSystem, "NumberOfLogicalProcessors")));
                inputObject.Properties.Add(new PSNoteProperty("NumberProcessors", GetRawValue(computerSystem, "NumberOfProcessors")));
                inputObject.Properties.Add(new PSNoteProperty("IsHyperThreading", isHyperThreading));
                inputObject.Properties.Add(new PSNoteProperty("TotalPhysicalMemory", totalPhysicalMemoryRaw is null ? null : new Size(Convert.ToInt64(totalPhysicalMemoryRaw, CultureInfo.InvariantCulture))));
                inputObject.Properties.Add(new PSNoteProperty("IsDaylightSavingsTime", GetRawValue(computerSystem, "EnableDaylightSavingsTime")));
                inputObject.Properties.Add(new PSNoteProperty("DaylightInEffect", GetRawValue(computerSystem, "DaylightInEffect")));
                inputObject.Properties.Add(new PSNoteProperty("DnsHostName", GetRawValue(computerSystem, "DNSHostName")));
                inputObject.Properties.Add(new PSNoteProperty("IsSystemManagedPageFile", GetRawValue(computerSystem, "AutomaticManagedPagefile")));
                inputObject.Properties.Add(new PSNoteProperty("AdminPasswordStatus", adminPasswordStatus));
                inputObject.Properties.Add(new PSNoteProperty("PendingReboot", pendingReboot));

                if (IncludeAws.ToBool() && isAws)
                {
                    inputObject.Properties.Add(new PSNoteProperty("AwsAmiId", GetRawValue(awsProps, "AmiId")));
                    inputObject.Properties.Add(new PSNoteProperty("AwsIamRoleArn", GetRawValue(awsProps, "IamRoleArn")));
                    inputObject.Properties.Add(new PSNoteProperty("AwsEc2InstanceId", GetRawValue(awsProps, "InstanceId")));
                    inputObject.Properties.Add(new PSNoteProperty("AwsEc2InstanceType", GetRawValue(awsProps, "InstanceType")));
                    inputObject.Properties.Add(new PSNoteProperty("AwsAvailabilityZone", GetRawValue(awsProps, "AvailabilityZone")));
                    inputObject.Properties.Add(new PSNoteProperty("AwsPublicHostName", GetRawValue(awsProps, "PublicHostname")));
                }

                // PS: Select-DefaultView -ExcludeProperty builds the display set from
                // Get-Member output, which is ALPHABETICALLY sorted — not declaration order.
                string[] excludes = { "SystemSkuNumber", "IsDaylightSavingsTime", "DaylightInEffect", "DnsHostName", "AdminPasswordStatus" };
                List<string> displayNames = new();
                foreach (PSPropertyInfo property in inputObject.Properties)
                {
                    if (Array.FindIndex(excludes, e => string.Equals(e, property.Name, StringComparison.OrdinalIgnoreCase)) < 0)
                    {
                        displayNames.Add(property.Name);
                    }
                }
                displayNames.Sort(StringComparer.OrdinalIgnoreCase);
                OutputHelper.SetDefaultDisplayPropertySet(inputObject, displayNames.ToArray());
                WriteObject(inputObject);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                // PS: catch { Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue }
                StopFunction("Failure", target: computer, errorRecord: new ErrorRecord(ex, "dbatools_Get-DbaComputerSystem", ErrorCategory.NotSpecified, computer), continueLoop: true);
                continue;
            }
        }
    }

    // PS: Resolve-DbaNetworkName -ComputerName $computer.ComputerName. A null element of -ComputerName passes $null, whose
    // loop in that function runs no time: no result and no warning of its own.
    private NetworkResolutionService.NetworkResolutionResult? ResolveComputer(DbaInstanceParameter? computer)
    {
        if (computer is null)
        {
            return null;
        }

        string cName = computer.IsLocalHost ? Environment.MachineName : computer.ComputerName;
        ManagementConnectionType lastRung = ManagementConnectionType.None;
        CimService.CmObjectFailure? identityFailure = null;
        CimService.CmObjectObserver identityObserver = new()
        {
            Rung = (rung, step, error) => lastRung = rung,
            Failure = reported => identityFailure = reported
        };
        NetworkResolutionService.NetworkResolutionResult? resolution = null;
        Exception? failure = null;
        try
        {
            resolution = NetworkResolutionService.Resolve(this, new DbaInstanceParameter(computer.ComputerName), Credential, false, identityObserver);
            if (resolution is null)
            {
                // The shared resolver returns only null for a failed lookup, and the warning carries that failure.
                try
                {
                    Dns.GetHostEntry(cName);
                    failure = new SocketException((int)SocketError.HostNotFound);
                }
                catch (Exception ex) when (ex is not PipelineStoppedException)
                {
                    failure = ex;
                }
            }
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            resolution = null;
            failure = ex;
        }

        // Outside the resolution try: a write this report makes is never mistaken for a failed lookup.
        ReportIdentityFailure(identityFailure, cName, lastRung);
        if (resolution is not null)
        {
            return resolution;
        }

        // PS: Stop-Function -Message "DNS name $cName not found" -Continue -ErrorRecord $_, under the nested function's name
        // and its own -EnableException, which this command never forwards. Under -WarningAction Stop the pin's catch then writes
        // a "Failure" warning carrying this one and stops on that; a cmdlet's stopped write ends the pipeline, so here the stop
        // names this warning alone. The pin's side is measured on both editions: evidence/probe-run-pin-computersystem-route-
        // 20261116-20261116070627.txt (sha256 045d6ea0), cases warningstop-* (watchman 492972de).
        WarnNestedStopFunction("Resolve-DbaNetworkName", "DNS name " + cName + " not found",
            errorRecord: new ErrorRecord(failure!, "dbatools_Resolve-DbaNetworkName", ErrorCategory.NotSpecified, null));
        return null;
    }

    // PS: Resolve-DbaNetworkName.ps1:259 reads win32_ComputerSystem with Get-DbaCmObject -EnableException inside its own try
    // (:249-284), whose catch writes only a Verbose message, and the resolver carries on with the name it has. That nested
    // Stop-Function's warning reaches the caller's warning stream and -WarningVariable alike and its record lands in $error
    // (probe-run capture 045d6ea0, cases cim-local-*: warnings and warningVar equal in every case on both editions), so it is
    // written as PowerPlan writes this read's failure, through the resolver's observer (watchman 2ea60ffc, CmObjectFailureRecord.cs).
    private void ReportIdentityFailure(CimService.CmObjectFailure? identityFailure, string cName, ManagementConnectionType lastRung)
    {
        if (identityFailure is null)
        {
            return;
        }

        string key = cName.ToLowerInvariant();
        ConnectionHost.Connections.TryGetValue(key, out ManagementConnection? connection);
        CmObjectFailureRecord? report = CmObjectFailureRecord.Build(identityFailure, connection!, key, lastRung, true, "win32_ComputerSystem", @"root\cimv2");
        if (report is not null)
        {
            WarnNestedStopFunction("Get-DbaCmObject", report.Message, report.Target, report.Record, report.Category, report.OverrideExceptionMessage);
        }
    }

    // PS: Test-Bound "Credential" branches to the same call with/without -Credential.
    private CimService.CmObjectResult Query(string computerResolved, string className, CimService.CmObjectObserver observer)
    {
        CimService.CmObjectRequest request = new()
        {
            ComputerName = new DbaInstanceParameter(computerResolved).ComputerName,
            ClassName = className,
            Observer = observer
        };
        if (TestBound(nameof(Credential)))
        {
            request.Credential = Credential;
        }
        return CimService.GetCmObject(this, request);
    }

    private PSObject? QueryFirst(string computerResolved, string className)
    {
        List<PSObject> instances = QueryAll(computerResolved, className);
        return instances.Count > 0 ? instances[0] : null;
    }

    private List<PSObject> QueryAll(string computerResolved, string className)
    {
        ManagementConnectionType lastRung = ManagementConnectionType.None;
        CimService.CmObjectFailure? failure = null;
        CimService.CmObjectObserver observer = new()
        {
            Rung = (rung, step, error) => lastRung = rung,
            Failure = reported => failure = reported
        };
        try
        {
            CimService.CmObjectResult result = Query(computerResolved, className, observer);
            ForwardErrors(result.PassthroughErrors);
            return result.Instances;
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            // PS: Get-DbaComputerSystem.ps1:114-118 call Get-DbaCmObject WITHOUT -EnableException. Its Stop-Function (for a
            // computer no protocol reaches, Get-DbaCmObject.ps1:296) is a warning under its own name with its record in $error
            // and -ErrorVariable, none in the error stream, whatever this command's -EnableException, and the caller goes on
            // with a null result (probe-run capture 045d6ea0, cases cim-local-*; watchman 69096191, audit.txt:42).
            string name = new DbaInstanceParameter(computerResolved).ComputerName.ToLowerInvariant();
            ConnectionHost.Connections.TryGetValue(name, out ManagementConnection? connection);
            CmObjectFailureRecord? report = failure is null ? null : CmObjectFailureRecord.Build(failure, connection!, name, lastRung, true, className, @"root\cimv2");
            if (report is null)
            {
                WriteNestedWarning("Get-DbaCmObject", ex.Message, ex);
                return new List<PSObject>();
            }

            WarnNestedStopFunction("Get-DbaCmObject", report.Message, report.Target, report.Record, report.Category, report.OverrideExceptionMessage);
            return new List<PSObject>();
        }
    }

    // A Get-DbaCmObject failure the observer did not report: the nested command's warning under its own name, without a
    // record, whatever this command's -EnableException says (as GetDbaClientProtocolCommand.cs writes it).
    private void WriteNestedWarning(string functionName, string message, Exception? exception)
    {
        MessageService.Write(this, new MessageService.MessageRequest
        {
            FunctionName = functionName,
            ModuleName = "dbatools",
            Level = MessageLevel.Warning,
            Message = message,
            Exception = exception,
            EnableException = false,
            File = MyInvocation.ScriptName,
            Line = MyInvocation.ScriptLineNumber
        });
    }

    // Records from another command or from the target host's session flow to the caller's
    // error stream as non-terminating errors, as the PS source's nested calls left them.
    private void ForwardErrors(IEnumerable<ErrorRecord> errors)
    {
        foreach (ErrorRecord error in errors)
        {
            WriteError(error);
        }
    }

    #region -IncludeAws

    // How the PS source surfaced a failed metadata request.
    private enum AwsFailure
    {
        // A request the PS source did not make: not reported.
        Silent,

        // The probe of the metadata root: in process, catch [System.Net.WebException] and its
        // warning; on a remote target, the error record Invoke-Command forwards.
        Probe,

        // A metadata read: an error record on the error stream.
        Metadata
    }

    // One request on the target host, by path below the metadata address; false when it failed,
    // after reporting the failure the way the PS source surfaced it.
    private delegate bool AwsSend(string method, string path, Dictionary<string, string>? headers, int timeoutSeconds, AwsFailure failure, out object? response);

    // PS: $isAws = ((Invoke-TlsRestMethod -TimeoutSec 15 -Uri 'http://169.254.169.254').StatusCode) -eq 200
    // run on the target, then, when $isAws, the [PSCustomObject] of six metadata reads.
    // Invoke-RestMethod returns the response body, which has no StatusCode, so the PS source never
    // recognized an EC2 instance. Here the probe of the root keeps its timeout and its failure
    // report; the instance is EC2 when the service also returns an EC2 instance id. A service that
    // issues IMDSv2 session tokens is asked for one first, and every request carries it, so an
    // instance that requires IMDSv2 answers too.
    private PSObject? ReadAws(AwsSend send, out bool isAws)
    {
        isAws = false;
        Dictionary<string, string>? headers = null;
        Dictionary<string, string> tokenRequest = new() { [AwsInstanceMetadata.TokenTtlHeader] = AwsInstanceMetadata.TokenTtlSeconds };
        if (send("PUT", AwsInstanceMetadata.TokenPath, tokenRequest, AwsInstanceMetadata.TokenTimeoutSeconds, AwsFailure.Silent, out object? token) && token is string tokenText && tokenText.Length > 0)
        {
            headers = new Dictionary<string, string> { [AwsInstanceMetadata.TokenHeader] = tokenText };
        }

        if (!send("GET", "", headers, AwsInstanceMetadata.ProbeTimeoutSeconds, AwsFailure.Probe, out _))
        {
            return null;
        }
        if (!send("GET", AwsInstanceMetadata.MetadataPath + "instance-id", headers, AwsInstanceMetadata.ProbeTimeoutSeconds, AwsFailure.Silent, out object? instanceId) || !AwsInstanceMetadata.IsInstanceId(instanceId))
        {
            return null;
        }
        isAws = true;
        return ReadAwsProperties(send, headers);
    }

    // PS: the six Invoke-TlsRestMethod reads of the metadata script block; iam/info is JSON and
    // Invoke-RestMethod reads its InstanceProfileArn member.
    private PSObject ReadAwsProperties(AwsSend send, Dictionary<string, string>? headers)
    {
        PSObject props = new();
        props.Properties.Add(new PSNoteProperty("AmiId", ReadAwsMetadata(send, headers, "ami-id")));
        props.Properties.Add(new PSNoteProperty("IamRoleArn", AwsInstanceMetadata.ReadMember(ReadAwsMetadata(send, headers, "iam/info"), "InstanceProfileArn")));
        props.Properties.Add(new PSNoteProperty("InstanceId", ReadAwsMetadata(send, headers, "instance-id")));
        props.Properties.Add(new PSNoteProperty("InstanceType", ReadAwsMetadata(send, headers, "instance-type")));
        props.Properties.Add(new PSNoteProperty("AvailabilityZone", ReadAwsMetadata(send, headers, "placement/availability-zone")));
        props.Properties.Add(new PSNoteProperty("PublicHostname", ReadAwsMetadata(send, headers, "public-hostname")));
        return props;
    }

    private static object? ReadAwsMetadata(AwsSend send, Dictionary<string, string>? headers, string category)
    {
        send("GET", AwsInstanceMetadata.MetadataPath + category, headers, 0, AwsFailure.Metadata, out object? response);
        return response;
    }

    // PS (local target): Invoke-Command2 runs the script block in this process.
#pragma warning disable SYSLIB0014 // HttpWebRequest: a synchronous request with a timeout on both net472 and net8.0
    private bool SendLocal(string computerResolved, string method, string path, Dictionary<string, string>? headers, int timeoutSeconds, AwsFailure failure, out object? response)
    {
        response = null;
        string uri = AwsInstanceMetadata.BaseAddress + path;
        try
        {
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(uri);
            request.Method = method;
            if (timeoutSeconds > 0)
            {
                request.Timeout = timeoutSeconds * 1000;
            }
            if (headers is not null)
            {
                foreach (KeyValuePair<string, string> header in headers)
                {
                    request.Headers[header.Key] = header.Value;
                }
            }
            if (string.Equals(method, "PUT", StringComparison.Ordinal))
            {
                request.ContentLength = 0;
            }
            using (HttpWebResponse reply = (HttpWebResponse)request.GetResponse())
            using (Stream body = reply.GetResponseStream())
            using (StreamReader reader = new StreamReader(body))
            {
                response = reader.ReadToEnd();
            }
            return true;
        }
        catch (WebException ex)
        {
            if (failure == AwsFailure.Probe)
            {
                WriteMessage(MessageLevel.Warning, computerResolved + " was not found to be an EC2 instance. Verify http://169.254.169.254 is accessible on the computer.");
            }
            else if (failure == AwsFailure.Metadata)
            {
                WriteError(new ErrorRecord(ex, "WebCmdletWebResponseException", ErrorCategory.InvalidOperation, uri));
            }
            return false;
        }
    }
#pragma warning restore SYSLIB0014

    // PS (remote target): Invoke-Command2 opens a WinRM session (PSRemoting.PsSession.UseSSL and
    // .Port configuration) and runs Invoke-RestMethod there. The commands run on the target
    // with their values as parameters. A failed request is an error record on the caller's
    // error stream, as Invoke-Command forwards it, and marks the host as not EC2. A session
    // that cannot open throws to the caller's "Failure", like New-PSSession -ErrorAction Stop.
    private PSObject? ReadAwsRemote(string computerName, out bool isAws)
    {
        isAws = false;
        bool useSsl = LanguagePrimitives.IsTrue(ConnectionService.GetConfigurationValue("psremoting.pssession.usessl"));
        int port = useSsl ? 5986 : 5985;
        object? configuredPort = ConnectionService.GetConfigurationValue("psremoting.pssession.port");
        if (configuredPort is not null)
        {
            int parsed = LanguagePrimitives.ConvertTo<int>(configuredPort);
            if (parsed > 0)
            {
                port = parsed;
            }
        }

        using (System.Management.Automation.Runspaces.Runspace runspace = RunspaceFactory.CreateRunspace(new WSManConnectionInfo(useSsl, computerName, port, "/wsman", "http://schemas.microsoft.com/powershell/Microsoft.PowerShell", Credential)))
        {
            runspace.Open();
            try
            {
                return ReadAws((string method, string path, Dictionary<string, string>? headers, int timeoutSeconds, AwsFailure failure, out object? response) => SendRemote(runspace, method, path, headers, timeoutSeconds, failure, out response), out isAws);
            }
            finally
            {
                runspace.Close();
            }
        }
    }

    private bool SendRemote(System.Management.Automation.Runspaces.Runspace runspace, string method, string path, Dictionary<string, string>? headers, int timeoutSeconds, AwsFailure failure, out object? response)
    {
        Hashtable headerTable = new Hashtable();
        if (headers is not null)
        {
            foreach (KeyValuePair<string, string> header in headers)
            {
                headerTable[header.Key] = header.Value;
            }
        }
        List<ErrorRecord> errors = new();
        Collection<PSObject> output = InvokeRemoteRestMethod(runspace, method, AwsInstanceMetadata.BaseAddress + path, headerTable, timeoutSeconds, errors);
        if (failure != AwsFailure.Silent)
        {
            ForwardErrors(errors);
        }
        response = FirstOutput(output);
        return errors.Count == 0;
    }

    // One Invoke-RestMethod on the target; TimeoutSec 0 is the cmdlet's indefinite default.
    private Collection<PSObject> InvokeRemoteRestMethod(System.Management.Automation.Runspaces.Runspace runspace, string method, string uri, Hashtable headerTable, int timeoutSec, List<ErrorRecord> errors)
    {
        using (PowerShell rest = PowerShell.Create())
        {
            rest.Runspace = runspace;
            rest.AddCommand("Invoke-RestMethod").AddParameter("Uri", uri).AddParameter("Method", method).AddParameter("Headers", headerTable).AddParameter("TimeoutSec", timeoutSec);
            using (CancellationToken.Register(() => rest.Stop()))
            {
                try
                {
                    Collection<PSObject> output = rest.Invoke();
                    errors.AddRange(rest.Streams.Error);
                    return output;
                }
                catch (RuntimeException ex) when (ex.ErrorRecord is not null && ex is not PipelineStoppedException)
                {
                    // A terminating error of the remote command reaches Invoke-Command's caller
                    // as an error record, not as an exception.
                    errors.AddRange(rest.Streams.Error);
                    errors.Add(ex.ErrorRecord);
                    return new Collection<PSObject>();
                }
            }
        }
    }

    private static object? FirstOutput(Collection<PSObject> output)
    {
        if (output.Count == 0 || output[0] is null)
        {
            return null;
        }
        return output[0].BaseObject is PSCustomObject ? output[0] : output[0].BaseObject;
    }

    #endregion

    #region Pending reboot

    // private/functions/Test-PendingReboot.ps1 (the caller never passes -NoPendingRename).
    // Invoke-Command2 runs each Get-ItemProperty probe in this process for the local computer
    // and on the target otherwise; here the local registry and the target's StdRegProv
    // (root\default) answer the same reads. -ErrorAction SilentlyContinue on each probe makes
    // a missing or unreadable key "not found"; a target that cannot be reached throws, and
    // the caller reports PendingReboot as $null.
    private object TestPendingReboot(string computerResolved)
    {
        DbaInstanceParameter target = new DbaInstanceParameter(computerResolved);
        if (target.IsLocalHost)
        {
            return ProbePendingReboot(null);
        }
        return ProbeRemotePendingReboot(target.ComputerName);
    }

    // The pinned Invoke-Command2 reads a remote target over PowerShell remoting (WinRM) whatever
    // New-DbaCmConnection or Set-DbaCmConnection -DisabledConnectionTypes says: those settings
    // govern Get-DbaCmObject, not Invoke-Command2. Here the target's StdRegProv is read over CIM,
    // WSMan (WinRM) first, then DCOM, likewise without consulting them. One session per protocol
    // tried, disposed after its reads. A CIM failure over WSMan runs the reads again over DCOM; a
    // DCOM failure throws, and the caller reports PendingReboot as $null.
    private object ProbeRemotePendingReboot(string computerName)
    {
        TimeSpan timeout = GetCimOperationTimeout();

        WSManSessionOptions wsmanOptions = new WSManSessionOptions { Timeout = timeout };
        ApplyRemotingConfiguration(wsmanOptions);
        AddSessionCredential(wsmanOptions);
        try
        {
            using CimSession wsmanSession = CimSession.Create(computerName, wsmanOptions);
            return ProbePendingReboot(wsmanSession);
        }
        catch (CimException)
        {
            // A WSMan session is created lazily, so a target WinRM cannot reach fails at the
            // first read; the reads run again over DCOM below.
        }

        DComSessionOptions dcomOptions = new DComSessionOptions
        {
            PacketPrivacy = true,
            PacketIntegrity = true,
            Impersonation = ImpersonationType.Impersonate,
            Timeout = timeout
        };
        AddSessionCredential(dcomOptions);
        using CimSession dcomSession = CimSession.Create(computerName, dcomOptions);
        return ProbePendingReboot(dcomSession);
    }

    // The three probes of Test-PendingReboot in the pinned order: on the local registry when
    // registry is null, otherwise on the target's StdRegProv through the given session.
    private object ProbePendingReboot(CimSession? registry)
    {
        // Component Based Servicing and Windows Update record a pending reboot as the
        // RebootPending and RebootRequired SUBKEYS. The PS source asked Get-ItemProperty for a
        // value of that name, which Windows does not write, so it never saw either; the value
        // or the subkey marks the reboot here.
        if (RegistryValueExists(registry, CbsKey, "RebootPending") || RegistryKeyExists(registry, CbsKey + "\\RebootPending"))
        {
            WriteMessage(MessageLevel.Verbose, "Reboot pending detected in the Component Based Servicing registry key");
            return true;
        }

        // Query WUAU from the registry
        if (RegistryValueExists(registry, WuauKey, "RebootRequired") || RegistryKeyExists(registry, WuauKey + "\\RebootRequired"))
        {
            WriteMessage(MessageLevel.Verbose, "WUAU has a reboot pending");
            return true;
        }

        // Query PendingFileRenameOperations from the registry
        if (LanguagePrimitives.IsTrue(ReadRegistryValue(registry, SessionManagerKey, "PendingFileRenameOperations")))
        {
            WriteMessage(MessageLevel.Verbose, "Reboot pending in the PendingFileRenameOperations registry value");
            return true;
        }
        return false;
    }

    // Invoke-Command2's own session settings (Invoke-Command2.ps1:67-68 and :98-113 at the pin), read as ReadAwsRemote
    // reads them: PSRemoting.PsSession.UseSSL and .Port (a port only when one above 0 is configured, otherwise the
    // protocol's default), and the New-PSSessionOption values PSRemoting.PsSessionOption.IncludePortInSPN, SkipCACheck,
    // SkipCNCheck and SkipRevocationCheck. The lab's WinRM listens on HTTP at its default port only, so no test here can
    // show a host that answers on HTTPS alone; these settings are not exercised on the lab.
    private static void ApplyRemotingConfiguration(WSManSessionOptions options)
    {
        options.UseSsl = LanguagePrimitives.IsTrue(ConnectionService.GetConfigurationValue("psremoting.pssession.usessl"));
        object? configuredPort = ConnectionService.GetConfigurationValue("psremoting.pssession.port");
        if (configuredPort is not null)
        {
            int parsed = LanguagePrimitives.ConvertTo<int>(configuredPort);
            if (parsed > 0)
            {
                options.DestinationPort = (uint)parsed;
            }
        }
        options.EncodePortInServicePrincipalName = LanguagePrimitives.IsTrue(ConnectionService.GetConfigurationValue("psremoting.pssessionoption.includeportinspn"));
        options.CertCACheck = !LanguagePrimitives.IsTrue(ConnectionService.GetConfigurationValue("psremoting.pssessionoption.skipcacheck"));
        options.CertCNCheck = !LanguagePrimitives.IsTrue(ConnectionService.GetConfigurationValue("psremoting.pssessionoption.skipcncheck"));
        options.CertRevocationCheck = !LanguagePrimitives.IsTrue(ConnectionService.GetConfigurationValue("psremoting.pssessionoption.skiprevocationcheck"));
    }

    // Invoke-Command2 passes -Credential only when the caller bound it.
    private void AddSessionCredential(CimSessionOptions options)
    {
        if (!TestBound(nameof(Credential)) || Credential is null)
        {
            return;
        }
        NetworkCredential network = Credential.GetNetworkCredential();
        options.AddDestinationCredentials(new CimCredential(PasswordAuthenticationMechanism.Default, network.Domain, network.UserName, Credential.Password));
    }

    // New-DbaCimSessionOptionWithTimeout: ComputerManagement.CimOperationTimeout, 60 seconds when unset.
    private static TimeSpan GetCimOperationTimeout()
    {
        TimeSpan fallback = TimeSpan.FromSeconds(60);
        if (!ConfigurationHost.Configurations.TryGetValue("computermanagement.cimoperationtimeout", out Config? config) || config?.Value is null)
        {
            return fallback;
        }
        if (config.Value is TimeSpan span)
        {
            return span;
        }
        try
        {
            return TimeSpan.Parse(Convert.ToString(config.Value, CultureInfo.InvariantCulture) ?? string.Empty, CultureInfo.InvariantCulture);
        }
        catch (FormatException)
        {
            // A malformed configuration value falls back to the default, as CimService does.
            return fallback;
        }
        catch (OverflowException)
        {
            // A malformed configuration value falls back to the default, as CimService does.
            return fallback;
        }
    }

    private static bool RegistryKeyExists(CimSession? registry, string subKey)
    {
        if (registry is null)
        {
            using RegistryKey? key = OpenLocalKey(subKey);
            return key is not null;
        }
        using CimMethodResult output = InvokeStdRegProv(registry, "EnumValues", subKey, null);
        return ReturnValue(output) == 0;
    }

    private static bool RegistryValueExists(CimSession? registry, string subKey, string valueName)
    {
        return FindValueType(registry, subKey, valueName) is not null;
    }

    // Get-ItemProperty -Name returns the value's data (REG_EXPAND_SZ expanded) when it exists.
    private static object? ReadRegistryValue(CimSession? registry, string subKey, string valueName)
    {
        if (registry is null)
        {
            using RegistryKey? key = OpenLocalKey(subKey);
            return key?.GetValue(valueName);
        }

        int? type = FindValueType(registry, subKey, valueName);
        if (type is null)
        {
            return null;
        }
        string method;
        string member;
        switch (type.Value)
        {
            case 1: method = "GetStringValue"; member = "sValue"; break;
            case 2: method = "GetExpandedStringValue"; member = "sValue"; break;
            case 3: method = "GetBinaryValue"; member = "uValue"; break;
            case 4: method = "GetDWORDValue"; member = "uValue"; break;
            case 7: method = "GetMultiStringValue"; member = "sValue"; break;
            case 11: method = "GetQWORDValue"; member = "uValue"; break;
            default: return null;
        }
        using CimMethodResult output = InvokeStdRegProv(registry, method, subKey, valueName);
        return ReturnValue(output) == 0 ? OutValue(output, member) : null;
    }

    // The registry type of a named value, or null when the key or the value does not exist.
    private static int? FindValueType(CimSession? registry, string subKey, string valueName)
    {
        if (registry is null)
        {
            using RegistryKey? key = OpenLocalKey(subKey);
            if (key is null)
            {
                return null;
            }
            foreach (string name in key.GetValueNames())
            {
                if (string.Equals(name, valueName, StringComparison.OrdinalIgnoreCase))
                {
                    return (int)key.GetValueKind(name);
                }
            }
            return null;
        }

        using CimMethodResult output = InvokeStdRegProv(registry, "EnumValues", subKey, null);
        if (ReturnValue(output) != 0 || OutValue(output, "sNames") is not string[] names)
        {
            return null;
        }
        int[]? types = OutValue(output, "Types") as int[];
        for (int index = 0; index < names.Length; index++)
        {
            if (string.Equals(names[index], valueName, StringComparison.OrdinalIgnoreCase))
            {
                return types is not null && index < types.Length ? types[index] : 0;
            }
        }
        return null;
    }

    private static RegistryKey? OpenLocalKey(string subKey)
    {
        try
        {
            using RegistryKey root = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Default);
            return root.OpenSubKey(subKey, false);
        }
        catch (System.Security.SecurityException)
        {
            // Get-ItemProperty -ErrorAction SilentlyContinue: an unreadable key is not found.
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            // Get-ItemProperty -ErrorAction SilentlyContinue: an unreadable key is not found.
            return null;
        }
    }

    // StdRegProv (root\default) is method-only: its methods are static, invoked on the class.
    private static CimMethodResult InvokeStdRegProv(CimSession registry, string method, string subKey, string? valueName)
    {
        using CimMethodParametersCollection input = new CimMethodParametersCollection();
        input.Add(CimMethodParameter.Create("hDefKey", HkeyLocalMachine, CimType.UInt32, CimFlags.In));
        input.Add(CimMethodParameter.Create("sSubKeyName", subKey, CimType.String, CimFlags.In));
        if (valueName is not null)
        {
            input.Add(CimMethodParameter.Create("sValueName", valueName, CimType.String, CimFlags.In));
        }
        return registry.InvokeMethod(@"root\default", "StdRegProv", method, input);
    }

    private static object? OutValue(CimMethodResult output, string name)
    {
        foreach (CimMethodParameter parameter in output.OutParameters)
        {
            if (string.Equals(parameter.Name, name, StringComparison.OrdinalIgnoreCase))
            {
                return parameter.Value;
            }
        }
        return null;
    }

    private static uint ReturnValue(CimMethodResult output)
    {
        object? value = output.ReturnValue?.Value;
        return value is null ? uint.MaxValue : Convert.ToUInt32(value, CultureInfo.InvariantCulture);
    }

    #endregion

    // PS member enumeration over the Win32_Processor result: null input -> null, one
    // instance -> the scalar property value, several -> object[] of the values.
    private static object? EnumerateMember(List<PSObject> instances, string name)
    {
        if (instances.Count == 0)
        {
            return null;
        }
        if (instances.Count == 1)
        {
            return GetRawValue(instances[0], name);
        }
        List<object?> values = new();
        foreach (PSObject instance in instances)
        {
            values.Add(GetRawValue(instance, name));
        }
        return values.ToArray();
    }

    private static object? GetRawValue(PSObject? instance, string name)
    {
        return instance?.Properties[name]?.Value;
    }

    private static long ToLongOrZero(object? value)
    {
        if (value is null)
        {
            return 0;
        }
        try
        {
            return Convert.ToInt64(value, CultureInfo.InvariantCulture);
        }
        catch (Exception ex) when (ex is FormatException || ex is InvalidCastException || ex is OverflowException)
        {
            // PS -gt on a non-numeric operand: treat as 0, like the original port.
            return 0;
        }
    }

    private static DbaInstanceParameter[]? DefaultComputerName()
    {
        string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(machine))
        {
            return null;
        }
        return new[] { new DbaInstanceParameter(machine) };
    }
}
