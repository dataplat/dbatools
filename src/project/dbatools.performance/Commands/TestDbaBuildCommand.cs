#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests SQL Server build compliance. Port of public/Test-DbaBuild.ps1 (W1-124).
/// BeginProcessing performs the source's bound-parameter exclusivity and grammar parsing
/// once. Parsed policy objects and the lazily loaded build-reference index are private
/// carriers across ProcessRecord calls, preserving the advanced-function begin/process
/// lifetime while the comparison engine remains in module-scoped PowerShell for exact
/// filtering, coercion, warning, decoration, and default-view semantics. Surface pinned by
/// migration/baselines/Test-DbaBuild.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaBuild")]
public sealed class TestDbaBuildCommand : DbaBaseCmdlet
{
    /// <summary>Build versions to test without connecting to SQL Server.</summary>
    [Parameter(Position = 0)]
    public Version[]? Build { get; set; }

    /// <summary>Minimum compliant build.</summary>
    [Parameter(Position = 1)]
    public Version? MinimumBuild { get; set; }

    /// <summary>Maximum acceptable SP/CU lag.</summary>
    [Parameter(Position = 2)]
    public string? MaxBehind { get; set; }

    /// <summary>Maximum acceptable build age.</summary>
    [Parameter(Position = 3)]
    public string? MaxTimeBehind { get; set; }

    /// <summary>Require the latest known build.</summary>
    [Parameter]
    public SwitchParameter Latest { get; set; }

    /// <summary>SQL Server instances whose builds should be tested.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative SQL Server credential.</summary>
    [Parameter(Position = 5)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Update build-reference data before testing.</summary>
    [Parameter]
    public SwitchParameter Update { get; set; }

    /// <summary>Emit only Boolean compliance values.</summary>
    [Parameter]
    public SwitchParameter Quiet { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _parsedMaxBehind;
    private object? _parsedMaxTimeBehind;
    private object? _indexReference;

    // PS: $BuildVersions is branch-assigned ($Build / $SqlInstance) but read UNCONDITIONALLY
    // by the foreach - at FUNCTION scope a record binding neither re-reads the PREVIOUS
    // record's builds. Carried like $IdxRef two lines above it (DEF-008 re-open #3).
    private object? _buildVersions;
    private bool _skipProcessing;

    protected override void BeginProcessing()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (IsCarrier(item, BeginCarrierMarker))
            {
                _skipProcessing = LanguagePrimitives.IsTrue(item!.Properties["SkipProcessing"]?.Value);
                _parsedMaxBehind = item.Properties["ParsedMaxBehind"]?.Value;
                _parsedMaxTimeBehind = item.Properties["ParsedMaxTimeBehind"]?.Value;
            }
            else
            {
                WriteObject(item);
            }
        }, BeginScript,
            MaxBehind, MaxTimeBehind,
            TestBound("MinimumBuild"), TestBound("MaxBehind"),
            TestBound("MaxTimeBehind"), TestBound("Latest"),
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        if (_skipProcessing)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            Build, MinimumBuild, MaxBehind, MaxTimeBehind, Latest.ToBool(),
            SqlInstance, SqlCredential, Update.ToBool(), Quiet.ToBool(),
            EnableException.ToBool(), _parsedMaxBehind, _parsedMaxTimeBehind,
            _indexReference, _buildVersions, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (IsCarrier(item, ProcessCarrierMarker))
            {
                _indexReference = item!.Properties["IndexReference"]?.Value;
                _buildVersions = item.Properties["BuildVersions"]?.Value;
            }
            else
            {
                WriteObject(item);
            }
        }
    }

    private static bool IsCarrier(PSObject? item, string marker)
    {
        return item?.Properties[marker] is not null &&
               LanguagePrimitives.IsTrue(item.Properties[marker].Value);
    }

    private const string BeginCarrierMarker = "__dbatoolsTbBeginCarrier";
    private const string ProcessCarrierMarker = "__dbatoolsTbProcessCarrier";

    private const string BeginScript = """
param($MaxBehind, $MaxTimeBehind, $__minimumBuildBound, $__maxBehindBound, $__maxTimeBehindBound, $__latestBound, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($MaxBehind, $MaxTimeBehind, $__minimumBuildBound, $__maxBehindBound, $__maxTimeBehindBound, $__latestBound, $EnableException)

    $ComplianceSpec = @()
    if ($__minimumBuildBound) { $ComplianceSpec += 'MinimumBuild' }
    if ($__maxBehindBound) { $ComplianceSpec += 'MaxBehind' }
    if ($__maxTimeBehindBound) { $ComplianceSpec += 'MaxTimeBehind' }
    if ($__latestBound) { $ComplianceSpec += 'Latest' }
    if ($ComplianceSpec.Length -gt 1) {
        Stop-Function -Category InvalidArgument -Message "-MinimumBuild, -MaxBehind, -MaxTimeBehind and -Latest are mutually exclusive. Please choose only one. Quitting." -FunctionName Test-DbaBuild
        [pscustomobject]@{ __dbatoolsTbBeginCarrier = $true; SkipProcessing = $true; ParsedMaxBehind = $null; ParsedMaxTimeBehind = $null }
        return
    }
    if ($ComplianceSpec.Length -eq 0) {
        Stop-Function -Category InvalidArgument -Message "You need to choose one from -MinimumBuild, -MaxBehind, -MaxTimeBehind and -Latest. Quitting." -FunctionName Test-DbaBuild
        [pscustomobject]@{ __dbatoolsTbBeginCarrier = $true; SkipProcessing = $true; ParsedMaxBehind = $null; ParsedMaxTimeBehind = $null }
        return
    }

    $ParsedMaxBehind = $null
    if ($MaxBehind) {
        $MaxBehindValidator = [regex]'^(?<howmany>[\d]+)(?<what>SP|CU)$'
        $pieces = $MaxBehind.Split(' ') | Where-Object { $_ }
        try {
            $ParsedMaxBehind = @{ }
            foreach ($piece in $pieces) {
                $pieceMatch = $MaxBehindValidator.Match($piece)
                if ($pieceMatch.Success -ne $true) {
                    Stop-Function -Message "MaxBehind has an invalid syntax ('$piece' could not be parsed correctly)" -ErrorRecord $_ -FunctionName Test-DbaBuild
                    [pscustomobject]@{ __dbatoolsTbBeginCarrier = $true; SkipProcessing = $true; ParsedMaxBehind = $ParsedMaxBehind; ParsedMaxTimeBehind = $null }
                    return
                } else {
                    $howmany = [int]$pieceMatch.Groups['howmany'].Value
                    $what = $pieceMatch.Groups['what'].Value
                    if ($ParsedMaxBehind.ContainsKey($what)) {
                        Stop-Function -Message "The specifier $what has been already passed" -ErrorRecord $_ -FunctionName Test-DbaBuild
                        [pscustomobject]@{ __dbatoolsTbBeginCarrier = $true; SkipProcessing = $true; ParsedMaxBehind = $ParsedMaxBehind; ParsedMaxTimeBehind = $null }
                        return
                    } else {
                        $ParsedMaxBehind[$what] = $howmany
                    }
                }
            }
            if (-not $ParsedMaxBehind.ContainsKey('SP')) {
                $ParsedMaxBehind['SP'] = 0
            }
        } catch {
            Stop-Function -Message "Error parsing MaxBehind" -ErrorRecord $_ -FunctionName Test-DbaBuild
            [pscustomobject]@{ __dbatoolsTbBeginCarrier = $true; SkipProcessing = $true; ParsedMaxBehind = $ParsedMaxBehind; ParsedMaxTimeBehind = $null }
            return
        }
    }

    $ParsedMaxTimeBehind = $null
    if ($MaxTimeBehind) {
        $MaxTimeBehindValidator = [regex]'^(?<howmany>[\d]+)(?<what>Mo|D)$'
        $timePieceMatch = $MaxTimeBehindValidator.Match($MaxTimeBehind)
        if (-not $timePieceMatch.Success) {
            Stop-Function -Category InvalidArgument -Message "MaxTimeBehind has an invalid syntax ('$MaxTimeBehind' could not be parsed). Use formats like '6Mo' for months or '180D' for days." -FunctionName Test-DbaBuild
            [pscustomobject]@{ __dbatoolsTbBeginCarrier = $true; SkipProcessing = $true; ParsedMaxBehind = $ParsedMaxBehind; ParsedMaxTimeBehind = $null }
            return
        }
        $ParsedMaxTimeBehind = @{
            HowMany = [int]$timePieceMatch.Groups['howmany'].Value
            What    = $timePieceMatch.Groups['what'].Value
        }
    }

    [pscustomobject]@{ __dbatoolsTbBeginCarrier = $true; SkipProcessing = $false; ParsedMaxBehind = $ParsedMaxBehind; ParsedMaxTimeBehind = $ParsedMaxTimeBehind }
} $MaxBehind $MaxTimeBehind $__minimumBuildBound $__maxBehindBound $__maxTimeBehindBound $__latestBound $EnableException @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($Build, $MinimumBuild, $MaxBehind, $MaxTimeBehind, $Latest, $SqlInstance, $SqlCredential, $Update, $Quiet, $EnableException, $ParsedMaxBehind, $ParsedMaxTimeBehind, $IdxRef, $BuildVersions, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($Build, $MinimumBuild, $MaxBehind, $MaxTimeBehind, $Latest, $SqlInstance, $SqlCredential, $Update, $Quiet, $EnableException, $ParsedMaxBehind, $ParsedMaxTimeBehind, $IdxRef, $BuildVersions)

    function Get-DbaBuildReferenceIndex {
        [CmdletBinding()]
        $DbatoolsData = Get-DbatoolsConfigValue -Name 'Path.DbatoolsData'
        $writable_idxfile = Join-Path $DbatoolsData "dbatools-buildref-index.json"
        $result = Get-Content $writable_idxfile -Raw | ConvertFrom-Json
        $result.Data | Select-Object @{ Name = "VersionObject"; Expression = { [version]$_.Version } }, *
    }

    if (Test-FunctionInterrupt) {
        [pscustomobject]@{ __dbatoolsTbProcessCarrier = $true; IndexReference = $IdxRef; BuildVersions = $BuildVersions }
        return
    }
    $hiddenProps = @()
    if (-not $SqlInstance) {
        $hiddenProps += 'SqlInstance'
    }
    if ($MinimumBuild) {
        $hiddenProps += 'MaxBehind', 'MaxTimeBehind', 'SPTarget', 'CUTarget', 'BuildTarget'
    } elseif ($MaxBehind -or $Latest) {
        $hiddenProps += 'MinimumBuild', 'MaxTimeBehind'
    } elseif ($MaxTimeBehind) {
        $hiddenProps += 'MinimumBuild', 'MaxBehind', 'SPTarget', 'CUTarget'
    }
    if ($Build) {
        $BuildVersions = Get-DbaBuild -Build $Build -Update:$Update -EnableException:$EnableException
    } elseif ($SqlInstance) {
        $BuildVersions = Get-DbaBuild -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Update:$Update -EnableException:$EnableException
    }
    # Moving it down here to only trigger after -Update was properly called
    if (!$IdxRef) {
        try {
            $IdxRef = Get-DbaBuildReferenceIndex
        } catch {
            Stop-Function -Message "Error loading SQL build reference" -ErrorRecord $_ -FunctionName Test-DbaBuild
            [pscustomobject]@{ __dbatoolsTbProcessCarrier = $true; IndexReference = $IdxRef; BuildVersions = $BuildVersions }
            return
        }
    }
    foreach ($BuildVersion in $BuildVersions) {
        $inputbuild = $BuildVersion.Build
        $compliant = $false
        $targetSPName = $null
        $targetCUName = $null
        $buildRefEntry = $IdxRef | Where-Object VersionObject -eq $inputbuild
        if ($BuildVersion.MatchType -eq 'Approximate') {
            Write-Message -Level Warning -Message "$($BuildVersion.Build) is not recognized as a correct version" -FunctionName Test-DbaBuild -ModuleName "dbatools"
        }
        if ($MinimumBuild) {
            Write-Message -Level Debug -Message "Comparing $MinimumBuild to $inputbuild" -FunctionName Test-DbaBuild -ModuleName "dbatools"
            if ($inputbuild -ge $MinimumBuild) {
                $compliant = $true
            }
        } elseif ($MaxBehind -or $Latest) {
            $buildAnchor = "$($inputbuild.Major).$($inputbuild.Minor).*"
            if ($inputbuild.Minor -notin (0, 50)) {
                $buildAnchor = "$($inputbuild.Major).$($inputbuild.Minor - $inputbuild.Minor % 10).*"
                Write-Message -Level Debug -Message "Normalized Minor Version to account version aliases" -FunctionName Test-DbaBuild -ModuleName "dbatools"
            }
            $IdxVersion = $IdxRef | Where-Object Version -Like $buildAnchor
            $lastsp = ''
            $SPsAndCUs = @()
            foreach ($el in $IdxVersion) {
                if ($null -ne $el.SP) {
                    $lastsp = $el.SP | Where-Object { $_ -ne 'LATEST' }
                    $SPsAndCUs += @{
                        VersionObject = $el.VersionObject
                        SP            = $lastsp
                    }
                }
                if ($null -ne $el.CU) {
                    $SPsAndCUs += @{
                        VersionObject = $el.VersionObject
                        SP            = $lastsp
                        CU            = $el.CU
                        Retired       = $el.Retired
                    }
                }
            }
            $targetedBuild = $SPsAndCUs[0]
            if ($Latest) {
                $targetedBuild = $IdxVersion[$IdxVersion.Length - 1]
            } else {
                if ($ParsedMaxBehind.ContainsKey('SP')) {
                    [string[]]$AllSPs = $SPsAndCUs.SP | Select-Object -Unique
                    $targetSP = $AllSPs.Length - $ParsedMaxBehind['SP'] - 1
                    if ($targetSP -lt 0) {
                        $targetSP = 0
                    }
                    $targetSPName = $AllSPs[$targetSP]
                    Write-Message -Level Debug -Message "Target SP is $targetSPName - $targetSP on $($AllSPs.Length)" -FunctionName Test-DbaBuild -ModuleName "dbatools"
                    $targetedBuild = $SPsAndCUs | Where-Object SP -eq $targetSPName | Select-Object -First 1
                }
                if ($ParsedMaxBehind.ContainsKey('CU')) {
                    [string[]]$AllCUs = ($SPsAndCUs | Where-Object VersionObject -GT $targetedBuild.VersionObject | Where-Object Retired -ne $true).CU | Select-Object -Unique
                    if ($AllCUs.Length -gt 0) {
                        # CU after the targeted build available
                        $targetCU = $AllCUs.Length - $ParsedMaxBehind['CU'] - 1
                        if ($targetCU -lt 0) {
                            $targetCU = 0
                        }
                        $targetCUName = $AllCUs[$targetCU]
                        Write-Message -Level Debug -Message "Target CU is $targetCUName - $targetCU on $($AllCUs.Length)" -FunctionName Test-DbaBuild -ModuleName "dbatools"
                        $targetedBuild = $SPsAndCUs | Where-Object VersionObject -gt $targetedBuild.VersionObject | Where-Object CU -eq $targetCUName | Select-Object -First 1
                    }
                }
            }
            if ($inputbuild -ge $targetedBuild.VersionObject) {
                $compliant = $true
            }
        } elseif ($MaxTimeBehind) {
            $buildAnchor = "$($inputbuild.Major).$($inputbuild.Minor).*"
            if ($inputbuild.Minor -notin (0, 50)) {
                $buildAnchor = "$($inputbuild.Major).$($inputbuild.Minor - $inputbuild.Minor % 10).*"
                Write-Message -Level Debug -Message "Normalized Minor Version to account version aliases" -FunctionName Test-DbaBuild -ModuleName "dbatools"
            }
            $IdxVersion = $IdxRef | Where-Object Version -Like $buildAnchor
            $today = (Get-Date).Date
            if ($ParsedMaxTimeBehind.What -eq "Mo") {
                $cutoffDate = $today.AddMonths(-$ParsedMaxTimeBehind.HowMany)
            } else {
                $cutoffDate = $today.AddDays(-$ParsedMaxTimeBehind.HowMany)
            }
            $targetedBuild = $IdxVersion | Where-Object { $_.ReleaseDate -and [datetime]$_.ReleaseDate -ge $cutoffDate } | Select-Object -First 1
            $currentBuildEntry = $IdxVersion | Where-Object VersionObject -eq $inputbuild
            if (-not $currentBuildEntry -or -not $currentBuildEntry.ReleaseDate) {
                Write-Message -Level Warning -Message "No ReleaseDate found for build $inputbuild - cannot determine time-based compliance" -FunctionName Test-DbaBuild -ModuleName "dbatools"
                $compliant = $false
            } else {
                $compliant = ([datetime]$currentBuildEntry.ReleaseDate -ge $cutoffDate)
            }
        }
        Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name Compliant -Value $compliant
        Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name MinimumBuild -Value $MinimumBuild
        Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name MaxBehind -Value $MaxBehind
        Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name MaxTimeBehind -Value $MaxTimeBehind
        Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name SPTarget -Value $targetSPName
        Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name CUTarget -Value $targetCUName
        Add-Member -InputObject $BuildVersion -MemberType NoteProperty -Name BuildTarget -Value $targetedBuild.VersionObject
        if ($Quiet) {
            $BuildVersion.Compliant
        } else {
            $BuildVersion | Select-Object * | Select-DefaultView -ExcludeProperty $hiddenProps
        }
    }
    [pscustomobject]@{ __dbatoolsTbProcessCarrier = $true; IndexReference = $IdxRef; BuildVersions = $BuildVersions }
} $Build $MinimumBuild $MaxBehind $MaxTimeBehind $Latest $SqlInstance $SqlCredential $Update $Quiet $EnableException $ParsedMaxBehind $ParsedMaxTimeBehind $IdxRef $BuildVersions @__commonParameters 3>&1 2>&1
""";
}
