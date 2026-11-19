#nullable enable
#pragma warning disable CA1416 // Windows-only command: SQL Server patching, WinRM remoting, WMI

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Updates (patches) SQL Server on one or more computers by building an action plan from the
/// Version/Type or KB parameter set and delegating each action to Invoke-DbaAdvancedUpdate. Port
/// of public/Update-DbaInstance.ps1; surface pinned by migration/baselines/Update-DbaInstance.json.
///
/// Every dbatools dependency (discovery, planning, remoting, execution) is invoked through the
/// dbatools MODULE SCOPE so Pester's `-ModuleName dbatools` mocks intercept the calls (the
/// install-family test contract).
/// </summary>
[Cmdlet(VerbsData.Update, "DbaInstance", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "Version")]
public sealed class UpdateDbaInstanceCommand : DbaBaseCmdlet
{
    [Parameter(Position = 1, ValueFromPipeline = true)]
    [Alias("cn", "host", "Server")]
    public DbaInstanceParameter[] ComputerName { get; set; } = new[] { new DbaInstanceParameter(Environment.MachineName) };

    [Parameter]
    public PSCredential? Credential { get; set; }

    [Parameter(ParameterSetName = "Version")]
    [ValidateNotNullOrEmpty]
    public string[]? Version { get; set; }

    [Parameter(ParameterSetName = "Version")]
    [ValidateSet("All", "ServicePack", "CumulativeUpdate")]
    public string[] Type { get; set; } = new[] { "All" };

    [Parameter(Mandatory = true, ParameterSetName = "KB")]
    [ValidateNotNullOrEmpty]
    public string[]? KB { get; set; }

    [Parameter]
    [Alias("Instance")]
    public string? InstanceName { get; set; }

    [Parameter]
    public string[]? Path { get; set; } = DefaultUpdatePath();

    [Parameter]
    public SwitchParameter Restart { get; set; }

    [Parameter]
    public SwitchParameter Continue { get; set; }

    [Parameter]
    [ValidateNotNull]
    public int Throttle { get; set; } = 50;

    [Parameter]
    [PsStringCast]
    [ValidateSet("Default", "Basic", "Negotiate", "NegotiateWithImplicitCredential", "Credssp", "Digest", "Kerberos")]
    public string? Authentication { get; set; }

    [Parameter]
    public SwitchParameter UseSSL { get; set; } = DefaultUseSSL();

    [Parameter]
    public int? Port { get; set; } = DefaultPort();

    [Parameter]
    public string? ExtractPath { get; set; }

    [Parameter]
    public string[]? ArgumentList { get; set; }

    [Parameter]
    public SwitchParameter Download { get; set; }

    [Parameter]
    public SwitchParameter NoPendingRenameCheck { get; set; } = DefaultPendingRename();

    // ---- begin-scoped state ----
    private readonly List<Hashtable> _actions = new();
    private bool _notifiedCredentials;
    private bool _notifiedUnsecure;
    private string _resolvedAuthentication = "Credssp";

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // PS: $Authentication = @('Credssp', 'Default')[$null -eq $Credential] - Credssp when a
        // credential is supplied, Default otherwise. Honour an explicit -Authentication.
        _resolvedAuthentication = TestBound("Authentication") && Authentication is not null
            ? Authentication
            : (Credential is null ? "Default" : "Credssp");

        // ---- parameter validation ----
        if (ParameterSetName == "Version")
        {
            foreach (string v in Version ?? Array.Empty<string>())
            {
                if (!Regex.IsMatch(v, @"^((SQL)?\d{4}(R2)?)?\s*(RTM|SP\d+)?\s*(CU\d+)?$"))
                {
                    StopFunction($"{string.Join(" ", Version ?? Array.Empty<string>())} is an incorrect Version value, please refer to Get-Help Update-DbaInstance -Parameter Version", category: ErrorCategory.InvalidArgument);
                    return;
                }
            }
        }

        List<string> kbList = new();
        if (ParameterSetName == "KB")
        {
            foreach (string kbItem in KB ?? Array.Empty<string>())
            {
                Match m = Regex.Match(kbItem, @"^(KB)?(\d+)$");
                if (m.Success) { kbList.Add(m.Groups[2].Value); }
                else
                {
                    StopFunction($"{kbItem} is an incorrect KB value, please refer to Get-Help Update-DbaInstance -Parameter KB", category: ErrorCategory.InvalidArgument);
                    return;
                }
            }
        }

        // PS: trim trailing slashes and drop whitespace-only entries.
        if (Path is not null)
        {
            Path = Path
                .Where(p => !string.IsNullOrWhiteSpace(p))
                .Select(p => p.TrimEnd('/', '\\'))
                .Where(p => !string.IsNullOrWhiteSpace(p))
                .ToArray();
        }
        if (Path is null || Path.Length == 0)
        {
            StopFunction("Path is required. Please provide a -Path to a folder containing (or to store) SQL Server updates, or configure a default with Set-DbatoolsConfig -Name Path.SQLServerUpdates -Value 'C:\\patches'.", category: ErrorCategory.InvalidArgument);
            return;
        }

        // ---- action-plan template ----
        Hashtable actionTemplate = new();
        if (!string.IsNullOrEmpty(InstanceName)) { actionTemplate["InstanceName"] = InstanceName; }
        if (Continue.IsPresent) { actionTemplate["Continue"] = Continue; }

        if (ParameterSetName == "Version")
        {
            // typeList: 'All' expands to the fixed order ServicePack, CumulativeUpdate; otherwise
            // the supplied types sorted descending ('ServicePack' precedes 'CumulativeUpdate').
            List<string> typeList;
            if (Type.Contains("All")) { typeList = new List<string> { "ServicePack", "CumulativeUpdate" }; }
            else { typeList = Type.OrderByDescending(t => t, StringComparer.OrdinalIgnoreCase).ToList(); }

            if (Version is not null && Version.Length > 0)
            {
                foreach (string ver in Version)
                {
                    Hashtable currentAction = (Hashtable)actionTemplate.Clone();
                    Match m = Regex.Match(ver ?? string.Empty, @"^(SQL)?(\d{4}(R2)?)?\s*(RTM|SP)?(\d+)?(CU)?(\d+)?");
                    if (!string.IsNullOrEmpty(ver) && m.Success)
                    {
                        // PS: $majorV, $spV, $cuV = $Matches[2, 5, 7]
                        string? majorV = GroupOrNull(m, 2);
                        string? spV = GroupOrNull(m, 5);
                        string? cuV = GroupOrNull(m, 7);
                        WriteMessage(MessageLevel.Debug, $"Parsed Version as Major {majorV} SP {spV} CU {cuV}");

                        if (majorV is not null)
                        {
                            currentAction["MajorVersion"] = majorV;
                            // version-only (no SP/CU) → add every requested type
                            if (spV is null && cuV is null)
                            {
                                foreach (string currentType in typeList)
                                {
                                    Hashtable a = (Hashtable)currentAction.Clone();
                                    a["Type"] = currentType;
                                    _actions.Add(a);
                                }
                            }
                        }
                        if (spV is not null)
                        {
                            currentAction["ServicePack"] = spV;
                            if (spV != "0" && typeList.Contains("ServicePack")) { _actions.Add((Hashtable)currentAction.Clone()); }
                        }
                        if (cuV is not null && cuV != "0" && typeList.Contains("CumulativeUpdate"))
                        {
                            Hashtable a = (Hashtable)currentAction.Clone();
                            a["CumulativeUpdate"] = cuV;
                            _actions.Add(a);
                        }
                    }
                    else
                    {
                        StopFunction($"{ver} is an incorrect Version value, please refer to Get-Help Update-DbaInstance -Parameter Version", category: ErrorCategory.InvalidArgument);
                        return;
                    }
                }
            }
            else
            {
                // no -Version: one action per requested type
                foreach (string currentType in typeList)
                {
                    Hashtable a = (Hashtable)actionTemplate.Clone();
                    a["Type"] = currentType;
                    _actions.Add(a);
                }
            }
        }
        else // KB set
        {
            foreach (string kbItem in kbList)
            {
                Hashtable a = (Hashtable)actionTemplate.Clone();
                a["KB"] = kbItem;
                _actions.Add(a);
            }
        }

        foreach (Hashtable a in _actions)
        {
            WriteMessage(MessageLevel.Debug, $"Added installation action {ConvertToJsonCompact(a)}");
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted) { return; }

        // ---- resolve computer names ----
        bool pathIsNetwork = TestNetworkPath(Path);
        List<string> resolvedComputers = new();
        foreach (DbaInstanceParameter computer in ComputerName)
        {
            ScalarInModuleScope("Test-ElevationRequirement", new Hashtable { { "ComputerName", computer }, { "Continue", true } });

            if (!computer.IsLocalHost && !_notifiedCredentials && Credential is null && pathIsNetwork)
            {
                WriteMessage(MessageLevel.Warning, "Explicit -Credential might be required when running against remote hosts and -Path is a network folder");
                _notifiedCredentials = true;
            }
            try
            {
                Hashtable resolveSplat = new() { { "ComputerName", computer.ComputerName }, { "EnableException", true } };
                if (Credential is not null) { resolveSplat["Credential"] = Credential; }
                object? resolved = ScalarInModuleScope("Resolve-DbaNetworkName", resolveSplat);
                if (resolved is not null)
                {
                    string full = PsStr(GetProp(resolved, "FullComputerName"));
                    if (!string.IsNullOrEmpty(full)) { resolvedComputers.Add(full); }
                }
            }
            catch (PipelineStoppedException) { throw; }
            catch
            {
                WriteMessage(MessageLevel.Verbose, $"Could not resolve {computer.ComputerName} via CIM (this may occur with CredSSP or workgroup environments). Using provided name directly.");
                resolvedComputers.Add(computer.ComputerName);
            }
        }
        List<string> uniqueComputers = resolvedComputers.Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(c => c, StringComparer.OrdinalIgnoreCase).ToList();

        List<PSObject> installActions = new();
        List<PSObject> downloads = new();

        foreach (string resolvedName in uniqueComputers)
        {
            // discovery
            object? componentsRaw;
            try
            {
                componentsRaw = CollectionToArray(InvokeInModuleScope("param($__p) & 'Get-SQLInstanceComponent' @__p 3>&1", new Hashtable
                {
                    { "ComputerName", resolvedName }, { "Credential", Credential }, { "Authentication", _resolvedAuthentication }
                }));
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex)
            {
                StopFunction($"Error while looking for SQL Server installations on {resolvedName}", errorRecord: AsRecord(ex), continueLoop: true);
                continue;
            }
            List<object?> components = EnumerateAny(componentsRaw).ToList();
            if (components.Count == 0)
            {
                StopFunction($"No SQL Server installations found on {resolvedName}", continueLoop: true);
                continue;
            }
            if (!string.IsNullOrEmpty(InstanceName))
            {
                components = components.Where(c => string.Equals(PsStr(GetProp(c, "InstanceName")), InstanceName, StringComparison.OrdinalIgnoreCase)).ToList();
            }

            // pending reboot
            object? rebootNeeded;
            try
            {
                rebootNeeded = ScalarInModuleScope("Test-PendingReboot", new Hashtable
                {
                    { "ComputerName", resolvedName }, { "Credential", Credential }, { "Authentication", _resolvedAuthentication }, { "NoPendingRename", NoPendingRenameCheck.ToBool() }
                });
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex)
            {
                StopFunction($"Failed to get reboot status from {resolvedName}", errorRecord: AsRecord(ex), continueLoop: true);
                continue;
            }
            bool isLocal = new DbaInstanceParameter(resolvedName).IsLocalHost;
            if (LanguagePrimitives.IsTrue(rebootNeeded) && (!Restart.IsPresent || isLocal))
            {
                StopFunction($"{resolvedName} is pending a reboot. Reboot the computer before proceeding.", continueLoop: true);
                continue;
            }

            // remote protocol test (only with an explicit credential against a remote host)
            if (Credential is not null && !isLocal)
            {
                if (!TestRemoteConnection(resolvedName)) { continue; }
            }

            // plan the upgrades for this computer
            List<PSObject> upgrades = new();
            bool computerAborted = false;
            foreach (Hashtable actionItem in _actions)
            {
                Hashtable currentAction = (Hashtable)actionItem.Clone();
                List<object?> selectedComponents;
                if (currentAction.ContainsKey("MajorVersion") && currentAction["MajorVersion"] is not null)
                {
                    string mv = PsStr(currentAction["MajorVersion"]);
                    selectedComponents = components.Where(c => NameLevelContains(c, mv)).ToList();
                    currentAction.Remove("MajorVersion");
                    WriteMessage(MessageLevel.Debug, $"Limiting components to version {mv}");
                }
                else { selectedComponents = components; }

                // Get-SqlInstanceUpdate declares `[bool]$EnableException = $EnableException`, i.e. it
                // inherits the caller's ambient $EnableException. The script function supplies that
                // from its own scope; our module-scoped invocation has none, so pass it explicitly.
                Hashtable updateSplat = new(currentAction)
                {
                    { "ComputerName", resolvedName }, { "Credential", Credential }, { "Component", selectedComponents.ToArray() }, { "EnableException", EnableException.ToBool() }
                };
                Collection<PSObject> upgradeDetails = InvokeInModuleScope("param($__p) & 'Get-SqlInstanceUpdate' @__p 3>&1", updateSplat);
                List<object?> details = FlattenObjects(upgradeDetails);
                if (details.Any(d => { object? s = GetProp(d, "Successful"); return s is not null && !LanguagePrimitives.IsTrue(s); }))
                {
                    foreach (object? d in details) { WriteObject(d); }
                    string notes = string.Join(" | ", details.Select(d => PsStr(GetProp(d, "Notes"))));
                    StopFunction($"Update cannot be applied to {resolvedName} | {notes}", continueLoop: true);
                    computerAborted = true;
                    break;
                }

                foreach (object? detail in details)
                {
                    Hashtable kbLookup = new()
                    {
                        { "ComputerName", resolvedName }, { "Credential", Credential }, { "Authentication", _resolvedAuthentication },
                        { "Architecture", GetProp(detail, "Architecture") }, { "MajorVersion", GetProp(detail, "MajorVersion") },
                        { "Path", Path }, { "KB", GetProp(detail, "KB") }
                    };
                    object? installer;
                    try { installer = ScalarInModuleScope("Find-SqlInstanceUpdate", kbLookup); }
                    catch (PipelineStoppedException) { throw; }
                    catch (Exception ex)
                    {
                        StopFunction("Failed to enumerate files in -Path", errorRecord: AsRecord(ex), continueLoop: true);
                        continue;
                    }
                    if (installer is not null)
                    {
                        SetProp(detail, "Installer", PsStr(GetProp(installer, "FullName")));
                    }
                    else if (Download.IsPresent)
                    {
                        PSObject dl = new();
                        dl.Properties.Add(new PSNoteProperty("KB", GetProp(detail, "KB")));
                        dl.Properties.Add(new PSNoteProperty("Architecture", GetProp(detail, "Architecture")));
                        downloads.Add(dl);
                    }
                    else
                    {
                        StopFunction($"Could not find installer for the SQL{PsStr(GetProp(detail, "MajorVersion"))} update KB{PsStr(GetProp(detail, "KB"))}", continueLoop: true);
                        continue;
                    }
                    // mutate components so multi-step chains target the just-applied level
                    object? targetVersion = GetProp(detail, "TargetVersion");
                    string targetNameLevel = PsStr(GetProp(targetVersion, "NameLevel"));
                    foreach (object? component in components)
                    {
                        if (string.Equals(PsStr(GetProp(GetProp(component, "Version"), "NameLevel")), targetNameLevel, StringComparison.OrdinalIgnoreCase))
                        {
                            SetProp(component, "Version", targetVersion);
                        }
                    }
                    if (detail is PSObject dp) { upgrades.Add(dp); } else if (detail is not null) { upgrades.Add(PSObject.AsPSObject(detail)); }
                }
            }
            if (computerAborted) { continue; }

            if (upgrades.Count > 0)
            {
                string chosen = string.Join(", ", upgrades.Select(u => $"{PsStr(GetProp(u, "MajorVersion"))} to {PsStr(GetProp(u, "TargetLevel"))} (KB{PsStr(GetProp(u, "KB"))})"));
                if (ShouldProcessSafe(resolvedName, $"Update {chosen}"))
                {
                    PSObject ia = new();
                    ia.Properties.Add(new PSNoteProperty("ComputerName", resolvedName));
                    ia.Properties.Add(new PSNoteProperty("Actions", upgrades.ToArray()));
                    installActions.Add(ia);
                }
            }
        }

        // ---- download path (KBs not present under -Path) ----
        ProcessDownloads(installActions, downloads);

        // ---- delegate execution ----
        foreach (PSObject item in installActions)
        {
            Hashtable updateSplat = new()
            {
                { "ComputerName", GetProp(item, "ComputerName") },
                { "Action", GetProp(item, "Actions") },
                { "Restart", Restart.ToBool() },
                { "Credential", Credential },
                { "EnableException", EnableException.ToBool() },
                { "ExtractPath", ExtractPath },
                { "Authentication", _resolvedAuthentication },
                { "ArgumentList", ArgumentList },
                { "NoPendingRenameCheck", NoPendingRenameCheck.ToBool() }
            };
            // Route through the dbatools module scope (not NestedCommand, which runs in the host
            // context) so `-ModuleName dbatools` mocks of Invoke-DbaAdvancedUpdate intercept - the
            // script function calls the worker from inside the module, which the mock targets.
            Collection<PSObject> workerResults = InvokeInModuleScope("param($__p) & 'Invoke-DbaAdvancedUpdate' @__p 3>&1", updateSplat);
            foreach (PSObject result in workerResults)
            {
                EmitResult(result);
            }
        }
    }

    // PS: the $outputHandler closure - default view + a warning on failure.
    private void EmitResult(PSObject result)
    {
        OutputHelper.SetDefaultDisplayPropertySet(result, new[] { "ComputerName", "MajorVersion", "TargetLevel", "KB", "Successful", "Restarted", "InstanceName", "Installer", "Notes" });
        object? successful = GetProp(result, "Successful");
        if (successful is not null && !LanguagePrimitives.IsTrue(successful))
        {
            string notes = string.Join(" | ", EnumerateAny(GetProp(result, "Notes")).Select(PsStr));
            WriteMessage(MessageLevel.Warning, $"Update failed: {notes}");
        }
        WriteObject(result);
    }

    // Remote-protocol probe (Invoke-Command2 { $true }); on CredSSP failure try Initialize-CredSSP
    // once, then optionally fall back to the primary protocol after a High-impact confirmation.
    private bool TestRemoteConnection(string resolvedName)
    {
        Hashtable RemoteSplat()
        {
            Hashtable s = new()
            {
                { "ComputerName", resolvedName }, { "Credential", Credential }, { "Authentication", _resolvedAuthentication },
                { "ScriptBlock", ScriptBlock.Create("$true") }, { "Raw", true }, { "UseSSL", UseSSL.ToBool() }
            };
            if (Port.HasValue && Port.Value > 0) { s["Port"] = Port.Value; }
            return s;
        }

        bool connectSuccess;
        try { connectSuccess = LanguagePrimitives.IsTrue(ScalarInModuleScope("Invoke-Command2", RemoteSplat())); }
        catch (PipelineStoppedException) { throw; }
        catch { connectSuccess = false; }

        if (!connectSuccess && string.Equals(_resolvedAuthentication, "Credssp", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                ScalarInModuleScope("Initialize-CredSSP", new Hashtable { { "ComputerName", resolvedName }, { "Credential", Credential }, { "EnableException", true } });
                connectSuccess = LanguagePrimitives.IsTrue(ScalarInModuleScope("Invoke-Command2", RemoteSplat()));
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex) { WriteMessage(MessageLevel.Warning, PsExceptionMessage(ex)); }
        }

        if (!connectSuccess)
        {
            if (!_notifiedUnsecure)
            {
                if (!ShouldProcessSafe(resolvedName, $"Primary protocol ({_resolvedAuthentication}) failed, sending credentials via potentially unsecure protocol"))
                {
                    StopFunction($"Failed to connect to {resolvedName} through {_resolvedAuthentication} protocol. No actions will be performed on that computer.", continueLoop: true);
                    return false;
                }
                _notifiedUnsecure = true;
            }
        }
        return true;
    }

    // PS: download missing KBs (network -Path → straight to Path[0]; local → temp), then copy
    // them to the target and back-patch each action's Installer to the local path.
    private void ProcessDownloads(List<PSObject> installActions, List<PSObject> downloads)
    {
        if (downloads.Count == 0) { return; }
        bool mainPathIsNetwork = TestNetworkPath(new[] { Path![0] });
        List<PSObject> downloadedKbs = new();

        foreach (PSObject kbItem in DistinctByKbArch(downloads))
        {
            string downloadPath = mainPathIsNetwork ? Path![0] : System.IO.Path.GetTempPath();
            try
            {
                object? fileItem = ScalarInModuleScope("Save-DbaKbUpdate", new Hashtable
                {
                    { "Name", GetProp(kbItem, "KB") }, { "Path", downloadPath }, { "Architecture", GetProp(kbItem, "Architecture") }, { "EnableException", true }
                });
                PSObject entry = new();
                entry.Properties.Add(new PSNoteProperty("FileItem", fileItem));
                entry.Properties.Add(new PSNoteProperty("KB", GetProp(kbItem, "KB")));
                entry.Properties.Add(new PSNoteProperty("Architecture", GetProp(kbItem, "Architecture")));
                downloadedKbs.Add(entry);
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex)
            {
                StopFunction($"Could not download installer for KB{PsStr(GetProp(kbItem, "KB"))}({PsStr(GetProp(kbItem, "Architecture"))}): {PsExceptionMessage(ex)}", continueLoop: true);
            }
        }
        if (downloadedKbs.Count == 0) { return; }

        foreach (PSObject installAction in installActions)
        {
            string computer = PsStr(GetProp(installAction, "ComputerName"));
            foreach (object? action in EnumerateAny(GetProp(installAction, "Actions")))
            {
                if (!string.IsNullOrEmpty(PsStr(GetProp(action, "Installer")))) { continue; }
                string kb = PsStr(GetProp(action, "KB"));
                string arch = PsStr(GetProp(action, "Architecture"));
                PSObject? match = downloadedKbs.FirstOrDefault(d => string.Equals(PsStr(GetProp(d, "KB")), kb, StringComparison.OrdinalIgnoreCase) && string.Equals(PsStr(GetProp(d, "Architecture")), arch, StringComparison.OrdinalIgnoreCase));
                if (match is null) { continue; }
                object? fileItem = GetProp(match, "FileItem");
                string filePath = System.IO.Path.Combine(Path![0], PsStr(GetProp(fileItem, "Name")));
                if (!mainPathIsNetwork)
                {
                    try { CopyUncFile(new DbaInstanceParameter(computer), PsStr(GetProp(fileItem, "FullName")), Path![0], computer); }
                    catch (PipelineStoppedException) { throw; }
                    catch (Exception ex)
                    {
                        StopFunction($"Could not move installer {PsStr(GetProp(fileItem, "FullName"))} to {Path![0]} on {computer}: {PsExceptionMessage(ex)}", continueLoop: true);
                    }
                }
                SetProp(action, "Installer", filePath);
            }
        }
        if (!mainPathIsNetwork)
        {
            foreach (PSObject dk in downloadedKbs)
            {
                InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__p) Remove-Item $__p -Force"), null, PsStr(GetProp(GetProp(dk, "FileItem"), "FullName")));
            }
        }
    }

    // ---- inner functions (byte-parity ports; source bugs preserved) ----

    // PS Join-AdminUnc: NOTE - a "\\"-prefixed path returns the *undefined* $filepath (→ null) in
    // the source; preserved. Otherwise "\\<server>\<C$>\path".
    private static string? JoinAdminUnc(DbaInstanceParameter computerName, string path)
    {
        if (path.StartsWith("\\\\", StringComparison.Ordinal)) { return null; }
        string server = computerName.ComputerName;
        // The PS source is Join-Path "\\server\" (path with : -> $). Path.Combine is NOT a faithful
        // stand-in: given a rooted child ("\logs\x" or "/logs/x") it discards the parent entirely
        // and returns the bare child, losing the server. Join-Path instead normalizes forward
        // slashes to backslashes and collapses the single duplicate boundary separator, yielding
        // "\\server\logs\x". Replicate that.
        string child = path.Replace(':', '$').Replace('/', '\\');
        if (child.Length > 0 && child[0] == '\\')
        {
            child = child.Substring(1);
        }
        return "\\\\" + server + "\\" + child;
    }

    // PS Copy-UncFile: the localhost checks read the ORIGINATING computer name (the PS source reads
    // the parent-scope loop var $groupItem); passed explicitly here as originComputer.
    private void CopyUncFile(DbaInstanceParameter computerName, string path, string destination, string originComputer)
    {
        bool originIsLocal = new DbaInstanceParameter(originComputer).IsLocalHost;
        string remoteFolder;
        if (originIsLocal) { remoteFolder = destination; }
        else
        {
            string? unc = JoinAdminUnc(computerName, destination);
            Hashtable driveSplat = new() { { "Name", "UpdateCopy" }, { "Root", unc }, { "PSProvider", "FileSystem" } };
            if (Credential is not null) { driveSplat["Credential"] = Credential; }
            InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__p) New-PSDrive @__p -ErrorAction Stop | Out-Null"), null, driveSplat);
            remoteFolder = "UpdateCopy:\\";
        }
        try
        {
            InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__s, $__d) Copy-Item -Path $__s -Destination $__d -ErrorAction Stop"), null, path, remoteFolder);
        }
        finally
        {
            if (!originIsLocal)
            {
                InvokeCommand.InvokeScript(false, ScriptBlock.Create("Remove-PSDrive -Name UpdateCopy -Force"), null);
            }
        }
    }

    // PS Test-NetworkPath: true if ANY path starts with "\\".
    private static bool TestNetworkPath(string[]? paths)
    {
        if (paths is null) { return false; }
        return paths.Any(p => p is not null && p.StartsWith("\\\\", StringComparison.Ordinal));
    }

    // ---- High-impact ShouldProcess wrapper (see InstallDbaInstanceCommand) ----
    private bool ShouldProcessSafe(string target, string action)
    {
        try { return ShouldProcess(target, action); }
        catch (PipelineStoppedException) { throw; }
        catch { return true; }
    }

    // ---- module-scoped invocation (so -ModuleName dbatools mocks intercept) ----
    private Collection<PSObject> InvokeInModuleScope(string scriptText, object payload)
    {
        ScriptBlock script = ScriptBlock.Create(
            "param($__body, $__p) " +
            "$__m = Get-Module dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1; " +
            "& $__m ([ScriptBlock]::Create($__body)) $__p");
        NestedCommand.RequireDbatoolsScriptModule(this);
        Collection<PSObject> raw = InvokeCommand.InvokeScript(false, script, null, scriptText, payload);
        Collection<PSObject> output = new();
        foreach (PSObject item in raw)
        {
            if (item?.BaseObject is WarningRecord warning) { WriteWarning(warning.Message); }
            else if (item is not null) { output.Add(item); }
        }
        return output;
    }

    private object? ScalarInModuleScope(string command, Hashtable splat)
    {
        Collection<PSObject> output = InvokeInModuleScope("param($__p) & '" + command + "' @__p 3>&1", splat);
        if (output.Count == 0) { return null; }
        if (output.Count == 1) { return output[0]; }
        object?[] many = new object?[output.Count];
        for (int i = 0; i < output.Count; i++) { many[i] = output[i]; }
        return many;
    }

    // ---- PS-parity helpers ----

    private static string? GroupOrNull(Match m, int n)
    {
        Group g = m.Groups[n];
        return g.Success && g.Value.Length > 0 ? g.Value : null;
    }

    private static bool NameLevelContains(object? component, string major)
    {
        object? version = GetProp(component, "Version");
        object? nameLevel = GetProp(version, "NameLevel");
        foreach (object? nl in EnumerateAny(nameLevel))
        {
            if (string.Equals(PsStr(nl), major, StringComparison.OrdinalIgnoreCase)) { return true; }
        }
        return false;
    }

    private static object? CollectionToArray(Collection<PSObject> c)
    {
        if (c.Count == 0) { return null; }
        object?[] arr = new object?[c.Count];
        for (int i = 0; i < c.Count; i++) { arr[i] = c[i]; }
        return arr;
    }

    private static List<object?> FlattenObjects(Collection<PSObject> c)
    {
        List<object?> flat = new();
        foreach (PSObject item in c)
        {
            object? bo = item?.BaseObject;
            if (bo is object?[] arr) { flat.AddRange(arr); }
            else if (item is not null) { flat.Add(item); }
        }
        return flat;
    }

    private static IEnumerable<PSObject> DistinctByKbArch(List<PSObject> downloads)
    {
        HashSet<string> seen = new(StringComparer.OrdinalIgnoreCase);
        foreach (PSObject d in downloads)
        {
            string key = PsStr(GetProp(d, "KB")) + "|" + PsStr(GetProp(d, "Architecture"));
            if (seen.Add(key)) { yield return d; }
        }
    }

    private static IEnumerable<object?> EnumerateAny(object? value)
    {
        if (value is null) { yield break; }
        if (value is PSObject pso && pso.BaseObject is not string && pso.BaseObject is IEnumerable psoEnum && pso.BaseObject is not IDictionary)
        {
            foreach (object? o in psoEnum) { yield return o; }
            yield break;
        }
        if (value is string) { yield return value; yield break; }
        if (value is IEnumerable en && value is not IDictionary)
        {
            foreach (object? o in en) { yield return o; }
            yield break;
        }
        yield return value;
    }

    private static object? GetProp(object? obj, string name)
    {
        if (obj is null) { return null; }
        PSObject pso = obj as PSObject ?? PSObject.AsPSObject(obj);
        return pso.Properties[name]?.Value;
    }

    private static void SetProp(object? obj, string name, object? value)
    {
        if (obj is null) { return; }
        PSObject pso = obj as PSObject ?? PSObject.AsPSObject(obj);
        if (pso.Properties[name] is not null) { pso.Properties[name].Value = value; }
        else { pso.Properties.Add(new PSNoteProperty(name, value)); }
    }

    private ErrorRecord AsRecord(Exception ex)
    {
        if (ex is IContainsErrorRecord cer && cer.ErrorRecord is not null) { return cer.ErrorRecord; }
        return new ErrorRecord(ex, "UpdateDbaInstance", ErrorCategory.NotSpecified, null);
    }

    private static string PsExceptionMessage(Exception ex)
    {
        if (ex is IContainsErrorRecord cer && cer.ErrorRecord?.Exception is not null) { return cer.ErrorRecord.Exception.Message; }
        return ex.Message;
    }

    private string ConvertToJsonCompact(object value)
    {
        Collection<PSObject> r = InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__o) $__o | ConvertTo-Json -Depth 1 -Compress"), null, value);
        return r.Count > 0 ? PsStr(r[0]) : string.Empty;
    }

    private static string PsStr(object? value)
    {
        if (value is null) { return string.Empty; }
        if (value is PSObject pso) { value = pso.BaseObject; }
        return LanguagePrimitives.ConvertTo<string>(value) ?? string.Empty;
    }

    // ---- config-backed parameter defaults (PS: Get-DbatoolsConfigValue) ----

    private static string[]? DefaultUpdatePath()
    {
        if (ConfigurationHost.Configurations.TryGetValue("path.sqlserverupdates", out Config? config) && config?.Value is not null)
        {
            if (config.Value is object?[] arr)
            {
                List<string> paths = new();
                foreach (object? o in arr) { if (o is not null) { paths.Add(PsStr(o)); } }
                return paths.ToArray();
            }
            return new[] { PsStr(config.Value) };
        }
        return null;
    }

    private static bool DefaultUseSSL()
    {
        if (ConfigurationHost.Configurations.TryGetValue("psremoting.pssession.usessl", out Config? config) && config?.Value is not null)
        {
            return LanguagePrimitives.IsTrue(config.Value);
        }
        return false;
    }

    private static int? DefaultPort()
    {
        if (ConfigurationHost.Configurations.TryGetValue("psremoting.pssession.port", out Config? config) && config?.Value is not null)
        {
            try { return Convert.ToInt32(config.Value); } catch { return null; }
        }
        return null;
    }

    private static bool DefaultPendingRename()
    {
        if (ConfigurationHost.Configurations.TryGetValue("os.pendingrename", out Config? config) && config?.Value is not null)
        {
            return LanguagePrimitives.IsTrue(config.Value);
        }
        return false;
    }
}
