#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Gathers operating system information from SQL Server hosts.
/// Port of public/Get-DbaOperatingSystem.ps1; surface pinned by migration/baselines/Get-DbaOperatingSystem.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaOperatingSystem")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaOperatingSystemCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server host computer(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [Alias("cn", "host", "Server")]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Alternate credential for the CIM/WMI and remoting probes.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

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

        foreach (DbaInstanceParameter computer in ComputerName)
        {
            WriteMessage(MessageLevel.Verbose, $"Connecting to {computer}");

            // PS: $server = Resolve-DbaNetworkName -ComputerName $computer.ComputerName -Credential $Credential
            // (no EnableException forwarding: a DNS failure is that function's own
            // "DNS name ... not found" warning followed by this command's skip warning).
            NetworkResolutionService.NetworkResolutionResult? resolution = null;
            string dnsProbeName = computer.IsLocalHost ? Environment.MachineName : computer.ComputerName;
            try
            {
                resolution = NetworkResolutionService.Resolve(this, new DbaInstanceParameter(computer.ComputerName), Credential, turbo: false);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                WriteMessage(MessageLevel.Warning, $"DNS name {dnsProbeName} not found", exception: ex);
            }
            if (resolution is null)
            {
                WriteMessage(MessageLevel.Warning, $"DNS name {dnsProbeName} not found");
            }

            string? computerResolved = resolution?.FullComputerName;
            WriteMessage(MessageLevel.Verbose, $"Resolved {computerResolved}");

            if (string.IsNullOrEmpty(computerResolved))
            {
                WriteMessage(MessageLevel.Warning, $"Unable to resolve hostname of {computer}. Skipping.");
                continue;
            }

            // PS: $TestWS = Test-WSMan -ComputerName $computerResolved -ErrorAction SilentlyContinue
            bool remotingAvailable = false;
            try
            {
                using PowerShell shell = PowerShell.Create(RunspaceMode.CurrentRunspace);
                shell.AddCommand("Test-WSMan")
                    .AddParameter("ComputerName", computerResolved)
                    .AddParameter("ErrorAction", "SilentlyContinue");
                remotingAvailable = shell.Invoke().Count > 0;
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch
            {
                // typo preserved from the PS source
                WriteMessage(MessageLevel.Warning, $"Remoting not availablle on {computer}. Skipping checks");
                remotingAvailable = false;
            }

            string powerShellVersion;
            if (remotingAvailable)
            {
                try
                {
                    RemoteExecutionService.RemoteCommandRequest versionRequest = new()
                    {
                        ComputerName = new DbaInstanceParameter(computerResolved!),
                        Credential = Credential,
                        ScriptText = "$PSVersionTable.PSVersion"
                    };
                    RemoteExecutionService.RemoteCommandResult versionResult = RemoteExecutionService.InvokeCommand(this, versionRequest);
                    PSObject? version = versionResult.Output.Count > 0 ? versionResult.Output[0] : null;
                    // PS: "$($psVersion.Major).$($psVersion.Minor)" - absent members render empty.
                    powerShellVersion = $"{GetPropertyValue(version, "Major")}.{GetPropertyValue(version, "Minor")}";
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch
                {
                    WriteMessage(MessageLevel.Warning, $"PowerShell Version information not available on {computer}.");
                    powerShellVersion = "Unavailable";
                }
            }
            else
            {
                powerShellVersion = "Unknown";
            }

            PSObject? os;
            try
            {
                os = QuerySingle(computerResolved!, "Win32_OperatingSystem", null, out List<ErrorRecord> osErrors);
                ForwardErrors(osErrors);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                // PS: Stop-Function (no -Continue) followed by return - the next pipeline
                // record still processes, so Interrupted must stay unset here.
                StopFunction($"Failure collecting OS information on {computer}", target: computer, errorRecord: new ErrorRecord(ex, "dbatools_Get-DbaOperatingSystem", ErrorCategory.NotSpecified, computer), continueLoop: true);
                return;
            }

            PSObject? timeZone;
            try
            {
                timeZone = QuerySingle(computerResolved!, "Win32_TimeZone", null, out List<ErrorRecord> tzErrors);
                ForwardErrors(tzErrors);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failure collecting TimeZone information on {computer}", target: computer, errorRecord: new ErrorRecord(ex, "dbatools_Get-DbaOperatingSystem", ErrorCategory.NotSpecified, computer), continueLoop: true);
                return;
            }

            string activePowerPlan;
            try
            {
                CimService.CmObjectResult planResult = Query(computerResolved!, "Win32_PowerPlan", @"root\cimv2\power");
                ForwardErrors(planResult.PassthroughErrors);
                if (planResult.Instances.Count == 0)
                {
                    // PS: $powerPlan stays empty, the if falls through to 'Not Avaliable'
                    activePowerPlan = "Not Avaliable";
                }
                else
                {
                    List<string> activeNames = new();
                    foreach (PSObject plan in planResult.Instances)
                    {
                        object? isActive = plan.Properties["IsActive"]?.Value;
                        if (isActive is not null && LanguagePrimitives.IsTrue(isActive))
                        {
                            activeNames.Add(GetPropertyValue(plan, "ElementName"));
                        }
                    }
                    activePowerPlan = string.Join(",", activeNames);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch
            {
                WriteMessage(MessageLevel.Warning, $"Power plan information not available on {computer}.");
                // typo preserved from the PS source
                activePowerPlan = "Not Avaliable";
            }

            CultureInfo? language = GetLanguage(os);

            object? isWsfc;
            try
            {
                CimService.CmObjectResult servicesResult = Query(computerResolved!, "Win32_SystemServices", null);
                ForwardErrors(servicesResult.PassthroughErrors);
                bool foundCluster = false;
                foreach (PSObject service in servicesResult.Instances)
                {
                    // PS: Select-Object PartComponent | Where-Object { $_ -like "*ClusSvc*" }
                    // - the wrapper stringifies to @{PartComponent=...}, so the match is on
                    // the PartComponent text containing ClusSvc.
                    string? part = service.Properties["PartComponent"]?.Value?.ToString();
                    if (part is not null && part.IndexOf("ClusSvc", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        foundCluster = true;
                        break;
                    }
                }
                isWsfc = foundCluster;
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch
            {
                WriteMessage(MessageLevel.Warning, $"Unable to determine Cluster State of {computer}.");
                isWsfc = null;
            }

            object? installDate;
            object? lastBootTime;
            object? localDateTime;
            try
            {
                // PS: [DbaDateTime] casts succeed when the CIM rungs delivered DateTime values.
                installDate = ToDbaDateTime(os, "InstallDate");
                lastBootTime = ToDbaDateTime(os, "LastBootUpTime");
                localDateTime = ToDbaDateTime(os, "LocalDateTime");
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch
            {
                // PS fallback: [dbadate]($os.ConverttoDateTime(...)) - the Wmi-rung DMTF shape.
                installDate = ToDbaDateFromDmtf(os, "InstallDate");
                lastBootTime = ToDbaDateFromDmtf(os, "LastBootUpTime");
                localDateTime = ToDbaDateFromDmtf(os, "LocalDateTime");
            }

            PSObject output = new();
            output.Properties.Add(new PSNoteProperty("ComputerName", computerResolved));
            output.Properties.Add(new PSNoteProperty("Manufacturer", GetRawValue(os, "Manufacturer")));
            output.Properties.Add(new PSNoteProperty("Organization", GetRawValue(os, "Organization")));
            output.Properties.Add(new PSNoteProperty("Architecture", GetRawValue(os, "OSArchitecture")));
            output.Properties.Add(new PSNoteProperty("Version", GetRawValue(os, "Version")));
            output.Properties.Add(new PSNoteProperty("Build", GetRawValue(os, "BuildNumber")));
            output.Properties.Add(new PSNoteProperty("OSVersion", GetRawValue(os, "Caption")));
            output.Properties.Add(new PSNoteProperty("SPVersion", GetRawValue(os, "ServicePackMajorVersion")));
            output.Properties.Add(new PSNoteProperty("InstallDate", installDate));
            output.Properties.Add(new PSNoteProperty("LastBootTime", lastBootTime));
            output.Properties.Add(new PSNoteProperty("LocalDateTime", localDateTime));
            output.Properties.Add(new PSNoteProperty("PowerShellVersion", powerShellVersion));
            output.Properties.Add(new PSNoteProperty("TimeZone", GetRawValue(timeZone, "Caption")));
            output.Properties.Add(new PSNoteProperty("TimeZoneStandard", GetRawValue(timeZone, "StandardName")));
            output.Properties.Add(new PSNoteProperty("TimeZoneDaylight", GetRawValue(timeZone, "DaylightName")));
            output.Properties.Add(new PSNoteProperty("BootDevice", GetRawValue(os, "BootDevice")));
            output.Properties.Add(new PSNoteProperty("SystemDevice", GetRawValue(os, "SystemDevice")));
            output.Properties.Add(new PSNoteProperty("SystemDrive", GetRawValue(os, "SystemDrive")));
            output.Properties.Add(new PSNoteProperty("WindowsDirectory", GetRawValue(os, "WindowsDirectory")));
            output.Properties.Add(new PSNoteProperty("PagingFileSize", GetRawValue(os, "SizeStoredInPagingFiles")));
            output.Properties.Add(new PSNoteProperty("TotalVisibleMemory", ToSizeKilobytes(os, "TotalVisibleMemorySize")));
            output.Properties.Add(new PSNoteProperty("FreePhysicalMemory", ToSizeKilobytes(os, "FreePhysicalMemory")));
            output.Properties.Add(new PSNoteProperty("TotalVirtualMemory", ToSizeKilobytes(os, "TotalVirtualMemorySize")));
            output.Properties.Add(new PSNoteProperty("FreeVirtualMemory", ToSizeKilobytes(os, "FreeVirtualMemory")));
            output.Properties.Add(new PSNoteProperty("ActivePowerPlan", activePowerPlan));
            output.Properties.Add(new PSNoteProperty("Status", GetRawValue(os, "Status")));
            output.Properties.Add(new PSNoteProperty("Language", language?.Name));
            output.Properties.Add(new PSNoteProperty("LanguageId", language?.LCID));
            output.Properties.Add(new PSNoteProperty("LanguageKeyboardLayoutId", language?.KeyboardLayoutId));
            output.Properties.Add(new PSNoteProperty("LanguageTwoLetter", language?.TwoLetterISOLanguageName));
            output.Properties.Add(new PSNoteProperty("LanguageThreeLetter", language?.ThreeLetterISOLanguageName));
            output.Properties.Add(new PSNoteProperty("LanguageAlias", language?.DisplayName));
            output.Properties.Add(new PSNoteProperty("LanguageNative", language?.NativeName));
            output.Properties.Add(new PSNoteProperty("CodeSet", GetRawValue(os, "CodeSet")));
            output.Properties.Add(new PSNoteProperty("CountryCode", GetRawValue(os, "CountryCode")));
            output.Properties.Add(new PSNoteProperty("Locale", GetRawValue(os, "Locale")));
            output.Properties.Add(new PSNoteProperty("IsWsfc", isWsfc));
            OutputHelper.SetDefaultDisplayPropertySet(output,
                "ComputerName", "Manufacturer", "Organization", "Architecture", "Version",
                "OSVersion", "LastBootTime", "LocalDateTime", "PowerShellVersion", "TimeZone",
                "TotalVisibleMemory", "ActivePowerPlan", "LanguageNative");
            WriteObject(output);
        }
    }

    private CimService.CmObjectResult Query(string computerResolved, string className, string? cimNamespace)
    {
        // PS: $splatDbaCmObject = @{ ComputerName; EnableException = $true } (+ Credential
        // when bound); EnableException means chain failures THROW into the caller's catch.
        // The PS binder converts the resolved name through DbaCmConnectionParameter, which
        // keeps only the host part - mirror that so bypass-shaped names still bind.
        CimService.CmObjectRequest request = new()
        {
            ComputerName = new DbaInstanceParameter(computerResolved).ComputerName,
            ClassName = className,
            Namespace = cimNamespace
        };
        if (TestBound(nameof(Credential)))
        {
            request.Credential = Credential;
        }
        return CimService.GetCmObject(this, request);
    }

    private PSObject? QuerySingle(string computerResolved, string className, string? cimNamespace, out List<ErrorRecord> errors)
    {
        CimService.CmObjectResult result = Query(computerResolved, className, cimNamespace);
        errors = result.PassthroughErrors;
        return result.Instances.Count > 0 ? result.Instances[0] : null;
    }

    private void ForwardErrors(List<ErrorRecord> errors)
    {
        foreach (ErrorRecord error in errors)
        {
            WriteError(NestedCommand.PreserveErrorIdentity(error));
        }
    }

    private CultureInfo? GetLanguage(PSObject? os)
    {
        // PS: Get-Language $os.OSLanguage - a bare CultureInfo.GetCultureInfo over the OS LCID
        // with no try/catch, and its call sits outside the caller's try. So an absent OSLanguage
        // ([int]$null binds to 0) or an unmapped LCID throws a statement-terminating error and
        // the record fails loudly rather than emitting empty Language fields. Match that: no
        // early null return and no catch. Convert.ToInt32(null) yields 0 exactly as the [int]
        // parameter binder does, so the null and unmapped cases both reach the throw as in PS.
        object? rawLanguage = os?.Properties["OSLanguage"]?.Value;
        return CultureInfo.GetCultureInfo(Convert.ToInt32(rawLanguage, CultureInfo.InvariantCulture));
    }

    private static string GetPropertyValue(PSObject? instance, string name)
    {
        object? value = instance?.Properties[name]?.Value;
        return value?.ToString() ?? string.Empty;
    }

    private static object? GetRawValue(PSObject? instance, string name)
    {
        return instance?.Properties[name]?.Value;
    }

    private static object? ToDbaDateTime(PSObject? instance, string name)
    {
        object? value = instance?.Properties[name]?.Value;
        if (value is null)
        {
            return null;
        }
        if (value is DateTime timestamp)
        {
            return new DbaDateTime(timestamp);
        }
        // non-DateTime values (the Wmi-rung DMTF strings) fail over to the [dbadate] path
        throw new InvalidCastException($"Value of {name} is not a DateTime");
    }

    private static object? ToDbaDateFromDmtf(PSObject? instance, string name)
    {
        object? value = instance?.Properties[name]?.Value;
        if (value is null)
        {
            return null;
        }
        if (value is DateTime timestamp)
        {
            return new DbaDate(timestamp);
        }
        return new DbaDate(CimService.ConvertDmtfToDateTime(value.ToString()!));
    }

    private static object? ToSizeKilobytes(PSObject? instance, string name)
    {
        object? value = instance?.Properties[name]?.Value;
        if (value is null)
        {
            return null;
        }
        try
        {
            return new Size(Convert.ToInt64(value, CultureInfo.InvariantCulture) * 1024);
        }
        catch
        {
            return null;
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
