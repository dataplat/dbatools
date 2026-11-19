#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests whether the required SPNs for an availability group's listeners are registered.
/// Port of public/Test-DbaAgSpn.ps1; surface pinned by
/// migration/baselines/Test-DbaAgSpn.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaAgSpn")]
public sealed class TestDbaAgSpnCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance or instances hosting the availability group.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Credentials used for the Active Directory SPN lookups.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    /// <summary>The availability group or groups to test.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? AvailabilityGroup { get; set; }

    /// <summary>Restrict the test to specific listener name(s).</summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? Listener { get; set; }

    /// <summary>Availability group objects piped from Get-DbaAvailabilityGroup.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop for a read-only command ([CmdletBinding()], NO ShouldProcess: no
        // transplant, no gate). The source has a begin{} block AND a process{} block, but the begin
        // block is trivial ($resultCache = @{}; $spns = @()), so instead of a separate begin-hop it
        // is replicated inside the process-hop's SEED: on the first record (no carried state) the
        // two are initialized empty exactly as begin{} does; on later records they are restored from
        // the carried sentinel.
        //
        // THREE cross-record carries - this row's crux, and only the first was caught by the
        // detector:
        //   $resultCache (begin :105) - the AD-lookup memo, explicitly cross-record ("spare the
        //     cmdlet to search for the same account over and over"). Restored-or-initialized.
        //   $spns (begin :106) - the accumulator. `$spns +=` at :144/:161 then `foreach ($spn in
        //     $spns)` at :180 walks the FULL set, so because $spns is begin-scoped it ACCUMULATES
        //     across records and RE-EMITS earlier records' SPNs every subsequent record. Very likely
        //     a latent source bug, but a faithful port MUST preserve it - so it is carried, not
        //     reset per record. Restored-or-initialized.
        //   $result (process-scoped, assigned :197 in a TRY / :205 in else, READ at :207) - if the
        //     :197 Get-DbaADObject throws (caught, catch does NOT assign $result), :207 reads the
        //     PREVIOUS iteration's/record's $result. This is the W4-055 $perm PER-BRANCH stale read
        //     the detector misses (source order says assigned at :197). Carried to stay bug-for-bug;
        //     NOT begin-initialized (matches the source, which leaves it undefined until first set).
        //
        // UNDEFINED VAR preserved (W4-054 class, NOT carried): $resolved at :185 is never assigned
        // anywhere and resolves to $null in both worlds via the same module scope. Only reached on
        // the LocalSystem/NT-SERVICE virtual-account branch.
        //
        // TWO bound flags for the guard at :109 (positional multi-name -Not over SqlInstance,
        // InputObject) -> -not ($__boundSqlInstance -or $__boundInputObject).
        //
        // T8/DEF-002 EXPOSURE (shared-runtime, blocked on A, escalated): AvailabilityGroup and
        // Listener are [string[]] flowing to called cmdlets; DEF-001 buffered-output is weaker here
        // (read-only; the AD lookup's own try/catch swallows the -EnableException throw at :199).
        // DEF-001 closed via InvokeScopedStreaming (ab7492c); read-only so no WhatIf interaction.
        // The three-var carry sentinel rides the callback as the last emitted item, unchanged.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4065State"))
            {
                _state = sentinel["__w4065State"] as Hashtable;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Credential, AvailabilityGroup, Listener, InputObject,
            EnableException.ToBool(),
            TestBound(nameof(SqlInstance)), TestBound(nameof(InputObject)),
            _state,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 109-227 (extracted programmatically) after stripping the Stop-Function -FunctionName
    // append, reversing the single Test-Bound rewrite (the guard at :109), and reversing the 9
    // direct-Write-Message DEF-006 rewrites (each carries a # SOURCE: marker; -FunctionName +
    // -ModuleName "dbatools" so the anonymous hop stamps the command/module as the function world
    // does). The source's inline comments
    // (the GetHostEntry note, the "spare the cmdlet" note, the virtual-account notes) ride
    // untouched, as does the undefined $resolved at :185. The seed block replicates begin{} for
    // record 1 and restores the three carries thereafter; the harvest re-exports them. The
    // dot-block preserves the guard's early return at :111.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Credential, $AvailabilityGroup, $Listener, $InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__state, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [PSCredential]$Credential, [string[]]$AvailabilityGroup, [string[]]$Listener, [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject, $EnableException, $__boundSqlInstance, $__boundInputObject, $__state, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # SEED the three cross-record carries. $resultCache and $spns replicate the source begin{} block
    # (:105-106) on the first record and are restored from the carried sentinel thereafter. $result
    # is NOT begin-initialized in the source (it stays undefined until first assigned), so it is only
    # restored when carried - preserving the per-branch stale read at :207.
    if ($null -ne $__state -and $__state.ContainsKey('resultCache')) { $resultCache = $__state.resultCache } else { $resultCache = @{ } }
    if ($null -ne $__state -and $__state.ContainsKey('spns')) { $spns = $__state.spns } else { $spns = @() }
    if ($null -ne $__state -and $__state.ContainsKey('result')) { $result = $__state.result }

    . {
        if (-not ($__boundSqlInstance -or $__boundInputObject)) { # SOURCE: if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object" -FunctionName Test-DbaAgSpn
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -AvailabilityGroup $AvailabilityGroup -SqlCredential $SqlCredential -EnableException:$EnableException
        }

        foreach ($ag in $InputObject) {
            Write-Message -Level Verbose -Message "Processing $($ag.Name) on $($ag.Parent.Name)" -FunctionName Test-DbaAgSpn -ModuleName "dbatools" # SOURCE: Write-Message -Level Verbose -Message "Processing $($ag.Name) on $($ag.Parent.Name)"
            if ($Listener) {
                $listeners = $ag | Get-DbaAgListener -Listener $Listener
            } else {
                $listeners = $ag | Get-DbaAgListener
            }

            # ([System.Net.Dns]::GetHostEntry($hostEntry)).HostName
            foreach ($aglistener in $listeners) {
                Write-Message -Level Verbose -Message "Processing $($aglistener.Name) on $($aglistener.Parent.Name)" -FunctionName Test-DbaAgSpn -ModuleName "dbatools" # SOURCE: Write-Message -Level Verbose -Message "Processing $($aglistener.Name) on $($aglistener.Parent.Name)"
                $server = $aglistener.Parent.Parent
                $platform = $server.Platform -split " " | Select-Object -Last 1
                $version = $server.VersionString, $server.DatabaseEngineEdition, "Edition", $platform -join " "
                $port = $aglistener.PortNumber

                $fqdn = $server.Information.FullyQualifiedNetName
                $dnsname = ($fqdn -split "\." | Select-Object -Skip 1) -join "."
                $hostEntry = $aglistener.Name, $dnsname -join "."

                if ($aglistener.InstanceName -eq "MSSQLSERVER") {
                    $required = "MSSQLSvc/$hostEntry"
                } else {
                    $required = "MSSQLSvc/" + $hostEntry + ":" + $aglistener.InstanceName
                }

                $spns += [PSCustomObject] @{
                    ComputerName           = $server.Information.FullyQualifiedNetName
                    SqlInstance            = $aglistener.SqlInstance
                    InstanceName           = $aglistener.InstanceName
                    SqlProduct             = $version
                    InstanceServiceAccount = $server.ServiceAccount
                    RequiredSPN            = $required
                    IsSet                  = $false
                    Cluster                = $server.IsClustered
                    TcpEnabled             = $true
                    Port                   = $port
                    DynamicPort            = $false
                    Warning                = "None"
                    Error                  = "None"
                    Credential             = $Credential
                }

                $spns += [PSCustomObject] @{
                    ComputerName           = $server.Information.FullyQualifiedNetName
                    SqlInstance            = $aglistener.SqlInstance
                    InstanceName           = $aglistener.InstanceName
                    SqlProduct             = $version
                    InstanceServiceAccount = $server.ServiceAccount
                    RequiredSPN            = "MSSQLSvc/$hostEntry" + ":" + $port
                    IsSet                  = $false
                    Cluster                = $server.IsClustered
                    TcpEnabled             = $true
                    Port                   = $port
                    DynamicPort            = $false
                    Warning                = "None"
                    Error                  = "None"
                    Credential             = $Credential
                }
            }
        }

        foreach ($spn in $spns) {
            Write-Message -Level Verbose -Message "Processing SPN on $($spn.SqlInstance)" -FunctionName Test-DbaAgSpn -ModuleName "dbatools" # SOURCE: Write-Message -Level Verbose -Message "Processing SPN on $($spn.SqlInstance)"
            $searchfor = 'User'
            if ($spn.InstanceServiceAccount -eq 'LocalSystem' -or $spn.InstanceServiceAccount -like 'NT SERVICE\*') {
                Write-Message -Level Verbose -Message "Virtual account detected, changing target registration to computername" -FunctionName Test-DbaAgSpn -ModuleName "dbatools" # SOURCE: Write-Message -Level Verbose -Message "Virtual account detected, changing target registration to computername"
                $spn.InstanceServiceAccount = "$($resolved.Domain)\$($resolved.ComputerName)$"
                $searchfor = 'Computer'
            } elseif ($spn.InstanceServiceAccount -like '*\*$') {
                Write-Message -Level Verbose -Message "Managed Service Account detected" -FunctionName Test-DbaAgSpn -ModuleName "dbatools" # SOURCE: Write-Message -Level Verbose -Message "Managed Service Account detected"
                $searchfor = 'Computer'
            }

            $serviceAccount = $spn.InstanceServiceAccount
            # spare the cmdlet to search for the same account over and over
            if ($spn.InstanceServiceAccount -notin $resultCache.Keys) {
                Write-Message -Message "Searching for $serviceAccount" -Level Verbose -FunctionName Test-DbaAgSpn -ModuleName "dbatools" # SOURCE: Write-Message -Message "Searching for $serviceAccount" -Level Verbose
                try {
                    $result = Get-DbaADObject -ADObject $serviceAccount -Type $searchfor -Credential $Credential -EnableException
                    $resultCache[$spn.InstanceServiceAccount] = $result
                } catch {
                    if (![System.String]::IsNullOrEmpty($spn.InstanceServiceAccount)) {
                        Write-Message -Message "AD lookup failure. This may be because the domain cannot be resolved for the SQL Server service account ($serviceAccount)." -Level Warning -FunctionName Test-DbaAgSpn -ModuleName "dbatools" # SOURCE: Write-Message -Message "AD lookup failure. This may be because the domain cannot be resolved for the SQL Server service account ($serviceAccount)." -Level Warning
                    }
                }
            } else {
                $result = $resultCache[$spn.InstanceServiceAccount]
            }
            if ($result.Count -gt 0) {
                try {
                    $results = $result.GetUnderlyingObject()
                    if ($results.Properties.servicePrincipalName -contains $spn.RequiredSPN) {
                        $spn.IsSet = $true
                    }
                } catch {
                    Write-Message -Message "The SQL Service account ($serviceAccount) has been found, but you don't have enough permission to inspect its SPNs" -Level Warning -FunctionName Test-DbaAgSpn -ModuleName "dbatools" # SOURCE: Write-Message -Message "The SQL Service account ($serviceAccount) has been found, but you don't have enough permission to inspect its SPNs" -Level Warning
                    continue
                }
            } else {
                Write-Message -Level Warning -Message "SQL Service account not found. Results may not be accurate." -FunctionName Test-DbaAgSpn -ModuleName "dbatools" # SOURCE: Write-Message -Level Warning -Message "SQL Service account not found. Results may not be accurate."
                $spn
                continue
            }
            if (!$spn.IsSet -and $spn.TcpEnabled) {
                $spn.Error = "SPN missing"
            }

            $spn | Select-DefaultView -ExcludeProperty Credential, DomainName
        }
    }

    @{ __w4065State = @{ resultCache = $resultCache; spns = $spns; result = $result } }
} $SqlInstance $SqlCredential $Credential $AvailabilityGroup $Listener $InputObject $EnableException $__boundSqlInstance $__boundInputObject $__state $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}