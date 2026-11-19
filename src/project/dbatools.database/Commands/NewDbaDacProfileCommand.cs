#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Writes DAC publish profile XML files for one or more databases. Port of
/// public/New-DbaDacProfile.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// BEGIN+PROCESS, two hops. SqlInstance is ValueFromPipeline, so process fires per piped instance.
///
/// THE BEGIN BLOCK IS SPLIT, because its two halves have different lifetimes. Its three GUARDS
/// (either -SqlInstance or -ConnectionString required, -Path must exist, -Path must be a directory)
/// are one-time validation and stay in the begin hop; each is Stop-Function WITHOUT -Continue so it
/// sets the module interrupt, and process opens with "if (Test-FunctionInterrupt) { return }", so a
/// failed guard silences every record. Its three HELPER FUNCTIONS
/// (Convert-HashtableToXMLString, Get-Template, Get-ServerName) are defined in begin but CALLED in
/// process, and begin's scope does not survive to the process hop, so they are recreated verbatim
/// at the top of the process hop - the same treatment Invoke-DbaDbDecryptObject's decrypt helper
/// needed. Get-Template closes over $PublishOptions, which inside the hop is the hop's own
/// parameter, so that closure keeps working.
///
/// -Path's source default is "$home\Documents", a bind-time default derived from a PowerShell
/// runtime variable that a C# property initializer cannot express faithfully (the DEF-007 class).
/// It is resolved ONCE in the begin hop - before the guards that read it - and the resolved value
/// carries to process, matching the source's bind-once semantics rather than re-deriving it.
///
/// $ConnectionString CROSS-RECORD ACCUMULATOR (bug-for-bug). The body does
/// "$ConnectionString += $server.ConnectionContext.ConnectionString..." for each connected
/// instance, and $ConnectionString is NOT a pipeline parameter, so the binder never rewrites it and
/// the source's function-scope value keeps every earlier record's connection strings. The
/// subsequent "foreach ($connString in $ConnectionString)" then re-emits profiles for instances an
/// earlier record already handled. Because the mutated variable can never be the pipeline target,
/// the carry is unconditional and needs no rebind detection - the cheap branch of that question.
///
/// $server is deliberately NOT carried, and this is the second row where a reviewer has read it as
/// a cross-record carry, so the reasoning is recorded here. It is assigned inside a try whose catch
/// is Stop-Function -Continue, and a continue inside a catch skips the rest of that loop iteration -
/// measured, see migration/logs/probe-20260718-continue-in-catch - so the
/// "$ConnectionString += $server..." line below is unreachable after a connection failure and can
/// never read a stale server. The second loop reassigns $server before use. GENERAL RULE:
/// "assigned in a try, read after the catch" is only a real carry when the catch neither continues
/// nor throws; check the catch disposition before adding such a variable to a sentinel.
///
/// The one $Pscmdlet.ShouldProcess gate routes to the real cmdlet via $__realCmdlet. Both process
/// Stop-Function calls carry -Continue (skip this instance / this profile and keep looping), so
/// they do not set the interrupt; only the begin guards do. In-hop Stop-Function/Write-Message
/// carry -FunctionName. Implicit positions 0-5 are made explicit; the switch carries none. Surface
/// pinned by migration/baselines/New-DbaDacProfile.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaDacProfile", SupportsShouldProcess = true)]
public sealed class NewDbaDacProfileCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance(s) to build connection strings from.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) each profile targets.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [PsStringArrayCast]
    public string[] Database { get; set; } = null!;

    /// <summary>Directory the profile XML files are written to; defaults to the user's Documents.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string? Path { get; set; }

    /// <summary>Connection strings to build profiles from instead of connecting.</summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? ConnectionString { get; set; }

    /// <summary>Extra publish options rendered into the profile XML.</summary>
    [Parameter(Position = 5)]
    public Hashtable? PublishOptions { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The resolved -Path (bind-once default) carried from begin; opaque to C#.
    private Hashtable? _beginState;
    // The $ConnectionString accumulator carried across records; opaque to C#.
    private Hashtable? _state;
    // A failed begin guard silences every record.
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaDacProfileBegin"))
            {
                if (sentinel["__newDbaDacProfileBegin"] is Hashtable state)
                {
                    _beginState = state;
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                }
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BeginScript,
            Path, EnableException.ToBool(),
            MyInvocation.BoundParameters.ContainsKey("SqlInstance"),
            MyInvocation.BoundParameters.ContainsKey("ConnectionString"),
            MyInvocation.BoundParameters.ContainsKey("Path"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaDacProfileProcess"))
            {
                _state = sentinel["__newDbaDacProfileProcess"] as Hashtable;
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
            SqlInstance, SqlCredential, Database, ConnectionString, PublishOptions,
            EnableException.ToBool(), _beginState, _state, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block's three GUARDS, verbatim and dot-sourced. The bind-time "$home\Documents"
    // default for -Path is applied FIRST, because two of the guards read $Path. Edits: the
    // Test-Bound -Not pair becomes the carried caller-boundness flags, -FunctionName on the three
    // Stop-Function calls. The sentinel carries the resolved path and the interrupt. The begin
    // block's three helper FUNCTIONS are not here - they are consumed in process, so they are
    // recreated there (begin's scope does not reach the process hop).
    private const string BeginScript = """
param($Path, $EnableException, $__boundSqlInstance, $__boundConnectionString, $__boundPath, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$Path, $EnableException, $__boundSqlInstance, $__boundConnectionString, $__boundPath, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # -Path's bind-time default. Resolved ONCE here, before the guards that read it, and carried to
    # process, matching the source binding it once rather than re-deriving it per hop.
    if (-not $__boundPath) { $Path = "$home\Documents" }

    . {
        if ((-not $__boundSqlInstance) -and (-not $__boundConnectionString)) {
            Stop-Function -Message "You must specify either SqlInstance or ConnectionString" -FunctionName New-DbaDacProfile
        }

        if (-not (Test-Path $Path)) {
            Stop-Function -Message "$Path doesn't exist or access denied" -FunctionName New-DbaDacProfile
        }

        if ((Get-Item $path) -isnot [System.IO.DirectoryInfo]) {
            Stop-Function -Message "Path must be a directory" -FunctionName New-DbaDacProfile
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __newDbaDacProfileBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value); Path = $Path } }
} $Path $EnableException $__boundSqlInstance $__boundConnectionString $__boundPath $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM per record, dot-sourced. Ahead of it: the resolved -Path from
    // begin, the begin block's three helper functions recreated verbatim (they are defined in begin
    // but called here, and begin's scope does not survive), and the $ConnectionString accumulator
    // restored from the carry. Edits: the one $Pscmdlet gate routes to $__realCmdlet and
    // -FunctionName is stamped on the three direct calls. The sentinel snapshots the accumulator so
    // a later piped instance sees the connection strings earlier ones appended - the source's
    // behavior, reproduced not fixed.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ConnectionString, $PublishOptions, $EnableException, $__beginState, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ConnectionString, [hashtable]$PublishOptions, $EnableException, $__beginState, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # the resolved -Path begin bound once
    $Path = $__beginState.Path

    # the begin block's helper functions, recreated verbatim (defined in begin, called here)
        function Convert-HashtableToXMLString($PublishOptions) {
            $return = @()
            if ($PublishOptions) {
                $PublishOptions.GetEnumerator() | ForEach-Object {
                    $key = $PSItem.Key.ToString()
                    $value = $PSItem.Value.ToString()
                    $return += "<$key>$value</$key>"
                }
            }
            $return | Out-String
        }

        function Get-Template {
            param (
                $db,
                $connString
            )

            "<?xml version=""1.0"" ?>
            <Project ToolsVersion=""14.0"" xmlns=""http://schemas.microsoft.com/developer/msbuild/2003"">
              <PropertyGroup>
                <TargetDatabaseName>{0}</TargetDatabaseName>
                <TargetConnectionString>{1}</TargetConnectionString>
                <ProfileVersionNumber>1</ProfileVersionNumber>
                {2}
              </PropertyGroup>
            </Project>" -f $db, $connString, $(Convert-HashtableToXMLString($PublishOptions))
        }

        function Get-ServerName ($connString) {
            $builder = New-Object System.Data.Common.DbConnectionStringBuilder
            $builder.set_ConnectionString($connString)
            $instance = $builder['data source']

            if (-not $instance) {
                $instance = $builder['server']
            }

            $instance = $instance.ToString().Replace('TCP:', '')
            $instance = $instance.ToString().Replace('tcp:', '')
            return $instance.ToString().Replace('\', '--')
        }

    # $ConnectionString accumulator: not a pipeline parameter, so the binder never rewrites it and
    # the source's function-scope value keeps every earlier record's appended connection strings.
    if ($null -ne $__state -and $__state.ContainsKey("ConnectionString")) {
        $ConnectionString = $__state.ConnectionString
    }

    . {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaDacProfile
            }

            $ConnectionString += $server.ConnectionContext.ConnectionString.Replace(';Application Name="dbatools PowerShell module - dbatools.io"', '').Replace(";Encrypt=False", "").Replace(";Trust Server Certificate=False", "") | Convert-ConnectionString

        }

        foreach ($connString in $ConnectionString) {
            foreach ($db in $Database) {
                if ($__realCmdlet.ShouldProcess($db, "Creating new DAC Profile")) {
                    $profileTemplate = Get-Template -db $db -connString $connString
                    $instanceName = Get-ServerName $connString

                    try {
                        $server = [DbaInstance]($instanceName.ToString().Replace('--', '\'))
                        $publishProfile = Join-Path $Path "$($instanceName.Replace('--','-'))-$db-publish.xml" -ErrorAction Stop
                        Write-Message -Level Verbose -Message "Writing to $publishProfile" -FunctionName New-DbaDacProfile -ModuleName "dbatools"
                        $profileTemplate | Out-File $publishProfile -ErrorAction Stop
                        [PSCustomObject]@{
                            ComputerName     = $server.ComputerName
                            InstanceName     = $server.InstanceName
                            SqlInstance      = $server.FullName
                            Database         = $db
                            FileName         = $publishProfile
                            ConnectionString = $connString
                            ProfileTemplate  = $profileTemplate
                        } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName, ProfileTemplate
                    } catch {
                        Stop-Function -ErrorRecord $_ -Message "Failure" -Target $instanceName -Continue -FunctionName New-DbaDacProfile
                    }
                }
            }
        }
    }

    @{ __newDbaDacProfileProcess = @{ ConnectionString = $ConnectionString } }
} $SqlInstance $SqlCredential $Database $ConnectionString $PublishOptions $EnableException $__beginState $__state $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
