#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Resolves SQL Server build levels against the build-reference index. Port of
/// public/Get-DbaBuild.ps1 (W1-057). The two nested helpers
/// (Get-DbaBuildReferenceIndex with its RB-IMP-51 ModuleBase fallback + Resolve-DbaBuild)
/// run BYTE-VERBATIM inside module hops, defined as functions so the Stop-Function
/// callstack prefixes match; the compliance gates, MajorVersion/SP/CU normalization and
/// the four output branches are native, each branch's Resolve+PSCustomObject segment
/// riding one hop (the fn's exact literals, Select-DefaultView included). $script:
/// PSModuleRoot is read live off the module SessionState; the index load rides the fn's
/// try (EngineTryScope) into Stop-Function + interrupt on failure.
/// Surface pinned by migration/baselines/Get-DbaBuild.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaBuild", DefaultParameterSetName = "Build")]
public sealed class GetDbaBuildCommand : DbaBaseCmdlet
{
    /// <summary>The build number(s) to resolve.</summary>
    [Parameter(Position = 0)]
    public Version[]? Build { get; set; }

    /// <summary>The KB number(s) to resolve.</summary>
    [Parameter(Position = 1)]
    public string[]? Kb { get; set; }

    /// <summary>The SQL release (SQL2017-style or 2017).</summary>
    [Parameter(Position = 2)]
    [ValidateNotNullOrEmpty]
    public string? MajorVersion { get; set; }

    /// <summary>The service pack level.</summary>
    [Parameter(Position = 3)]
    [ValidateNotNullOrEmpty]
    [Alias("SP")]
    public string ServicePack { get; set; } = "RTM";

    /// <summary>The cumulative update level.</summary>
    [Parameter(Position = 4)]
    [Alias("CU")]
    public string? CumulativeUpdate { get; set; }

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 6)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Refreshes the reference index from the online source.</summary>
    [Parameter]
    public SwitchParameter Update { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _idxRef;

    protected override void BeginProcessing()
    {
        // PS: mutual-exclusion compliance over ('Build','Kb',('MajorVersion','ServicePack',
        // 'CumulativeUpdate'),'SqlInstance') with the pipeline-expectation special case.
        bool isPipelineSqlInstance = MyInvocation.ExpectingInput;
        List<string> complianceSpec = new List<string>();
        string[][] groups = new string[][]
        {
            new[] { "Build" },
            new[] { "Kb" },
            new[] { "MajorVersion", "ServicePack", "CumulativeUpdate" },
            new[] { "SqlInstance" },
        };
        foreach (string[] group in groups)
        {
            foreach (string name in group)
            {
                if (name == "SqlInstance")
                {
                    if (isPipelineSqlInstance || TestBound("SqlInstance"))
                        complianceSpec.Add(name);
                }
                else if (TestBound(name))
                {
                    complianceSpec.Add(name);
                    break;
                }
            }
        }
        if (complianceSpec.Count == 0 && !TestBound("Update") && !isPipelineSqlInstance)
        {
            StopFunction("You need to choose at least one parameter.", category: ErrorCategory.InvalidArgument);
            return;
        }
        if (complianceSpec.Count > 1)
        {
            StopFunction(string.Join(", ", complianceSpec) + " are mutually exclusive. Please choose one or the other. Quitting.", category: ErrorCategory.InvalidArgument);
            return;
        }
        if ((TestBound("ServicePack") || TestBound("CumulativeUpdate")) && !TestBound("MajorVersion"))
        {
            StopFunction("-MajorVersion is required when specifying SP or CU.", category: ErrorCategory.InvalidArgument);
            return;
        }
        if (PsOps.IsTrue(MajorVersion))
        {
            Match major = Regex.Match(MajorVersion!, "^(SQL)?(\\d{4}(R2)?)$", RegexOptions.IgnoreCase);
            if (major.Success)
            {
                MajorVersion = major.Groups[2].Value;
            }
            else
            {
                StopFunction("Incorrect SQL Server version format: use SQL2XXX or just 2XXXX - SQL2012, SQL2008R2");
                return;
            }
            if (!PsOps.IsTrue(ServicePack))
                ServicePack = "RTM";
            Match sp = Regex.Match(ServicePack, "^(SP)?\\s*(\\d+)$", RegexOptions.IgnoreCase);
            if (sp.Success)
            {
                ServicePack = sp.Groups[2].Value == "0" ? "RTM" : "SP" + sp.Groups[2].Value;
            }
            else if (!Regex.IsMatch(ServicePack, "^RTM$", RegexOptions.IgnoreCase))
            {
                StopFunction("Incorrect SQL Server service pack format: use SPX, X or RTM, where X is a service pack number");
                return;
            }
            if (PsOps.IsTrue(CumulativeUpdate))
            {
                Match cu = Regex.Match(CumulativeUpdate!, "^(CU)?\\s*(\\d+)$", RegexOptions.IgnoreCase);
                if (cu.Success)
                {
                    CumulativeUpdate = cu.Groups[2].Value == "0" ? "" : "CU" + cu.Groups[2].Value;
                }
                else
                {
                    StopFunction("Incorrect SQL Server cumulative update format: use CUX or X, where X is a cumulative update number");
                    return;
                }
            }
        }

        // PS: $moduledirectory = $script:PSModuleRoot (module-scope read); try { index }
        // catch { Stop-Function "Error loading SQL build reference"; return }.
        object? moduleDirectory = GetModuleScopeVariable("script:PSModuleRoot");
        try
        {
            using EngineTryScope tryScope = EngineTryScope.Enter(this);
            Collection<PSObject> data = NestedCommand.InvokeScoped(this, IndexScript, moduleDirectory, Update.ToBool(), EnableException.ToBool(), BoundVerbose(), BoundDebug());
            object[] bags = new object[data.Count];
            for (int i = 0; i < data.Count; i++)
                bags[i] = data[i];
            _idxRef = bags;
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            StopFunction("Error loading SQL build reference", errorRecord: StatementFault.Record(ex, "Get-DbaBuild"));
            return;
        }
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        if (SqlInstance is not null)
        {
            foreach (DbaInstanceParameter instance in SqlInstance)
            {
                Hashtable connectParams = new Hashtable();
                connectParams["SqlInstance"] = instance;
                connectParams["SqlCredential"] = SqlCredential;
                NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
                if (!connection.Ok)
                {
                    StopFunction("Failure", target: instance, errorRecord: connection.Failure, category: ErrorCategory.ConnectionError, continueLoop: true);
                    continue;
                }
                Server server = connection.Server!;

                // PS: try { $null = $server.Version.ToString() } catch { Stop-Function ... -Continue }
                try
                {
                    _ = server.Version.ToString();
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    StopFunction("Error occurred while establishing connection to " + PsText(instance), target: instance, errorRecord: StatementFault.Record(ex, "Get-DbaBuild"), category: ErrorCategory.ConnectionError, continueLoop: true);
                    continue;
                }

                RunBranch(InstanceBranchScript, server);
            }
        }

        if (Build is not null)
        {
            foreach (Version buildstr in Build)
                RunBranch(BuildBranchScript, buildstr);
        }

        if (Kb is not null)
        {
            foreach (string kbItem in Kb)
                RunBranch(KbBranchScript, kbItem);
        }

        if (PsOps.IsTrue(MajorVersion))
        {
            RunBranch(MajorBranchScript, MajorVersion, ServicePack, CumulativeUpdate);
        }
    }

    /// <summary>Runs one output branch: Resolve-DbaBuild (verbatim, hop-defined) plus the
    /// branch's exact PSCustomObject/Select-DefaultView literal.</summary>
    private void RunBranch(string script, params object?[] extraArguments)
    {
        object?[] arguments = new object?[4 + extraArguments.Length];
        arguments[0] = _idxRef;
        arguments[1] = EnableException.ToBool();
        arguments[2] = BoundVerbose();
        arguments[3] = BoundDebug();
        Array.Copy(extraArguments, 0, arguments, 4, extraArguments.Length);
        try
        {
            foreach (PSObject? item in NestedCommand.InvokeScoped(this, script, arguments))
                WriteObject(item);
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (RuntimeException ex)
        {
            StatementFault.Surface(this, ex, "Get-DbaBuild");
        }
    }

    /// <summary>Reads a variable off the dbatools script module's SessionState.</summary>
    private object? GetModuleScopeVariable(string variableName)
    {
        Hashtable getModuleParams = new Hashtable();
        getModuleParams["Name"] = "dbatools";
        foreach (PSObject wrapped in NestedCommand.Invoke(this, "Get-Module", getModuleParams))
        {
            if (wrapped?.BaseObject is PSModuleInfo module && module.ModuleType == ModuleType.Script)
                return module.SessionState.PSVariable.GetValue(variableName);
        }
        return null;
    }

    /// <summary>PS string interpolation of a value.</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return PSObject.AsPSObject(value).ToString();
    }

    /// <summary>A bound -Debug carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundDebug()
    {
        object? debug;
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    /// <summary>A bound -Verbose carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundVerbose()
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    private const string IndexScript = """
param($__moduledir, $__update, $EnableException, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__moduledir, $__update, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
        function Get-DbaBuildReferenceIndex {
            [CmdletBinding()]
            param (
                [string]
                $Moduledirectory,

                [bool]
                $Update,

                [bool]
                $EnableException
            )

            # Under some hosted runners (observed: Invoke-ManualPester on PowerShell 5.1,
            # migration tracker row RB-IMP-51) module-scope reads resolve empty mid-run, so
            # both paths fall back defensively instead of dying on a null Join-Path/Resolve-Path.
            if (-not $Moduledirectory) {
                $Moduledirectory = (Get-Module -Name dbatools | Where-Object ModuleType -eq 'Script' | Select-Object -First 1).ModuleBase
            }
            $orig_idxfile = Resolve-Path "$Moduledirectory\bin\dbatools-buildref-index.json"
            $DbatoolsData = Get-DbatoolsConfigValue -Name 'Path.DbatoolsData'
            if (-not $DbatoolsData) {
                $DbatoolsData = [System.IO.Path]::GetTempPath()
            }
            $writable_idxfile = Join-Path $DbatoolsData "dbatools-buildref-index.json"

            if (-not (Test-Path $orig_idxfile)) {
                Write-Message -Level Warning -Message "Unable to read local SQL build reference file. Please check your module integrity or reinstall dbatools."
            }

            if ((-not (Test-Path $orig_idxfile)) -and (-not (Test-Path $writable_idxfile))) {
                throw "Build reference file not found, please check module health."
            }

            # If no writable copy exists, create one and return the module original
            if (-not (Test-Path $writable_idxfile)) {
                Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
                $result = Get-Content $orig_idxfile -Raw | ConvertFrom-Json
            }

            # Else, if both exist, update the writeable if necessary and return the current version
            elseif (Test-Path $orig_idxfile) {
                $module_content = Get-Content $orig_idxfile -Raw | ConvertFrom-Json
                $data_content = Get-Content $writable_idxfile -Raw | ConvertFrom-Json

                $module_time = Get-Date $module_content.LastUpdated
                $data_time = Get-Date $data_content.LastUpdated

                if ($module_time -gt $data_time) {
                    Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
                    $result = $module_content
                } else {
                    $result = $data_content
                }
                # If Update is passed, try to fetch from online resource and store into the writeable
                if ($Update) {
                    Update-DbaBuildReference -EnableException -ErrorAction Stop
                }
            }

            # Else if the module version of the file no longer exists, but the writable version exists, return the writable version
            else {
                $result = Get-Content $writable_idxfile -Raw | ConvertFrom-Json
            }

            $LastUpdated = Get-Date -Date $result.LastUpdated
            if ($LastUpdated -lt (Get-Date).AddDays(-45)) {
                Write-Message -Level Warning -Message "Index is stale, last update on: $(Get-Date -Date $LastUpdated -Format s), try the -Update parameter to fetch the most up to date index"
            }

            $result.Data | Select-Object @{ Name = "VersionObject"; Expression = { [version]$_.Version } }, *
        }
    Get-DbaBuildReferenceIndex -Moduledirectory $__moduledir -Update $__update -EnableException $EnableException
} $__moduledir $__update $EnableException $__boundVerbose $__boundDebug 3>&1
""";

    private const string InstanceBranchScript = """
param($Data, $EnableException, $__boundVerbose, $__boundDebug, $server)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($Data, $EnableException, $__boundVerbose, $__boundDebug, $server)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
        function Resolve-DbaBuild {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            [CmdletBinding()]
            [OutputType([System.Collections.Hashtable])]
            param (
                [Parameter(Mandatory, ParameterSetName = 'Build')]
                [version]
                $Build,

                [Parameter(Mandatory, ParameterSetName = 'KB')]
                [string]
                $Kb,

                [Parameter(Mandatory, ParameterSetName = 'HFLevel')]
                [string]
                $MajorVersion,

                [Parameter(ParameterSetName = 'HFLevel')]
                [string]
                [Alias('SP')]
                $ServicePack = 'RTM',

                [Parameter(ParameterSetName = 'HFLevel')]
                [string]
                [Alias('CU')]
                $CumulativeUpdate,

                $Data,

                [bool]
                $EnableException
            )

            if ($Build) {
                if ($Build.Minor -notin (0, 50)) {
                    Write-Message -Level Debug -Message "Normalized Minor Version to account version aliases"
                    $Build = New-Object -TypeName System.Version -ArgumentList ($Build.Major , ($Build.Minor - $Build.Minor % 10), $Build.Build)
                }
                Write-Message -Level Verbose -Message "Looking for $Build"

                $IdxVersion = $Data | Where-Object Version -Like "$($Build.Major).$($Build.Minor).*"
            } elseif ($Kb) {
                Write-Message -Level Verbose -Message "Looking for KB $Kb"
                if ($Kb -match '^(KB)?(\d+)$') {
                    $currentKb = $Matches[2]
                    $kbVersion = $Data | Where-Object KBList -Contains $currentKb
                    $IdxVersion = $Data | Where-Object Version -Like "$($kbVersion.VersionObject.Major).$($kbVersion.VersionObject.Minor).*"
                } else {
                    Stop-Function -Message "Wrong KB name $kb"
                    return
                }
            } elseif ($MajorVersion) {
                Write-Message -Level Verbose -Message "Looking for SQL $MajorVersion SP $ServicePack CU $CumulativeUpdate"
                $kbVersion = $Data | Where-Object Name -eq $MajorVersion
                $IdxVersion = $Data | Where-Object Version -Like "$($kbVersion.VersionObject.Major).$($kbVersion.VersionObject.Minor).*"
            }

            $Detected = @{ }
            $Detected.MatchType = 'Approximate'
            $idxCount = $IdxVersion | Measure-Object | Select-Object -ExpandProperty Count
            Write-Message -Level Verbose -Message "We have $idxCount builds in store for this Release"
            If ($idxCount -eq 0) {
                Write-Message -Level Warning -Message "No info in store for this Release"
                $Detected.Warning = "No info in store for this Release"
            } else {
                $LastVer = $IdxVersion[0]
            }
            foreach ($el in $IdxVersion) {
                if ($null -ne $el.Name) {
                    $Detected.Name = $el.Name
                }
                if ($Build -and $el.VersionObject -gt $Build) {
                    $Detected.MatchType = 'Approximate'
                    $Detected.Warning = "$Build not found, closest build we have is $($LastVer.Version)"
                    break
                }
                $LastVer = $el
                $Detected.BuildLevel = $el.VersionObject
                if ($null -ne $el.SP) {
                    $Detected.SP = $el.SP
                    $Detected.CU = $null
                }
                if ($null -ne $el.CU) {
                    $Detected.CU = $el.CU
                }
                if ($null -ne $el.SupportedUntil) {
                    $Detected.SupportedUntil = (Get-Date -Date $el.SupportedUntil)
                }
                if ($null -ne $el.ReleaseDate) {
                    $Detected.ReleaseDate = [datetime]$el.ReleaseDate
                }
                $Detected.Build = $el.Version
                $Detected.KB = $el.KBList
                if (($Build -and $el.Version -eq $Build) -or ($Kb -and $el.KBList -eq $currentKb)) {
                    $Detected.MatchType = 'Exact'
                    if ($el.Retired) {
                        $Detected.Warning = "This version has been officially retired by Microsoft"
                    }
                    break
                } elseif ($MajorVersion -and $Detected.SP -contains $ServicePack -and (!$CumulativeUpdate -or ($el.CU -and $el.CU -eq $CumulativeUpdate))) {
                    $Detected.MatchType = 'Exact'
                    if ($el.Retired) {
                        $Detected.Warning = "This version has been officially retired by Microsoft"
                    }
                    break
                }
            }
            return $Detected
        }
    $Detected = Resolve-DbaBuild -Build $server.Version -Data $Data -EnableException $EnableException

    [PSCustomObject]@{
        SqlInstance    = $server.DomainInstanceName
        Build          = $server.Version
        NameLevel      = $Detected.Name
        SPLevel        = $Detected.SP
        CULevel        = $Detected.CU
        KBLevel        = $Detected.KB
        BuildLevel     = $Detected.BuildLevel
        SupportedUntil = $Detected.SupportedUntil
        ReleaseDate    = $Detected.ReleaseDate
        MatchType      = $Detected.MatchType
        Warning        = $Detected.Warning
    }
} $Data $EnableException $__boundVerbose $__boundDebug $server 3>&1
""";

    private const string BuildBranchScript = """
param($Data, $EnableException, $__boundVerbose, $__boundDebug, $buildstr)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($Data, $EnableException, $__boundVerbose, $__boundDebug, $buildstr)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
        function Resolve-DbaBuild {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            [CmdletBinding()]
            [OutputType([System.Collections.Hashtable])]
            param (
                [Parameter(Mandatory, ParameterSetName = 'Build')]
                [version]
                $Build,

                [Parameter(Mandatory, ParameterSetName = 'KB')]
                [string]
                $Kb,

                [Parameter(Mandatory, ParameterSetName = 'HFLevel')]
                [string]
                $MajorVersion,

                [Parameter(ParameterSetName = 'HFLevel')]
                [string]
                [Alias('SP')]
                $ServicePack = 'RTM',

                [Parameter(ParameterSetName = 'HFLevel')]
                [string]
                [Alias('CU')]
                $CumulativeUpdate,

                $Data,

                [bool]
                $EnableException
            )

            if ($Build) {
                if ($Build.Minor -notin (0, 50)) {
                    Write-Message -Level Debug -Message "Normalized Minor Version to account version aliases"
                    $Build = New-Object -TypeName System.Version -ArgumentList ($Build.Major , ($Build.Minor - $Build.Minor % 10), $Build.Build)
                }
                Write-Message -Level Verbose -Message "Looking for $Build"

                $IdxVersion = $Data | Where-Object Version -Like "$($Build.Major).$($Build.Minor).*"
            } elseif ($Kb) {
                Write-Message -Level Verbose -Message "Looking for KB $Kb"
                if ($Kb -match '^(KB)?(\d+)$') {
                    $currentKb = $Matches[2]
                    $kbVersion = $Data | Where-Object KBList -Contains $currentKb
                    $IdxVersion = $Data | Where-Object Version -Like "$($kbVersion.VersionObject.Major).$($kbVersion.VersionObject.Minor).*"
                } else {
                    Stop-Function -Message "Wrong KB name $kb"
                    return
                }
            } elseif ($MajorVersion) {
                Write-Message -Level Verbose -Message "Looking for SQL $MajorVersion SP $ServicePack CU $CumulativeUpdate"
                $kbVersion = $Data | Where-Object Name -eq $MajorVersion
                $IdxVersion = $Data | Where-Object Version -Like "$($kbVersion.VersionObject.Major).$($kbVersion.VersionObject.Minor).*"
            }

            $Detected = @{ }
            $Detected.MatchType = 'Approximate'
            $idxCount = $IdxVersion | Measure-Object | Select-Object -ExpandProperty Count
            Write-Message -Level Verbose -Message "We have $idxCount builds in store for this Release"
            If ($idxCount -eq 0) {
                Write-Message -Level Warning -Message "No info in store for this Release"
                $Detected.Warning = "No info in store for this Release"
            } else {
                $LastVer = $IdxVersion[0]
            }
            foreach ($el in $IdxVersion) {
                if ($null -ne $el.Name) {
                    $Detected.Name = $el.Name
                }
                if ($Build -and $el.VersionObject -gt $Build) {
                    $Detected.MatchType = 'Approximate'
                    $Detected.Warning = "$Build not found, closest build we have is $($LastVer.Version)"
                    break
                }
                $LastVer = $el
                $Detected.BuildLevel = $el.VersionObject
                if ($null -ne $el.SP) {
                    $Detected.SP = $el.SP
                    $Detected.CU = $null
                }
                if ($null -ne $el.CU) {
                    $Detected.CU = $el.CU
                }
                if ($null -ne $el.SupportedUntil) {
                    $Detected.SupportedUntil = (Get-Date -Date $el.SupportedUntil)
                }
                if ($null -ne $el.ReleaseDate) {
                    $Detected.ReleaseDate = [datetime]$el.ReleaseDate
                }
                $Detected.Build = $el.Version
                $Detected.KB = $el.KBList
                if (($Build -and $el.Version -eq $Build) -or ($Kb -and $el.KBList -eq $currentKb)) {
                    $Detected.MatchType = 'Exact'
                    if ($el.Retired) {
                        $Detected.Warning = "This version has been officially retired by Microsoft"
                    }
                    break
                } elseif ($MajorVersion -and $Detected.SP -contains $ServicePack -and (!$CumulativeUpdate -or ($el.CU -and $el.CU -eq $CumulativeUpdate))) {
                    $Detected.MatchType = 'Exact'
                    if ($el.Retired) {
                        $Detected.Warning = "This version has been officially retired by Microsoft"
                    }
                    break
                }
            }
            return $Detected
        }
    $Detected = Resolve-DbaBuild -Build $buildstr -Data $Data -EnableException $EnableException

    [PSCustomObject]@{
        SqlInstance    = $null
        Build          = $buildstr
        NameLevel      = $Detected.Name
        SPLevel        = $Detected.SP
        CULevel        = $Detected.CU
        KBLevel        = $Detected.KB
        BuildLevel     = $Detected.BuildLevel
        SupportedUntil = $Detected.SupportedUntil
        ReleaseDate    = $Detected.ReleaseDate
        MatchType      = $Detected.MatchType
        Warning        = $Detected.Warning
    } | Select-DefaultView -ExcludeProperty SqlInstance
} $Data $EnableException $__boundVerbose $__boundDebug $buildstr 3>&1
""";

    private const string KbBranchScript = """
param($Data, $EnableException, $__boundVerbose, $__boundDebug, $kbItem)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($Data, $EnableException, $__boundVerbose, $__boundDebug, $kbItem)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
        function Resolve-DbaBuild {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            [CmdletBinding()]
            [OutputType([System.Collections.Hashtable])]
            param (
                [Parameter(Mandatory, ParameterSetName = 'Build')]
                [version]
                $Build,

                [Parameter(Mandatory, ParameterSetName = 'KB')]
                [string]
                $Kb,

                [Parameter(Mandatory, ParameterSetName = 'HFLevel')]
                [string]
                $MajorVersion,

                [Parameter(ParameterSetName = 'HFLevel')]
                [string]
                [Alias('SP')]
                $ServicePack = 'RTM',

                [Parameter(ParameterSetName = 'HFLevel')]
                [string]
                [Alias('CU')]
                $CumulativeUpdate,

                $Data,

                [bool]
                $EnableException
            )

            if ($Build) {
                if ($Build.Minor -notin (0, 50)) {
                    Write-Message -Level Debug -Message "Normalized Minor Version to account version aliases"
                    $Build = New-Object -TypeName System.Version -ArgumentList ($Build.Major , ($Build.Minor - $Build.Minor % 10), $Build.Build)
                }
                Write-Message -Level Verbose -Message "Looking for $Build"

                $IdxVersion = $Data | Where-Object Version -Like "$($Build.Major).$($Build.Minor).*"
            } elseif ($Kb) {
                Write-Message -Level Verbose -Message "Looking for KB $Kb"
                if ($Kb -match '^(KB)?(\d+)$') {
                    $currentKb = $Matches[2]
                    $kbVersion = $Data | Where-Object KBList -Contains $currentKb
                    $IdxVersion = $Data | Where-Object Version -Like "$($kbVersion.VersionObject.Major).$($kbVersion.VersionObject.Minor).*"
                } else {
                    Stop-Function -Message "Wrong KB name $kb"
                    return
                }
            } elseif ($MajorVersion) {
                Write-Message -Level Verbose -Message "Looking for SQL $MajorVersion SP $ServicePack CU $CumulativeUpdate"
                $kbVersion = $Data | Where-Object Name -eq $MajorVersion
                $IdxVersion = $Data | Where-Object Version -Like "$($kbVersion.VersionObject.Major).$($kbVersion.VersionObject.Minor).*"
            }

            $Detected = @{ }
            $Detected.MatchType = 'Approximate'
            $idxCount = $IdxVersion | Measure-Object | Select-Object -ExpandProperty Count
            Write-Message -Level Verbose -Message "We have $idxCount builds in store for this Release"
            If ($idxCount -eq 0) {
                Write-Message -Level Warning -Message "No info in store for this Release"
                $Detected.Warning = "No info in store for this Release"
            } else {
                $LastVer = $IdxVersion[0]
            }
            foreach ($el in $IdxVersion) {
                if ($null -ne $el.Name) {
                    $Detected.Name = $el.Name
                }
                if ($Build -and $el.VersionObject -gt $Build) {
                    $Detected.MatchType = 'Approximate'
                    $Detected.Warning = "$Build not found, closest build we have is $($LastVer.Version)"
                    break
                }
                $LastVer = $el
                $Detected.BuildLevel = $el.VersionObject
                if ($null -ne $el.SP) {
                    $Detected.SP = $el.SP
                    $Detected.CU = $null
                }
                if ($null -ne $el.CU) {
                    $Detected.CU = $el.CU
                }
                if ($null -ne $el.SupportedUntil) {
                    $Detected.SupportedUntil = (Get-Date -Date $el.SupportedUntil)
                }
                if ($null -ne $el.ReleaseDate) {
                    $Detected.ReleaseDate = [datetime]$el.ReleaseDate
                }
                $Detected.Build = $el.Version
                $Detected.KB = $el.KBList
                if (($Build -and $el.Version -eq $Build) -or ($Kb -and $el.KBList -eq $currentKb)) {
                    $Detected.MatchType = 'Exact'
                    if ($el.Retired) {
                        $Detected.Warning = "This version has been officially retired by Microsoft"
                    }
                    break
                } elseif ($MajorVersion -and $Detected.SP -contains $ServicePack -and (!$CumulativeUpdate -or ($el.CU -and $el.CU -eq $CumulativeUpdate))) {
                    $Detected.MatchType = 'Exact'
                    if ($el.Retired) {
                        $Detected.Warning = "This version has been officially retired by Microsoft"
                    }
                    break
                }
            }
            return $Detected
        }
    $Detected = Resolve-DbaBuild -Kb $kbItem -Data $Data -EnableException $EnableException

    [PSCustomObject]@{
        SqlInstance    = $null
        Build          = $Detected.Build
        NameLevel      = $Detected.Name
        SPLevel        = $Detected.SP
        CULevel        = $Detected.CU
        KBLevel        = $Detected.KB
        BuildLevel     = $Detected.BuildLevel
        SupportedUntil = $Detected.SupportedUntil
        ReleaseDate    = $Detected.ReleaseDate
        MatchType      = $Detected.MatchType
        Warning        = $Detected.Warning
    } | Select-DefaultView -ExcludeProperty SqlInstance
} $Data $EnableException $__boundVerbose $__boundDebug $kbItem 3>&1
""";

    private const string MajorBranchScript = """
param($Data, $EnableException, $__boundVerbose, $__boundDebug, $MajorVersion, $ServicePack, $CumulativeUpdate)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($Data, $EnableException, $__boundVerbose, $__boundDebug, $MajorVersion, $ServicePack, $CumulativeUpdate)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
        function Resolve-DbaBuild {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
            [CmdletBinding()]
            [OutputType([System.Collections.Hashtable])]
            param (
                [Parameter(Mandatory, ParameterSetName = 'Build')]
                [version]
                $Build,

                [Parameter(Mandatory, ParameterSetName = 'KB')]
                [string]
                $Kb,

                [Parameter(Mandatory, ParameterSetName = 'HFLevel')]
                [string]
                $MajorVersion,

                [Parameter(ParameterSetName = 'HFLevel')]
                [string]
                [Alias('SP')]
                $ServicePack = 'RTM',

                [Parameter(ParameterSetName = 'HFLevel')]
                [string]
                [Alias('CU')]
                $CumulativeUpdate,

                $Data,

                [bool]
                $EnableException
            )

            if ($Build) {
                if ($Build.Minor -notin (0, 50)) {
                    Write-Message -Level Debug -Message "Normalized Minor Version to account version aliases"
                    $Build = New-Object -TypeName System.Version -ArgumentList ($Build.Major , ($Build.Minor - $Build.Minor % 10), $Build.Build)
                }
                Write-Message -Level Verbose -Message "Looking for $Build"

                $IdxVersion = $Data | Where-Object Version -Like "$($Build.Major).$($Build.Minor).*"
            } elseif ($Kb) {
                Write-Message -Level Verbose -Message "Looking for KB $Kb"
                if ($Kb -match '^(KB)?(\d+)$') {
                    $currentKb = $Matches[2]
                    $kbVersion = $Data | Where-Object KBList -Contains $currentKb
                    $IdxVersion = $Data | Where-Object Version -Like "$($kbVersion.VersionObject.Major).$($kbVersion.VersionObject.Minor).*"
                } else {
                    Stop-Function -Message "Wrong KB name $kb"
                    return
                }
            } elseif ($MajorVersion) {
                Write-Message -Level Verbose -Message "Looking for SQL $MajorVersion SP $ServicePack CU $CumulativeUpdate"
                $kbVersion = $Data | Where-Object Name -eq $MajorVersion
                $IdxVersion = $Data | Where-Object Version -Like "$($kbVersion.VersionObject.Major).$($kbVersion.VersionObject.Minor).*"
            }

            $Detected = @{ }
            $Detected.MatchType = 'Approximate'
            $idxCount = $IdxVersion | Measure-Object | Select-Object -ExpandProperty Count
            Write-Message -Level Verbose -Message "We have $idxCount builds in store for this Release"
            If ($idxCount -eq 0) {
                Write-Message -Level Warning -Message "No info in store for this Release"
                $Detected.Warning = "No info in store for this Release"
            } else {
                $LastVer = $IdxVersion[0]
            }
            foreach ($el in $IdxVersion) {
                if ($null -ne $el.Name) {
                    $Detected.Name = $el.Name
                }
                if ($Build -and $el.VersionObject -gt $Build) {
                    $Detected.MatchType = 'Approximate'
                    $Detected.Warning = "$Build not found, closest build we have is $($LastVer.Version)"
                    break
                }
                $LastVer = $el
                $Detected.BuildLevel = $el.VersionObject
                if ($null -ne $el.SP) {
                    $Detected.SP = $el.SP
                    $Detected.CU = $null
                }
                if ($null -ne $el.CU) {
                    $Detected.CU = $el.CU
                }
                if ($null -ne $el.SupportedUntil) {
                    $Detected.SupportedUntil = (Get-Date -Date $el.SupportedUntil)
                }
                if ($null -ne $el.ReleaseDate) {
                    $Detected.ReleaseDate = [datetime]$el.ReleaseDate
                }
                $Detected.Build = $el.Version
                $Detected.KB = $el.KBList
                if (($Build -and $el.Version -eq $Build) -or ($Kb -and $el.KBList -eq $currentKb)) {
                    $Detected.MatchType = 'Exact'
                    if ($el.Retired) {
                        $Detected.Warning = "This version has been officially retired by Microsoft"
                    }
                    break
                } elseif ($MajorVersion -and $Detected.SP -contains $ServicePack -and (!$CumulativeUpdate -or ($el.CU -and $el.CU -eq $CumulativeUpdate))) {
                    $Detected.MatchType = 'Exact'
                    if ($el.Retired) {
                        $Detected.Warning = "This version has been officially retired by Microsoft"
                    }
                    break
                }
            }
            return $Detected
        }
    $Detected = Resolve-DbaBuild -MajorVersion $MajorVersion -ServicePack $ServicePack -CumulativeUpdate $CumulativeUpdate -Data $Data -EnableException $EnableException

    [PSCustomObject]@{
        SqlInstance    = $null
        Build          = $Detected.Build
        NameLevel      = $Detected.Name
        SPLevel        = $Detected.SP
        CULevel        = $Detected.CU
        KBLevel        = $Detected.KB
        BuildLevel     = $Detected.BuildLevel
        SupportedUntil = $Detected.SupportedUntil
        ReleaseDate    = $Detected.ReleaseDate
        MatchType      = $Detected.MatchType
        Warning        = $Detected.Warning
    } | Select-DefaultView -ExcludeProperty SqlInstance
} $Data $EnableException $__boundVerbose $__boundDebug $MajorVersion $ServicePack $CumulativeUpdate 3>&1
""";

}
