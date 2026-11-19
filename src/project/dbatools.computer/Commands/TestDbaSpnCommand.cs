#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests whether the SPNs a SQL Server deployment requires are registered in Active Directory.
/// Port of public/Test-DbaSpn.ps1; surface pinned by migration/baselines/Test-DbaSpn.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaSpn")]
[OutputType(typeof(PSObject))]
public sealed class TestDbaSpnCommand : DbaBaseCmdlet
{
    /// <summary>The computer(s) hosting SQL Server instances to inspect.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; }

    /// <summary>Credential with rights on the domain and the target computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // PS begin block: spare the cmdlet to search for the same account over and over. The @{}
    // literal is a case-insensitive Hashtable shared across all pipeline records; its key comparer
    // is EDITION-DEPENDENT (net472 current-culture, net8.0 ordinal - the W5-030 empirical fact).
    private readonly Hashtable _resultCache = new(NewCacheComparer());

    private static System.Collections.IEqualityComparer NewCacheComparer() =>
#if NET8_0_OR_GREATER
        StringComparer.OrdinalIgnoreCase;
#else
        StringComparer.CurrentCultureIgnoreCase;
#endif

    // PS: $result is FUNCTION-scope - a failed AD lookup leaves the value from ANY previous
    // iteration (even a previous computer) in place, and the stale object is then inspected for
    // the current spn (quirk preserved; a per-computer local only spanned one computer). Holds
    // the pipeline-SHAPED value like the PS variable (a not-found lookup emits an explicit $null,
    // which PS collapses to scalar null with Count 0).
    private object? _adLookupResult;

    // The SQL WMI scriptblock, verbatim from the PS source. Invoke-ManagedComputerCommand
    // re-creates it from TEXT (unbound) and prepends its own $wmi setup, so passing the text
    // through the private function preserves every scoping detail.
    private const string SpnScript = @"
                $spns = @()
                $servereName = $args[0]
                $hostEntry = $args[1]
                $instanceName = $args[2]
                $instanceCount = $wmi.ServerInstances.Count

                <# DO NOT use Write-Message as this is inside of a script block #>
                Write-Verbose ""Found $instanceCount instances""

                foreach ($instance in $wmi.ServerInstances) {
                    $spn = [PSCustomObject] @{
                        ComputerName           = $servereName
                        InstanceName           = $instanceName
                        #SKUNAME
                        SqlProduct             = $null
                        InstanceServiceAccount = $null
                        RequiredSPN            = $null
                        IsSet                  = $false
                        Cluster                = $false
                        TcpEnabled             = $false
                        Port                   = $null
                        DynamicPort            = $false
                        Warning                = ""None""
                        Error                  = ""None""
                        # for piping
                        Credential             = $Credential
                    }

                    $spn.InstanceName = $instance.Name
                    $instanceName = $spn.InstanceName

                    <# DO NOT use Write-Message as this is inside of a script block #>
                    Write-Verbose ""Parsing $instanceName""

                    $services = $wmi.Services | Where-Object { $_.DisplayName -eq ""SQL Server ($instanceName)"" }
                    $spn.InstanceServiceAccount = $services.ServiceAccount
                    $spn.Cluster = ($services.advancedproperties | Where-Object { $_.Name -eq 'Clustered' }).Value

                    if ($spn.Cluster) {
                        $hostEntry = ($services.advancedproperties | Where-Object { $_.Name -eq 'VSNAME' }).Value.ToLowerInvariant()
                        <# DO NOT use Write-Message as this is inside of a script block #>
                        Write-Verbose ""Found cluster $hostEntry""
                        $hostEntry = ([System.Net.Dns]::GetHostEntry($hostEntry)).HostName
                        $spn.ComputerName = $hostEntry
                    }

                    $rawVersion = [version]($services.AdvancedProperties | Where-Object { $_.Name -eq 'VERSION' }).Value

                    $version = $rawVersion
                    $skuName = ($services.AdvancedProperties | Where-Object { $_.Name -eq 'SKUNAME' }).Value

                    $spn.SqlProduct = ""$version $skuName""

                    #is tcp enabled on this instance? If not, we don't need an spn, son
                    if ((($instance.ServerProtocols | Where-Object { $_.Displayname -eq ""TCP/IP"" }).ProtocolProperties | Where-Object { $_.Name -eq ""Enabled"" }).Value -eq $true) {
                        <# DO NOT use Write-Message as this is inside of a script block #>
                        Write-Verbose ""TCP is enabled, gathering SPN requirements""
                        $spn.TcpEnabled = $true
                        #Each instance has a default SPN of MSSQLSvc\<fqdn> or MSSSQLSvc\<fqdn>:Instance
                        if ($instance.Name -eq ""MSSQLSERVER"") {
                            $spn.RequiredSPN = ""MSSQLSvc/$hostEntry""
                        } else {
                            $spn.RequiredSPN = ""MSSQLSvc/"" + $hostEntry + "":"" + $instance.Name
                        }
                    }

                    $spns += $spn
                }
                # Now, for each spn, do we need a port set? Only if TCP is enabled and NOT DYNAMIC!
                foreach ($spn in $spns) {
                    $ports = @()

                    if (-not $spn.TcpEnabled) {
                        continue
                    }

                    $ips = (($wmi.ServerInstances | Where-Object { $_.Name -eq $spn.InstanceName }).ServerProtocols | Where-Object { $_.DisplayName -eq ""TCP/IP"" -and $_.IsEnabled -eq ""True"" }).IpAddresses
                    $ipAllPort = $null
                    foreach ($ip in $ips) {
                        if ($ip.Name -eq ""IPAll"") {
                            $ipAllPort = ($ip.IPAddressProperties | Where-Object { $_.Name -eq ""TCPPort"" }).Value
                            if (($ip.IpAddressProperties | Where-Object { $_.Name -eq ""TcpDynamicPorts"" }).Value -ne """") {
                                $ipAllPort = ($ip.IPAddressProperties | Where-Object { $_.Name -eq ""TcpDynamicPorts"" }).Value + ""d""
                            }
                        } else {
                            $enabled = ($ip.IPAddressProperties | Where-Object { $_.Name -eq ""Enabled"" }).Value
                            $active = ($ip.IPAddressProperties | Where-Object { $_.Name -eq ""Active"" }).Value
                            $tcpDynamicPorts = ($ip.IPAddressProperties | Where-Object { $_.Name -eq ""TcpDynamicPorts"" }).Value
                            if ($enabled -and $active -and $tcpDynamicPorts -eq """") {
                                $ports += ($ip.IPAddressProperties | Where-Object { $_.Name -eq ""TCPPort"" }).Value
                            } elseif ($enabled -and $active -and $tcpDynamicPorts -ne """") {
                                $ports += $ipAllPort + ""d""
                            }
                        }
                    }
                    if ($ipAllPort -ne """") {
                        #IPAll overrides any set ports. Not sure why that's the way it is?
                        $ports = $ipAllPort
                    }

                    $ports = $ports.Split(',') | Select-Object -Unique
                    foreach ($port in $ports) {
                        $newspn = $spn.PSObject.Copy()
                        if ($port -like ""*d"") {
                            $newspn.Port = ($port.replace(""d"", """"))
                            $newspn.RequiredSPN = $newspn.RequiredSPN.Replace("":"" + $newSPN.InstanceName, "":"" + $newspn.Port)
                            $newspn.DynamicPort = $true
                            $newspn.Warning = ""Dynamic port is enabled""
                        } else {
                            #If this is a named instance, replace the instance name with a port number (for non-dynamic ported named instances)
                            $newspn.Port = $port
                            $newspn.DynamicPort = $false

                            if ($newspn.InstanceName -eq ""MSSQLSERVER"") {
                                $newspn.RequiredSPN = $newspn.RequiredSPN + "":"" + $port
                            } else {
                                $newspn.RequiredSPN = $newspn.RequiredSPN.Replace("":"" + $newSPN.InstanceName, "":"" + $newspn.Port)
                            }
                        }
                        $spns += $newspn
                    }
                }
                $spns";

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
            if (computer is null)
            {
                continue;
            }
            string computerText = computer.ToString();

            // PS: try { Resolve-DbaNetworkName ... -ErrorAction Stop } catch { Resolve ... -Turbo }
            // (the Turbo fallback drops the credential, like the source).
            NetworkResolutionService.NetworkResolutionResult? resolved;
            try
            {
                resolved = NetworkResolutionService.Resolve(this, new DbaInstanceParameter(computer.ComputerName), Credential, turbo: false);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch
            {
                resolved = null;
            }
            if (resolved is null)
            {
                resolved = NetworkResolutionService.Resolve(this, new DbaInstanceParameter(computer.ComputerName), null, turbo: true);
            }

            if (resolved?.IPAddress is null)
            {
                WriteMessage(MessageLevel.Warning, "Cannot resolve IP address, moving on.");
                continue;
            }

            string hostEntry = resolved.FullComputerName;
            WriteMessage(MessageLevel.Verbose, $"Resolved ComputerName to FQDN: {hostEntry}");

            // PS: Invoke-ManagedComputerCommand -ComputerName $hostEntry -ScriptBlock $Scriptblock
            //     -ArgumentList $resolved.FullComputerName, $hostEntry, $computer.InstanceName
            //     -Credential $Credential -ErrorAction Stop - the PRIVATE function runs in the
            //     dbatools module scope (script-module instance per the W5-017 duplicate rule).
            Collection<PSObject> spns;
            try
            {
                Hashtable payload = new Hashtable
                {
                    { "ComputerName", hostEntry },
                    { "ScriptText", SpnScript },
                    { "ArgumentList", new object?[] { resolved.FullComputerName, hostEntry, computer.InstanceName } },
                    { "Credential", Credential }
                };
                NestedCommand.RequireDbatoolsScriptModule(this);
                spns = InvokeModuleScoped(
                    "param($__p) " +
                    "$__module = Get-Module dbatools | Where-Object ModuleType -eq \"Script\" | Select-Object -First 1; " +
                    "& $__module { param($p) Invoke-ManagedComputerCommand -ComputerName $p.ComputerName -ScriptBlock ([ScriptBlock]::Create($p.ScriptText)) -ArgumentList $p.ArgumentList -Credential $p.Credential -ErrorAction Stop } $__p 3>&1",
                    payload);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException rex)
            {
                StopFunction($"Couldn't connect to {computerText}", errorRecord: rex.ErrorRecord, continueLoop: true);
                continue;
            }
            catch (Exception ex)
            {
                StopFunction($"Couldn't connect to {computerText}", exception: ex, continueLoop: true);
                continue;
            }

            foreach (PSObject spn in spns)
            {
                if (spn is null)
                {
                    continue;
                }

                string searchfor = "User";
                string account = LanguagePrimitives.ConvertTo<string>(spn.Properties["InstanceServiceAccount"]?.Value) ?? string.Empty;
                if (string.Equals(account, "LocalSystem", StringComparison.OrdinalIgnoreCase)
                    || account.StartsWith("NT SERVICE\\", StringComparison.OrdinalIgnoreCase))
                {
                    WriteMessage(MessageLevel.Verbose, "Virtual account detected, changing target registration to computername");
                    account = $"{resolved.Domain}\\{resolved.ComputerName}$";
                    SetNoteValue(spn, "InstanceServiceAccount", account);
                    searchfor = "Computer";
                }
                else if (account.EndsWith("$", StringComparison.Ordinal) && account.Contains("\\"))
                {
                    WriteMessage(MessageLevel.Verbose, "Managed Service Account detected");
                    searchfor = "Computer";
                }

                string serviceAccount = account;
                // PS: if ($spn.InstanceServiceAccount -notin $resultCache.Keys)
                if (!_resultCache.ContainsKey(account))
                {
                    WriteMessage(MessageLevel.Verbose, $"Searching for {serviceAccount}");
                    try
                    {
                        Hashtable adPayload = new Hashtable
                        {
                            { "ADObject", serviceAccount },
                            { "Type", searchfor },
                            { "Credential", Credential }
                        };
                        NestedCommand.RequireDbatoolsScriptModule(this);
                        _adLookupResult = ShapeForScript(InvokeModuleScoped(
                            "param($__p) " +
                            "$__module = Get-Module dbatools | Where-Object ModuleType -eq \"Script\" | Select-Object -First 1; " +
                            "& $__module { param($p) Get-DbaADObject -ADObject $p.ADObject -Type $p.Type -Credential $p.Credential -EnableException } $__p 3>&1",
                            adPayload));
                        _resultCache[account] = _adLookupResult;
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch
                    {
                        if (!string.IsNullOrEmpty(account))
                        {
                            WriteMessage(MessageLevel.Warning, $"AD lookup failure. This may be because the domain cannot be resolved for the SQL Server service account ({serviceAccount}).");
                        }
                    }
                }
                else
                {
                    _adLookupResult = _resultCache[account];
                }

                if (PsCount(_adLookupResult) > 0)
                {
                    bool isSet;
                    try
                    {
                        // PS: $results = $result.GetUnderlyingObject();
                        //     $results.Properties.servicePrincipalName -contains $spn.RequiredSPN
                        // - run the exact PS expression so the DirectoryEntry adapter semantics
                        // (case-insensitive -contains over the property value collection) hold.
                        Collection<PSObject> check = InvokeCommand.InvokeScript(
                            false,
                            ScriptBlock.Create("param($__r, $__spn) $__results = $__r.GetUnderlyingObject(); $__results.Properties.servicePrincipalName -contains $__spn"),
                            null,
                            _adLookupResult, spn.Properties["RequiredSPN"]?.Value);
                        isSet = check.Count > 0 && LanguagePrimitives.IsTrue(check[0]);
                    }
                    catch (PipelineStoppedException)
                    {
                        throw;
                    }
                    catch
                    {
                        WriteMessage(MessageLevel.Warning, $"The SQL Service account ({serviceAccount}) has been found, but you don't have enough permission to inspect its SPNs");
                        continue;
                    }
                    if (isSet)
                    {
                        SetNoteValue(spn, "IsSet", true);
                    }
                }
                else
                {
                    WriteMessage(MessageLevel.Warning, "SQL Service account not found. Results may not be accurate.");
                    WriteObject(spn);
                    continue;
                }

                bool isSetNow = LanguagePrimitives.IsTrue(spn.Properties["IsSet"]?.Value);
                bool tcpEnabled = LanguagePrimitives.IsTrue(spn.Properties["TcpEnabled"]?.Value);
                if (!isSetNow && tcpEnabled)
                {
                    SetNoteValue(spn, "Error", "SPN missing");
                }

                // PS: $spn | Select-DefaultView -ExcludeProperty Credential, DomainName - the
                // display set comes from Get-Member output = ALPHABETICAL, minus the excluded.
                List<string> displayNames = new();
                foreach (PSPropertyInfo property in spn.Properties)
                {
                    if (!string.Equals(property.Name, "Credential", StringComparison.OrdinalIgnoreCase)
                        && !string.Equals(property.Name, "DomainName", StringComparison.OrdinalIgnoreCase))
                    {
                        displayNames.Add(property.Name);
                    }
                }
                displayNames.Sort(StringComparer.OrdinalIgnoreCase);
                OutputHelper.SetDefaultDisplayPropertySet(spn, displayNames.ToArray());
                WriteObject(spn);
            }
        }
    }

    // NestedCommand discipline for module-scoped private-function calls: PSDPV shield plus 3>&1
    // warning re-emit through this cmdlet's stream.

    // PS .Count on a pipeline-shaped value: null (a not-found lookup EMITS an explicit $null,
    // which PS collapses to a scalar null whose Count is 0) -> 0, array -> length, scalar -> 1.
    private static int PsCount(object? value)
    {
        if (value is null)
        {
            return 0;
        }
        object unwrapped = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (unwrapped is object?[] many)
        {
            return many.Length;
        }
        return 1;
    }

    private Collection<PSObject> InvokeModuleScoped(string scriptText, object payload)
    {
        object? effective = SessionState.PSVariable.GetValue("PSDefaultParameterValues");
        // Module-internal calls resolve $PSDefaultParameterValues from the MODULE session state,
        // where none is defined - neither caller-LOCAL nor GLOBAL defaults ever reached the retired
        // functions' nested calls, so the faithful shield is an EMPTY table, not the global one.
        bool swapped = effective is not null;
        if (swapped)
        {
            SessionState.PSVariable.Set("PSDefaultParameterValues", new System.Management.Automation.DefaultParameterDictionary());
        }
        try
        {
            ScriptBlock script = ScriptBlock.Create(scriptText);
            Collection<PSObject> raw = InvokeCommand.InvokeScript(false, script, null, payload);
            Collection<PSObject> output = new();
            foreach (PSObject item in raw)
            {
                if (item?.BaseObject is WarningRecord warning)
                {
                    WriteWarning(warning.Message);
                }
                else
                {
                    output.Add(item!);
                }
            }
            return output;
        }
        finally
        {
            if (swapped)
            {
                SessionState.PSVariable.Set("PSDefaultParameterValues", effective);
            }
        }
    }

    // PS pipeline-assignment shape for feeding $result back into script expressions.
    private static object? ShapeForScript(Collection<PSObject> items)
    {
        if (items.Count == 0)
        {
            return null;
        }
        if (items.Count == 1)
        {
            return items[0];
        }
        List<PSObject> many = new(items);
        return many.ToArray();
    }

    private static void SetNoteValue(PSObject target, string name, object? value)
    {
        PSPropertyInfo? property = target.Properties[name];
        if (property is not null)
        {
            property.Value = value;
        }
        else
        {
            target.Properties.Add(new PSNoteProperty(name, value));
        }
    }
}
