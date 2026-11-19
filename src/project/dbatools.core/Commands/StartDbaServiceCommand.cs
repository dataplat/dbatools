#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Starts SQL Server services. Port of public/Start-DbaService.ps1 (W3-101) - the
/// Restart-DbaService (W3-084) sibling, same begin/process/end lifecycle with the
/// cross-record accumulator: the begin block resolves the Server parameter set's
/// services via Get-DbaService (begin hop; the result and the empty $processArray ride
/// the __w3101State sentinel), each process record appends $InputObject to the
/// accumulator (in the Server set the begin-resolved list IS the record's $InputObject
/// - the C# side passes the begin value through, reproducing the function's variable
/// semantics), and the end hop runs the verbatim filter / ShouldProcess gate /
/// Update-ServiceStatus call. DIFFERENCES from the sibling, all verbatim: no -Force
/// (no dependent-service expansion), the gate sits OUTSIDE the empty-check (WhatIf
/// suppresses even the no-services Stop-Function), the Stop-Function carries
/// -Category ObjectNotFound, and Update-ServiceStatus is called ONCE with
/// Action "start" (no stop-then-restart flow, no Failed/Successful split - its output
/// flows straight to the pipeline). The private Update-ServiceStatus rides behind the
/// same W3-084 ATTRIBUTION SHIM (it derives Stop-Function attribution from
/// $callStack[1].Command); no latch dependency follows the call (nothing executes
/// after it - the W3-092/095-verified shim class). $PSCmdlet.ShouldProcess routes to
/// the REAL cmdlet; the begin-block $PsCmdlet.ParameterSetName read is carried as a
/// string. Bind-time casts: [PsStringArrayCast] on the ValidateSet Type (W1-035) and
/// [PsIntCast] on Timeout (W1-043: explicit null binds 0, overriding the 60 default
/// exactly like the function binder). NO WarningAction carrier (codex W3-005 r3).
/// Surface pinned by migration/baselines/Start-DbaService.json (sets Server
/// {ComputerName pos1 + aliases cn/host/Server + env default, SqlInstance} + Service
/// {InputObject object[] Mandatory VFP Alias ServiceCollection}, default Server).
/// </summary>
[Cmdlet(VerbsLifecycle.Start, "DbaService", SupportsShouldProcess = true, DefaultParameterSetName = "Server")]
public sealed class StartDbaServiceCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to this computer.</summary>
    [Parameter(ParameterSetName = "Server", Position = 1)]
    [Alias("cn", "host", "Server")]
    public DbaInstanceParameter[] ComputerName { get; set; } =
        (DbaInstanceParameter[])LanguagePrimitives.ConvertTo(
            Environment.GetEnvironmentVariable("COMPUTERNAME"),
            typeof(DbaInstanceParameter[]), System.Globalization.CultureInfo.InvariantCulture);

    /// <summary>Instance name filter.</summary>
    [Parameter]
    [Alias("Instance")]
    public string[]? InstanceName { get; set; }

    /// <summary>Instance(s) whose services should be started (Server set).</summary>
    [Parameter(ParameterSetName = "Server")]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Service type filter.</summary>
    [Parameter]
    [PsStringArrayCast]
    [ValidateSet("Agent", "Browser", "Engine", "FullText", "SSAS", "SSIS", "SSRS", "PolyBase", "Launchpad")]
    public string[]? Type { get; set; }

    /// <summary>Service objects from Get-DbaService (Service set).</summary>
    [Parameter(ValueFromPipeline = true, Mandatory = true, ParameterSetName = "Service")]
    [Alias("ServiceCollection")]
    public object[]? InputObject { get; set; }

    /// <summary>Seconds to wait per service state change; defaults to 60.</summary>
    [Parameter]
    [PsIntCast]
    public int Timeout { get; set; } = 60;

    /// <summary>Credential for the remote service operations.</summary>
    [Parameter]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // begin-resolved Server-set services + the cross-record $processArray accumulator.
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            ComputerName, InstanceName, SqlInstance, Type, Credential,
            EnableException.ToBool(), ParameterSetName,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3101State"))
            {
                _state = sentinel["__w3101State"] as Hashtable;
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // In the Server set the function's process reads the begin-assigned $InputObject;
        // in the Service set it reads the record binding.
        object? recordInput = string.Equals(ParameterSetName, "Server", StringComparison.Ordinal)
            ? _state?["beginInputObject"]
            : InputObject;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            recordInput, _state,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3101State"))
            {
                _state = sentinel["__w3101State"] as Hashtable;
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, EndScript,
            ComputerName, InstanceName, SqlInstance, Type, Timeout, Credential,
            EnableException.ToBool(), ParameterSetName, _state, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    // PS: the begin block VERBATIM. Substitution only: $PsCmdlet.ParameterSetName -> the
    // carried set name. The Server-set Get-DbaService resolution result rides the
    // sentinel as beginInputObject next to the empty accumulator.
    private const string BeginScript = """
param($ComputerName, $InstanceName, $SqlInstance, $Type, $Credential, $EnableException, $__parameterSetName, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$ComputerName, [string[]]$InstanceName, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [string[]]$Type, [PSCredential]$Credential, $EnableException, $__parameterSetName, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $processArray = @()
    @{ __w3101State = @{ processArray = $processArray; beginInputObject = $null } }
} $ComputerName $InstanceName $SqlInstance $Type $Credential $EnableException $__parameterSetName $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process body VERBATIM per record; the accumulator threads through the
    // sentinel.
    private const string ProcessScript = """
param($InputObject, $__state, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([object[]]$InputObject, $__state, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $processArray = $__state.processArray

    #Get all the objects from the pipeline before proceeding
    $processArray += $InputObject

    @{ __w3101State = @{ processArray = $processArray; beginInputObject = $__state.beginInputObject } }
} $InputObject $__state $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM. Substitutions only: $PSCmdlet -> $__realCmdlet and
    // explicit -FunctionName Start-DbaService on Stop-Function (W1-090). The private
    // Update-ServiceStatus (behind the attribution shim), the "$ProcessArray"
    // gate-target interpolation, the gate-outside-empty-check ordering and the explicit
    // -EnableException $EnableException / -Category ObjectNotFound Stop-Function ride
    // as-is.
    private const string EndScript = """
param($ComputerName, $InstanceName, $SqlInstance, $Type, $Timeout, $Credential, $EnableException, $__parameterSetName, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$ComputerName, [string[]]$InstanceName, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [string[]]$Type, [int]$Timeout, [PSCredential]$Credential, $EnableException, $__parameterSetName, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # ATTRIBUTION SHIM (B batch [P2], the Get-PSCallStack class): Update-ServiceStatus
    # derives its Stop-Function attribution from $callStack[1].Command. Called bare from
    # this hop, frame 1 is the hop scriptblock => FQEID dbatools_<ScriptBlock>. This
    # named wrapper puts "Start-DbaService" in frame 1 exactly like the source's own
    # function frame; streams and terminating errors flow through unchanged.
    function Start-DbaService {
        param($__splat)
        # The nested-command boundary re-wraps carried PSObjects: NoteProperties and
        # ScriptMethods return through the engine's instance-member table (keyed on the
        # base object), but inserted instance type names live on the wrapper and are lost
        # in transit. Update-ServiceStatus gates on the dbatools.DbaSqlService type name,
        # so restore it - only on objects provably carrying Get-DbaService's decoration:
        # the ServicePriority NoteProperty plus the ChangeStartMode ScriptMethod, on
        # either an adapted SqlService/MSReportServer WMI/CIM object or the reporting
        # services property-bag shape. Objects without that decoration keep failing the
        # gate exactly like they do in the function world.
        foreach ($__carriedService in @($__splat.InputObject)) {
            if ($null -eq $__carriedService) { continue }
            if ("dbatools.DbaSqlService" -in $__carriedService.PSObject.TypeNames) { continue }
            $__priorityMember = $__carriedService.PSObject.Properties["ServicePriority"]
            $__startModeMethod = $__carriedService.PSObject.Methods["ChangeStartMode"]
            $__adaptedServiceName = $__carriedService.PSObject.TypeNames -match "^(System\.Management\.ManagementObject|Microsoft\.Management\.Infrastructure\.CimInstance)#(root[\\/].+[\\/])?(SqlService|MSReportServer_ConfigurationSetting)$"
            $__isPropertyBag = $__carriedService.PSObject.BaseObject -is [System.Management.Automation.PSCustomObject]
            if ($__priorityMember -and $__priorityMember.MemberType -eq "NoteProperty" -and
                $__startModeMethod -and $__startModeMethod.MemberType -eq "ScriptMethod" -and
                ($__adaptedServiceName -or $__isPropertyBag)) {
                $__carriedService.PSObject.TypeNames.Insert(0, "dbatools.DbaSqlService")
            }
        }
        Update-ServiceStatus @__splat
    }

    $processArray = $__state.processArray
    if ($__parameterSetName -eq "Server") {
        $serviceParams = @{ ComputerName = $ComputerName }
        if ($InstanceName) { $serviceParams.InstanceName = $InstanceName }
        if ($SqlInstance) { $serviceParams.SqlInstance = $SqlInstance }
        if ($Type) { $serviceParams.Type = $Type }
        if ($Credential) { $serviceParams.Credential = $Credential }
        if ($EnableException) { $serviceParams.EnableException = $EnableException }
        $processArray = @(Get-DbaService @serviceParams)
    }

    $processArray = $processArray | Where-Object { (!$InstanceName -or $_.InstanceName -in $InstanceName) -and (!$Type -or $_.ServiceType -in $Type) }
    if ($__realCmdlet.ShouldProcess("$ProcessArray", "Starting Service")) {
        if ($processArray) {
            $splatServiceStatus = @{
                InputObject     = $processArray
                Action          = "start"
                Timeout         = $Timeout
                EnableException = $EnableException
            }
            if ($Credential) { $splatServiceStatus.Credential = $Credential }
            Start-DbaService -__splat $splatServiceStatus
        } else {
            Stop-Function -EnableException $EnableException -Message "No SQL Server services found with current parameters." -Category ObjectNotFound -FunctionName Start-DbaService
        }
    }
} $ComputerName $InstanceName $SqlInstance $Type $Timeout $Credential $EnableException $__parameterSetName $__state $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
