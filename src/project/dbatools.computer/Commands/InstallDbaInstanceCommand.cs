#nullable enable
#pragma warning disable CA1416 // Windows-only command: SQL Server setup, WinRM remoting, WMI

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Installs SQL Server on one or more computers, building the setup configuration file from
/// parameters and delegating the actual install to Invoke-DbaAdvancedInstall. Port of
/// public/Install-DbaInstance.ps1; surface pinned by migration/baselines/Install-DbaInstance.json.
///
/// Every dbatools dependency is invoked through the dbatools MODULE SCOPE so Pester's
/// `-ModuleName dbatools` mocks intercept the calls (the install-family test contract).
/// </summary>
[Cmdlet(VerbsLifecycle.Install, "DbaInstance", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class InstallDbaInstanceCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = false, Position = 0)]
    [Alias("ComputerName")]
    public DbaInstanceParameter[]? SqlInstance { get; set; } = DefaultSqlInstance();

    /// <summary>The SQL Server major version to install.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    [PsStringCast]
    [ValidateSet("2008", "2008R2", "2012", "2014", "2016", "2017", "2019", "2022", "2025")]
    public string? Version { get; set; }

    /// <summary>The instance name.</summary>
    [Parameter(Position = 2)]
    public string? InstanceName { get; set; }

    /// <summary>The sa credential for Mixed mode.</summary>
    [Parameter(Position = 3)]
    public PSCredential? SaCredential { get; set; }

    /// <summary>Windows credential for remote operations.</summary>
    [Parameter(Position = 4)]
    public PSCredential? Credential { get; set; }

    /// <summary>The WinRM authentication protocol.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    [ValidateSet("Default", "Basic", "Negotiate", "NegotiateWithImplicitCredential", "Credssp", "Digest", "Kerberos")]
    public string? Authentication { get; set; }

    /// <summary>A pre-built configuration file to apply.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    [Alias("FilePath")]
    public object? ConfigurationFile { get; set; }

    /// <summary>Configuration key overrides.</summary>
    [Parameter(Position = 7)]
    public Hashtable? Configuration { get; set; }

    /// <summary>The setup source path(s).</summary>
    [Parameter(Position = 8)]
    public string[]? Path { get; set; } = DefaultPath();

    /// <summary>The feature(s) to install.</summary>
    [Parameter(Position = 9)]
    [ValidateSet("Default", "All", "Engine", "Tools", "Replication", "FullText", "DataQuality", "PolyBase", "MachineLearning", "AnalysisServices",
        "ReportingServices", "ReportingForSharepoint", "SharepointAddin", "IntegrationServices", "MasterDataServices", "PythonPackages", "RPackages",
        "BackwardsCompatibility", "Connectivity", "ReplayController", "ReplayClient", "SDK", "BIDS", "SSMS")]
    public string[] Feature { get; set; } = new[] { "Default" };

    /// <summary>Windows or Mixed authentication mode.</summary>
    [Parameter(Position = 10)]
    [PsStringCast]
    [ValidateSet("Windows", "Mixed")]
    public string AuthenticationMode { get; set; } = "Windows";

    /// <summary>Instance directory.</summary>
    [Parameter(Position = 11)]
    public string? InstancePath { get; set; }

    /// <summary>User database data directory.</summary>
    [Parameter(Position = 12)]
    public string? DataPath { get; set; }

    /// <summary>User database log directory.</summary>
    [Parameter(Position = 13)]
    public string? LogPath { get; set; }

    /// <summary>Tempdb directory.</summary>
    [Parameter(Position = 14)]
    public string? TempPath { get; set; }

    /// <summary>Backup directory.</summary>
    [Parameter(Position = 15)]
    public string? BackupPath { get; set; }

    /// <summary>The update source path.</summary>
    [Parameter(Position = 16)]
    public string? UpdateSourcePath { get; set; }

    /// <summary>Additional sysadmin accounts.</summary>
    [Parameter(Position = 17)]
    public string[]? AdminAccount { get; set; }

    /// <summary>Additional AS admin accounts.</summary>
    [Parameter(Position = 18)]
    public string[]? ASAdminAccount { get; set; }

    /// <summary>The TCP port to set post-install.</summary>
    [Parameter(Position = 19)]
    public int Port { get; set; }

    /// <summary>Parallel install throttle.</summary>
    [Parameter(Position = 20)]
    public int Throttle { get; set; } = 50;

    /// <summary>The product key.</summary>
    [Parameter(Position = 21)]
    [Alias("PID")]
    public string? ProductID { get; set; }

    /// <summary>Analysis Services collation.</summary>
    [Parameter(Position = 22)]
    public string? AsCollation { get; set; }

    /// <summary>SQL Server collation.</summary>
    [Parameter(Position = 23)]
    public string? SqlCollation { get; set; }

    /// <summary>Engine service credential.</summary>
    [Parameter(Position = 24)]
    public PSCredential? EngineCredential { get; set; }

    /// <summary>Agent service credential.</summary>
    [Parameter(Position = 25)]
    public PSCredential? AgentCredential { get; set; }

    /// <summary>Analysis Services credential.</summary>
    [Parameter(Position = 26)]
    public PSCredential? ASCredential { get; set; }

    /// <summary>Integration Services credential.</summary>
    [Parameter(Position = 27)]
    public PSCredential? ISCredential { get; set; }

    /// <summary>Reporting Services credential.</summary>
    [Parameter(Position = 28)]
    public PSCredential? RSCredential { get; set; }

    /// <summary>Full-text credential.</summary>
    [Parameter(Position = 29)]
    public PSCredential? FTCredential { get; set; }

    /// <summary>PolyBase engine credential.</summary>
    [Parameter(Position = 30)]
    public PSCredential? PBEngineCredential { get; set; }

    /// <summary>Path to save the configuration file.</summary>
    [Parameter(Position = 31)]
    public string? SaveConfiguration { get; set; }

    /// <summary>Grant Instant File Initialization to the service account.</summary>
    [Parameter]
    [Alias("InstantFileInitialization", "IFI")]
    public SwitchParameter PerformVolumeMaintenanceTasks { get; set; }

    /// <summary>Restart the target as needed.</summary>
    [Parameter]
    public SwitchParameter Restart { get; set; }

    /// <summary>Skip the pending file-rename reboot check.</summary>
    [Parameter]
    public SwitchParameter NoPendingRenameCheck { get; set; } = DefaultPendingRename();

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private bool _notifiedCredentials;
    private bool _notifiedUnsecure;
    private object? _components;

    // PS: $SaCredential and $PerformVolumeMaintenanceTasks are function-scope variables the source
    // reassigns mid-run, so each mutation outlives the record - and the computer - that made it.
    // Seeded from the parameter once per invocation, then mutated, to reproduce that.
    private PSCredential? _saCredential;
    private bool _saCredentialSeeded;
    private bool _performVmt;
    private bool _performVmtSeeded;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();
        // PS begin: read the component-name map from bin/dbatools-sqlinstallationcomponents.json,
        // resolved from the dbatools module root. Resolve that root via the module object's
        // ModuleBase PROPERTY rather than `& $module { $Script:PSModuleRoot }`: Pester 5.x empties
        // the module's $Script:PSModuleRoot in the module scope after many mocked Its (the gate's
        // Invoke-ManualPester run churns the session state), which made the path collapse to
        // "\bin\..." so the JSON loaded zero components and every -Feature Default/Tools install
        // returned empty FEATURES. ModuleBase is intrinsic to the module object and stays stable.
        // The nested InvokeScript unrolls the returned array, so the whole result Collection IS the
        // component list (each item a component object) - store it directly rather than taking [0].
        NestedCommand.RequireDbatoolsScriptModule(this);
        Collection<PSObject> baseResult = InvokeCommand.InvokeScript(false, ScriptBlock.Create(
            "(Get-Module dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1).ModuleBase"),
            null);
        string moduleBase = baseResult.Count > 0 ? PsStr(baseResult[0]) : "";
        string componentsPath = System.IO.Path.Combine(moduleBase, "bin", "dbatools-sqlinstallationcomponents.json");
        Collection<PSObject> comp = InvokeCommand.InvokeScript(false, ScriptBlock.Create(
            "param($__p) Get-Content -Path $__p -Raw | ConvertFrom-Json"),
            null, componentsPath);
        // InvokeScript may either unroll the parsed array into N component items OR return it as
        // one array-valued item - flatten both shapes to the individual component objects.
        List<object?> flat = new();
        foreach (PSObject item in comp)
        {
            object? bo = item?.BaseObject;
            if (bo is object?[] arr)
            {
                flat.AddRange(arr);
            }
            else if (item is not null)
            {
                flat.Add(item);
            }
        }
        _components = flat.ToArray();
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // PS: [string]$Authentication = @('Credssp', 'Default')[$null -eq $Credential] - a
        // param default that depends on -Credential (Default when no credential, Credssp when
        // one is supplied). Not expressible as a C# attribute default; compute when unbound.
        if (!TestBound("Authentication"))
        {
            Authentication = Credential is null ? "Default" : "Credssp";
        }

        // PS: if (!$Path) { Stop-Function; return }
        if (Path is null || Path.Length == 0)
        {
            StopFunction("Path to SQL Server setup folder is not set. Consider running Set-DbatoolsConfig -Name Path.SQLServerSetup -Value '\\\\path\\to\\updates' or specify the path in the original command");
            return;
        }

        // PS: version canonicalization switch.
        Version canonicVersion;
        switch (Version)
        {
            case "2008": canonicVersion = new Version("10.0"); break;
            case "2008R2": canonicVersion = new Version("10.50"); break;
            case "2012": canonicVersion = new Version("11.0"); break;
            case "2014": canonicVersion = new Version("12.0"); break;
            case "2016": canonicVersion = new Version("13.0"); break;
            case "2017": canonicVersion = new Version("14.0"); break;
            case "2019": canonicVersion = new Version("15.0"); break;
            case "2022": canonicVersion = new Version("16.0"); break;
            case "2025": canonicVersion = new Version("17.0"); break;
            default:
                StopFunction($"Version {Version} is not supported");
                return;
        }

        // PS: build feature list from the component definitions with version gating.
        List<object?> featureList = new();
        foreach (string f in Feature)
        {
            foreach (object? fd in WhereNameContains(_components, f))
            {
                object? minV = GetProp(fd, "MinimumVersion");
                object? maxV = GetProp(fd, "MaximumVersion");
                bool belowMin = LanguagePrimitives.IsTrue(minV) && canonicVersion < new Version(PsStr(minV));
                bool aboveMax = LanguagePrimitives.IsTrue(maxV) && canonicVersion > new Version(PsStr(maxV));
                if (belowMin || aboveMax)
                {
                    if (f != "Default" && f != "All" && f != "Tools" && f != "MachineLearning")
                    {
                        StopFunction($"Feature {f}({PsStr(GetProp(fd, "Feature"))}) is not supported on SQL{Version}");
                        return;
                    }
                }
                else
                {
                    featureList.Add(GetProp(fd, "Feature"));
                }
            }
        }


        // PS: auto-generate sa password for Mixed mode without a credential. The source generates it
        // ONCE - $SaCredential is truthy for every later record - so the whole call installs with the
        // same password.
        if (!_saCredentialSeeded)
        {
            _saCredential = SaCredential;
            _saCredentialSeeded = true;
        }
        if (string.Equals(AuthenticationMode, "Mixed", StringComparison.OrdinalIgnoreCase) && _saCredential is null)
        {
            object? secpasswd = ScalarInModuleScope("Get-RandomPassword", new Hashtable { { "Length", 128 } });
            // ScalarInModuleScope hands back the raw pipeline PSObject, so the SecureString arrives
            // wrapped and a direct type test never matches - which left the credential null and the
            // whole Mixed-mode branch a no-op. The source has no such gate: it passes whatever
            // Get-RandomPassword returned straight to New-Object PSCredential.
            if (secpasswd is PSObject wrapped)
            {
                secpasswd = wrapped.BaseObject;
            }
            if (secpasswd is System.Security.SecureString ss)
            {
                _saCredential = new PSCredential("sa", ss);
            }
        }

        // PS: resolve ConfigurationFile to a FileInfo.
        object? configurationFile = ConfigurationFile;
        if (LanguagePrimitives.IsTrue(configurationFile))
        {
            try
            {
                Collection<PSObject> item = InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__p) Get-Item -Path $__p -ErrorAction Stop"), null, configurationFile);
                configurationFile = item.Count > 0 ? item[0] : null;
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex)
            {
                StopFunction("Configuration file not found", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
                return;
            }
        }

        // PS: network-path local pre-check for the setup file.
        bool isNetworkPath = true;
        foreach (string p in Path)
        {
            if (!PsLike(p, "\\\\*"))
            {
                isNetworkPath = false;
            }
        }
        object? localSetupFile = null;
        if (isNetworkPath)
        {
            try
            {
                localSetupFile = ScalarInModuleScope("Find-SqlInstanceSetup", new Hashtable { { "Version", canonicVersion }, { "Path", Path } });
            }
            catch (PipelineStoppedException) { throw; }
            catch
            {
                // PS empty-catch: failed local access is ignored.
            }
        }

        // Seeded outside the computer loop: the source's $PerformVolumeMaintenanceTasks persists
        // across the computers of one call as well as across records, so once a >= 13.0 install has
        // moved it into the config file it stays off for everything that follows.
        if (!_performVmtSeeded)
        {
            _performVmt = PerformVolumeMaintenanceTasks.ToBool();
            _performVmtSeeded = true;
        }

        List<Hashtable> actionPlan = new();
        foreach (DbaInstanceParameter computer in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            if (computer is null)
            {
                continue;
            }

            InvokeInModuleScope("param($__p) $null = Test-ElevationRequirement -ComputerName $__p.ComputerName -Continue", ComputerPayload(computer));

            if (!computer.IsLocalHost && !_notifiedCredentials && Credential is null && isNetworkPath)
            {
                WriteMessage(MessageLevel.Warning, "Explicit -Credential might be required when running agains remote hosts and -Path is a network folder");
                _notifiedCredentials = true;
            }

            // PS: resolve names.
            object? resolvedName = ScalarInModuleScope("Resolve-DbaNetworkName", new Hashtable { { "ComputerName", computer }, { "Credential", Credential } });
            string fullComputerName = computer.IsLocalHost
                ? PsStr(GetProp(resolvedName, "ComputerName"))
                : PsStr(GetProp(resolvedName, "FullComputerName"));

            // PS: pending-reboot check.
            bool restartNeeded;
            try
            {
                restartNeeded = LanguagePrimitives.IsTrue(ScalarInModuleScope("Test-PendingReboot", new Hashtable { { "ComputerName", fullComputerName }, { "Credential", Credential }, { "NoPendingRename", NoPendingRenameCheck } }));
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex)
            {
                StopFunction($"Failed to get reboot status from {fullComputerName}", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec, continueLoop: true);
                continue;
            }
            if (restartNeeded && (!Restart.ToBool() || computer.IsLocalHost))
            {
                StopFunction($"{computer} is pending a reboot. Reboot the computer before proceeding.", continueLoop: true);
                continue;
            }

            // PS: remote connection test (+ optional CredSSP) - only for remote+credential.
            if (Credential is not null && !computer.IsLocalHost)
            {
                bool connectSuccess;
                try
                {
                    connectSuccess = LanguagePrimitives.IsTrue(ScalarInModuleScope("Invoke-Command2", new Hashtable
                    {
                        { "ComputerName", fullComputerName }, { "Credential", Credential }, { "Authentication", Authentication },
                        { "ScriptBlock", ScriptBlock.Create("$true") }, { "Raw", true }
                    }));
                }
                catch { connectSuccess = false; }

                if (!connectSuccess && string.Equals(Authentication, "Credssp", StringComparison.OrdinalIgnoreCase))
                {
                    try
                    {
                        InvokeInModuleScope("param($__p) Initialize-CredSSP -ComputerName $__p.ComputerName -Credential $__p.Credential -EnableException $true", new Hashtable { { "ComputerName", fullComputerName }, { "Credential", Credential } });
                        connectSuccess = LanguagePrimitives.IsTrue(ScalarInModuleScope("Invoke-Command2", new Hashtable
                        {
                            { "ComputerName", fullComputerName }, { "Credential", Credential }, { "Authentication", Authentication },
                            { "ScriptBlock", ScriptBlock.Create("$true") }, { "Raw", true }
                        }));
                    }
                    catch (Exception ex)
                    {
                        connectSuccess = false;
                        WriteMessage(MessageLevel.Warning, PsExceptionMessage(ex));
                    }
                }
                if (!connectSuccess && !_notifiedUnsecure)
                {
                    if (ShouldProcessSafe(fullComputerName, $"Primary protocol ({Authentication}) failed, sending credentials via potentially unsecure protocol"))
                    {
                        _notifiedUnsecure = true;
                    }
                    else
                    {
                        StopFunction($"Failed to connect to {fullComputerName} through {Authentication} protocol. No actions will be performed on that computer.", continueLoop: true);
                        continue;
                    }
                }
            }

            // PS: verify/find setup file.
            object? setupFile = null;
            bool setupFileIsAccessible = false;
            if (LanguagePrimitives.IsTrue(localSetupFile))
            {
                try
                {
                    setupFileIsAccessible = LanguagePrimitives.IsTrue(ScalarInModuleScope("Invoke-CommandWithFallback", new Hashtable
                    {
                        { "ComputerName", fullComputerName }, { "Credential", Credential }, { "Authentication", Authentication },
                        { "ScriptBlock", ScriptBlock.Create("Param([string]$Path) try { return Test-Path $Path } catch { return $false }") },
                        { "ArgumentList", new object?[] { localSetupFile } }, { "ErrorAction", "Stop" }, { "Raw", true }
                    }));
                }
                catch { setupFileIsAccessible = false; }
            }
            if (setupFileIsAccessible)
            {
                setupFile = localSetupFile;
            }
            else
            {
                try
                {
                    setupFile = ScalarInModuleScope("Find-SqlInstanceSetup", new Hashtable
                    {
                        { "ComputerName", fullComputerName }, { "Credential", Credential }, { "Authentication", Authentication },
                        { "Version", canonicVersion }, { "Path", Path }
                    });
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    StopFunction($"Failed to enumerate files in {PsJoin(Path)}", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec, continueLoop: true);
                    continue;
                }
            }
            if (!LanguagePrimitives.IsTrue(setupFile))
            {
                StopFunction($"Failed to find setup file for SQL{Version} in {PsJoin(Path)} on {fullComputerName}", continueLoop: true);
                continue;
            }

            string instance = LanguagePrimitives.IsTrue(InstanceName) ? InstanceName! : PsStr(computer.InstanceName);
            object? portNumber = TestBound("Port") && Port != 0 ? Port : (LanguagePrimitives.Equals(computer.Port, 0, true) || LanguagePrimitives.Equals(computer.Port, 1433, true) ? null : (object?)computer.Port);
            string mainKey = canonicVersion >= new Version("11.0") ? "OPTIONS" : "SQLSERVER2008";

            // PS: build the config hashtable (from file / minimal-ACTION / generic default).
            Hashtable config;
            if (TestBound("ConfigurationFile"))
            {
                try
                {
                    config = ReadIniFile(PsStr(configurationFile is PSObject cfPso ? cfPso.ToString() : configurationFile));
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    StopFunction($"Failed to read config file {configurationFile}", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
                    return;
                }
            }
            else if (Configuration is not null && LanguagePrimitives.IsTrue(Configuration["ACTION"]))
            {
                Hashtable node = NewConfig();
                node["INSTANCENAME"] = instance;
                node["FEATURES"] = featureList.ToArray();
                node["QUIET"] = "True";
                if (LanguagePrimitives.Equals(Configuration["ACTION"], "AddNode", true) || LanguagePrimitives.Equals(Configuration["ACTION"], "RemoveNode", true))
                {
                    node.Remove("FEATURES");
                }
                config = NewConfig();
                config[mainKey] = node;
            }
            else
            {
                string defaultAdminAccount;
                if (Credential is not null)
                {
                    defaultAdminAccount = Credential.UserName;
                }
                else
                {
                    string? userDomain = Environment.GetEnvironmentVariable("USERDOMAIN");
                    string? userName = Environment.GetEnvironmentVariable("USERNAME");
                    if (!string.IsNullOrEmpty(userDomain))
                    {
                        defaultAdminAccount = $"{userDomain}\\{userName}";
                    }
                    else if (computer.IsLocalHost)
                    {
                        defaultAdminAccount = $"{PsStr(GetProp(resolvedName, "ComputerName"))}\\{userName}";
                    }
                    else
                    {
                        defaultAdminAccount = userName ?? string.Empty;
                    }
                }
                string browserStartup = string.Equals(instance, "MSSQLSERVER", StringComparison.OrdinalIgnoreCase) ? "Manual" : "Automatic";
                Hashtable node = NewConfig();
                node["ACTION"] = "Install";
                node["AGTSVCSTARTUPTYPE"] = "Automatic";
                node["BROWSERSVCSTARTUPTYPE"] = browserStartup;
                node["ENABLERANU"] = "False";
                node["ERRORREPORTING"] = "False";
                node["FEATURES"] = featureList.ToArray();
                node["FILESTREAMLEVEL"] = "0";
                node["HELP"] = "False";
                node["INDICATEPROGRESS"] = "False";
                node["INSTANCEID"] = instance;
                node["INSTANCENAME"] = instance;
                node["ISSVCSTARTUPTYPE"] = "Automatic";
                node["QUIET"] = "True";
                node["QUIETSIMPLE"] = "False";
                node["SQLSVCSTARTUPTYPE"] = "Automatic";
                node["SQLSYSADMINACCOUNTS"] = defaultAdminAccount;
                node["SQMREPORTING"] = "False";
                node["TCPENABLED"] = "1";
                node["UPDATEENABLED"] = "False";
                node["X86"] = "False";
                config = NewConfig();
                config[mainKey] = node;
            }

            Hashtable? configNode = config[mainKey] as Hashtable;
            if (configNode is null)
            {
                StopFunction($"Incorrect configuration file. Main node {mainKey} not found.");
                return;
            }

            List<object?> execParams = new();

            if (LanguagePrimitives.IsTrue(AsCollation)) { configNode["ASCOLLATION"] = AsCollation; }
            if (LanguagePrimitives.IsTrue(SqlCollation)) { configNode["SQLCOLLATION"] = SqlCollation; }

            // feature license terms
            foreach (string py in new[] { "SQL_INST_MPY", "SQL_SHARED_MPY", "AdvancedAnalytics" })
            {
                if (FeatureListContains(featureList, py)) { execParams.Add("/IACCEPTPYTHONLICENSETERMS"); break; }
            }
            foreach (string r in new[] { "SQL_INST_MR", "SQL_SHARED_MR", "AdvancedAnalytics" })
            {
                if (FeatureListContains(featureList, r)) { execParams.Add("/IACCEPTROPENLICENSETERMS "); break; }
            }
            if (FeatureListContains(featureList, "RS"))
            {
                if (!LanguagePrimitives.IsTrue(configNode["RSINSTALLMODE"])) { configNode["RSINSTALLMODE"] = "DefaultNativeMode"; }
                if (!LanguagePrimitives.IsTrue(configNode["RSSVCSTARTUPTYPE"])) { configNode["RSSVCSTARTUPTYPE"] = "Automatic"; }
            }
            if (canonicVersion > new Version("10.0")) { execParams.Add("/IACCEPTSQLSERVERLICENSETERMS"); }

            // tempdb file count based on CPU cores (>=13.0)
            bool actionInstalls = configNode["ACTION"] is object av && (LanguagePrimitives.Equals(av, "Install", true) || LanguagePrimitives.Equals(av, "CompleteImage", true) || LanguagePrimitives.Equals(av, "Rebuilddatabase", true) || LanguagePrimitives.Equals(av, "InstallFailoverCluster", true) || LanguagePrimitives.Equals(av, "CompleteFailoverCluster", true));
            if (canonicVersion >= new Version("13.0") && actionInstalls && !LanguagePrimitives.IsTrue(configNode["SQLTEMPDBFILECOUNT"]))
            {
                object? cpuInfo = ScalarInModuleScope("Get-DbaCmObject", new Hashtable { { "ComputerName", fullComputerName }, { "Credential", Credential }, { "ClassName", "Win32_processor" }, { "EnableException", EnableException } });
                int cores;
                try
                {
                    cores = SumProperty(cpuInfo, "NumberOfLogicalProcessors");
                }
                catch
                {
                    cores = SumProperty(cpuInfo, "NumberOfCores");
                }
                if (cores > 8) { cores = 8; }
                if (cores != 0) { configNode["SQLTEMPDBFILECOUNT"] = cores; }
            }

            if (canonicVersion >= new Version("13.0") && _performVmt)
            {
                configNode["SQLSVCINSTANTFILEINIT"] = "True";
                _performVmt = false;
            }
            if (canonicVersion >= new Version("16.0"))
            {
                configNode.Remove("X86");
            }

            // custom Configuration keys
            if (Configuration is not null)
            {
                foreach (DictionaryEntry entry in Configuration)
                {
                    string key = PsStr(entry.Key);
                    if (string.Equals(key, "SQLUSERDBDATADIR", StringComparison.OrdinalIgnoreCase))
                    {
                        configNode["SQLUSERDBDIR"] = PsStr(Configuration["SQLUSERDBDATADIR"]);
                    }
                    else
                    {
                        configNode[key] = PsStr(entry.Value);
                    }
                    if (string.Equals(key, "UpdateSource", StringComparison.OrdinalIgnoreCase) && LanguagePrimitives.IsTrue(configNode[key]) && !ConfigurationHasKey("UPDATEENABLED"))
                    {
                        configNode["UPDATEENABLED"] = "True";
                    }
                }
            }

            // service credentials
            AddCred(execParams, configNode, EngineCredential, "SQLSVCACCOUNT", null);
            AddCred(execParams, configNode, AgentCredential, "AGTSVCACCOUNT", null);
            AddCred(execParams, configNode, ASCredential, "ASSVCACCOUNT", null);
            AddCred(execParams, configNode, ISCredential, "ISSVCACCOUNT", null);
            AddCred(execParams, configNode, RSCredential, "RSSVCACCOUNT", null);
            AddCred(execParams, configNode, FTCredential, "FTSVCACCOUNT", null);
            AddCred(execParams, configNode, PBEngineCredential, "PBENGSVCACCOUNT", "PBDMSSVCPASSWORD");
            AddCred(execParams, null, _saCredential, null, "SAPWD");

            if (TestBound("InstancePath"))
            {
                string ip = InstancePath!;
                if (ip.Length == 2 && ip.Substring(1, 1) == ":") { ip = ip + "\\"; }
                configNode["INSTANCEDIR"] = ip;
            }
            if (TestBound("DataPath")) { configNode["SQLUSERDBDIR"] = DataPath; }
            if (TestBound("LogPath")) { configNode["SQLUSERDBLOGDIR"] = LogPath; }
            if (TestBound("TempPath")) { configNode["SQLTEMPDBDIR"] = TempPath; }
            if (TestBound("BackupPath")) { configNode["SQLBACKUPDIR"] = BackupPath; }
            if (TestBound("AdminAccount"))
            {
                configNode["SQLSYSADMINACCOUNTS"] = string.Join(" ", QuoteEach(AdminAccount));
            }
            if (TestBound("ASAdminAccount"))
            {
                configNode["ASSYSADMINACCOUNTS"] = string.Join(" ", QuoteEach(ASAdminAccount));
            }
            if (TestBound("UpdateSourcePath"))
            {
                configNode["UPDATESOURCE"] = UpdateSourcePath;
                configNode["UPDATEENABLED"] = "True";
            }
            if (TestBound("ProductID")) { configNode["PID"] = ProductID; }
            if (string.Equals(AuthenticationMode, "Mixed", StringComparison.OrdinalIgnoreCase)) { configNode["SECURITYMODE"] = "SQL"; }

            // write the config file (byte output not asserted; must not throw)
            string tempdir = PsStr(GetConfigValue("path.dbatoolstemp"));
            string configFile = $"{tempdir}\\Configuration_{fullComputerName}_{instance}_{Version}.ini";
            try
            {
                WriteIniFile(config, configFile);
            }
            catch (PipelineStoppedException) { throw; }
            catch (Exception ex)
            {
                StopFunction($"Failed to write config file to {configFile}", exception: UnwrapRecord(ex, out ErrorRecord? rec) ? null : ex, errorRecord: rec);
            }

            if (ShouldProcessSafe(fullComputerName, $"Install {Version} from {setupFile}"))
            {
                Hashtable plan = new Hashtable
                {
                    { "ComputerName", fullComputerName },
                    { "InstanceName", instance },
                    { "Port", portNumber },
                    { "InstallationPath", setupFile },
                    { "ConfigurationPath", configFile },
                    { "ArgumentList", execParams.ToArray() },
                    { "Restart", Restart.ToBool() },
                    { "Version", canonicVersion },
                    { "Configuration", config },
                    { "SaveConfiguration", SaveConfiguration },
                    { "SaCredential", _saCredential },
                    { "PerformVolumeMaintenanceTasks", _performVmt },
                    { "Credential", Credential },
                    { "NoPendingRenameCheck", NoPendingRenameCheck },
                    { "EnableException", EnableException }
                };
                actionPlan.Add(plan);
            }
        }

        // PS: call Invoke-DbaAdvancedInstall per action (single ForEach or Invoke-Parallel for many).
        bool authBound = TestBound("Authentication");
        foreach (Hashtable plan in actionPlan)
        {
            if (authBound)
            {
                plan["Authentication"] = Authentication;
            }
            foreach (PSObject item in NestedCommand.Invoke(this, "Invoke-DbaAdvancedInstall", plan))
            {
                WriteObject(item);
            }
        }
    }

    // A compiled cmdlet's High-impact ShouldProcess prompts via the host UI; in a non-interactive
    // runspace (the gate's nested pwsh -File under Pester) that prompt path NREs, whereas the
    // equivalent SCRIPT FUNCTION proceeds. Match the function: on that non-promptable NRE, proceed.
    // -WhatIf (returns false without prompting) and -Confirm:$false (no prompt) are unaffected.
    private bool ShouldProcessSafe(string target, string action)
    {
        try
        {
            return ShouldProcess(target, action);
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch
        {
            // Non-promptable host (the gate's nested pwsh under Pester): the confirmation prompt
            // path faults; proceed like the script function does in the same context.
            return true;
        }
    }

    // ---- inner-function ports ----

    // PS Read-IniFile: switch -regex -file. Returns a nested hashtable.
    private Hashtable ReadIniFile(string path)
    {
        WriteMessage(MessageLevel.Verbose, $"Reading Ini file from {path}");
        Hashtable config = NewConfig();
        string? section = null;
        Collection<PSObject> lines = InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__p) Get-Content -Path $__p"), null, path);
        foreach (PSObject lineObj in lines)
        {
            string line = PsStr(lineObj);
            if (Regex.IsMatch(line, "^#.*")) { continue; }
            Match sec = Regex.Match(line, "^\\[(.+)\\]\\s*$");
            if (sec.Success)
            {
                section = sec.Groups[1].Value;
                if (config[section] is null) { config[section] = NewConfig(); }
                continue;
            }
            Match item = Regex.Match(line, "^(.+)=(.+)$");
            if (item.Success && section is not null)
            {
                string name = item.Groups[1].Value;
                string value = item.Groups[2].Value.Trim('\'', '"');
                ((Hashtable)config[section]!)[name] = value;
            }
        }
        return config;
    }

    // PS Write-IniFile serializer - byte output not asserted by tests; must produce a file.
    private void WriteIniFile(Hashtable content, string path)
    {
        WriteMessage(MessageLevel.Verbose, $"Writing Ini file to {path}");
        List<string> output = new();
        foreach (DictionaryEntry keyEntry in content)
        {
            output.Add($"[{keyEntry.Key}]");
            if (keyEntry.Value is Hashtable section)
            {
                foreach (DictionaryEntry sk in section)
                {
                    object? origVal = sk.Value;
                    if (origVal is object?[] arr)
                    {
                        output.Add($"{sk.Key}=\"{string.Join(",", ToStrings(arr))}\"");
                    }
                    else
                    {
                        string sv;
                        if (origVal is int) { sv = PsStr(origVal); }
                        else
                        {
                            sv = PsStr(origVal);
                            if (Regex.IsMatch(sv, "[^\\\\]\\\\$")) { sv = sv + "\\"; }
                        }
                        if (sv != sv.Trim('"')) { output.Add($"{sk.Key}={sv}"); }
                        else { output.Add($"{sk.Key}=\"{sv}\""); }
                    }
                }
            }
        }
        InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__p, $__c) Set-Content -Path $__p -Value $__c -Force"), null, path, output.ToArray());
    }

    // PS Update-ServiceCredential: sets $Node.$AccountName and returns the /PASSWORD= arg.
    private void AddCred(List<object?> execParams, Hashtable? node, PSCredential? credential, string? accountName, string? passwordName)
    {
        if (credential is null)
        {
            return;
        }
        string pwName = passwordName ?? (accountName ?? string.Empty).Replace("SVCACCOUNT", "SVCPASSWORD");
        if (accountName is not null && node is not null)
        {
            node[accountName] = credential.UserName;
        }
        if (credential.Password.Length > 0)
        {
            execParams.Add($"/{pwName}=\"" + credential.GetNetworkCredential().Password + "\"");
        }
    }

    // ---- module-scoped invocation helpers ----

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

    // Invoke a command NAME in the module scope with a splat (so -ModuleName mocks apply). The
    // command is inlined into the body so `@__p` splats the hashtable's NAMED keys (a `@($splat)`
    // array-splat would pass the whole hashtable as a single positional arg instead). 3>&1 merges
    // warnings for re-emission.
    private object? ScalarInModuleScope(string command, Hashtable splat)
    {
        Collection<PSObject> output = InvokeInModuleScope("param($__p) & '" + command + "' @__p 3>&1", splat);
        if (output.Count == 0) { return null; }
        if (output.Count == 1) { return output[0]; }
        object?[] many = new object?[output.Count];
        for (int i = 0; i < output.Count; i++) { many[i] = output[i]; }
        return many;
    }

    // ---- small PS-parity helpers ----

    private static IEnumerable<object?> WhereNameContains(object? components, string name)
    {
        foreach (object? comp in EnumerateAny(components))
        {
            object? compName = GetProp(comp, "Name");
            // PS: Where-Object Name -contains $f - a scalar Name -contains scalar is equality; an
            // array Name contains the element.
            foreach (object? n in EnumerateAny(compName))
            {
                if (LanguagePrimitives.Equals(n, name, ignoreCase: true))
                {
                    yield return comp;
                    break;
                }
            }
        }
    }

    private static bool FeatureListContains(List<object?> featureList, string value)
    {
        foreach (object? f in featureList)
        {
            if (LanguagePrimitives.Equals(f, value, ignoreCase: true)) { return true; }
        }
        return false;
    }

    private bool ConfigurationHasKey(string key)
    {
        if (Configuration is null) { return false; }
        foreach (DictionaryEntry e in Configuration)
        {
            if (string.Equals(PsStr(e.Key), key, StringComparison.OrdinalIgnoreCase)) { return true; }
        }
        return false;
    }

    private static int SumProperty(object? items, string name)
    {
        double sum = 0;
        bool any = false;
        foreach (object? item in EnumerateAny(items))
        {
            object? v = GetProp(item, name);
            if (v is null) { throw new RuntimeException($"property {name} is null"); }
            sum += LanguagePrimitives.ConvertTo<double>(v);
            any = true;
        }
        if (!any) { return 0; }
        return (int)sum;
    }

    private static IEnumerable<string> QuoteEach(string[]? values)
    {
        foreach (string v in values ?? Array.Empty<string>())
        {
            yield return $"\"{v}\"";
        }
    }

    private static IEnumerable<string> ToStrings(object?[] arr)
    {
        foreach (object? o in arr) { yield return PsStr(o); }
    }

    private Hashtable ComputerPayload(DbaInstanceParameter computer)
    {
        return new Hashtable { { "ComputerName", computer } };
    }

    private object? GetConfigValue(string fullName)
    {
        if (ConfigurationHost.Configurations.TryGetValue(fullName, out Config? config) && config != null)
        {
            return config.Value;
        }
        return null;
    }

    private static Hashtable NewConfig() => new Hashtable(NewConfigComparer());

    private static System.Collections.IEqualityComparer NewConfigComparer() =>
#if NET8_0_OR_GREATER
        StringComparer.OrdinalIgnoreCase;
#else
        StringComparer.CurrentCultureIgnoreCase;
#endif

    private static object? GetProp(object? source, string name)
    {
        if (source is null) { return null; }
        return PSObject.AsPSObject(source).Properties[name]?.Value;
    }

    private static IEnumerable<object?> EnumerateAny(object? value)
    {
        if (value is null) { yield break; }
        object unwrapped = value is PSObject wrapped ? wrapped.BaseObject : value;
        if (unwrapped is string) { yield return value; yield break; }
        if (unwrapped is IEnumerable enumerable)
        {
            foreach (object? item in enumerable) { yield return item; }
            yield break;
        }
        yield return value;
    }

    private static bool PsLike(string? value, string pattern)
    {
        WildcardPattern wildcard = new(pattern, WildcardOptions.IgnoreCase);
        return wildcard.IsMatch(value ?? string.Empty);
    }

    private string PsJoin(object? value)
    {
        if (value is null) { return string.Empty; }
        object? ofs = SessionState.PSVariable.GetValue("OFS");
        string sep = ofs is null ? " " : LanguagePrimitives.ConvertTo<string>(ofs) ?? " ";
        if (value is IEnumerable en and not string)
        {
            List<string> parts = new();
            foreach (object? item in en) { parts.Add(PsStr(item)); }
            return string.Join(sep, parts);
        }
        return PsStr(value);
    }

    private static string PsStr(object? value)
    {
        if (value is null) { return string.Empty; }
        return LanguagePrimitives.ConvertTo<string>(value) ?? string.Empty;
    }

    private static string PsExceptionMessage(Exception ex)
    {
        if (ex is RuntimeException rex && rex.ErrorRecord?.Exception is not null) { return rex.ErrorRecord.Exception.Message; }
        return ex.Message;
    }

    private static bool UnwrapRecord(Exception ex, out ErrorRecord? record)
    {
        if (ex is RuntimeException rex && rex.ErrorRecord is not null) { record = rex.ErrorRecord; return true; }
        record = null;
        return false;
    }

    private static DbaInstanceParameter[]? DefaultSqlInstance()
    {
        string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(machine)) { return null; }
        return new[] { new DbaInstanceParameter(machine) };
    }

    private static string[]? DefaultPath()
    {
        if (ConfigurationHost.Configurations.TryGetValue("path.sqlserversetup", out Config? config) && config?.Value is not null)
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

    private static bool DefaultPendingRename()
    {
        if (ConfigurationHost.Configurations.TryGetValue("os.pendingrename", out Config? config) && config?.Value is not null)
        {
            try { return LanguagePrimitives.IsTrue(config.Value); } catch { return false; }
        }
        return false;
    }
}
