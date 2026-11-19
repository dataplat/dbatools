#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using System.Security;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Creates and enables the SSIS Catalog (SSISDB) database on SQL Server 2012+ instances.</para>
/// <para type="description">Creates the SSIS Catalog database (SSISDB) required before deploying, managing, or executing
/// SSIS packages. The command validates prerequisites (edition, master-key password, running SSIS service, CLR
/// integration), then builds the catalog through the IntegrationServices object model.</para>
/// </summary>
/// <remarks>
/// <para>
/// The prerequisite validation and catalog creation stay a module-scoped PowerShell compatibility hop. The begin
/// hop reproduces the source begin block: it refuses on PowerShell Core FIRST (Stop-Function with NO -Continue,
/// which latches the interrupt and spans the whole pipeline), then refuses when neither -SecurePassword nor
/// -Credential is supplied (also a latching Stop-Function), and otherwise derives the effective master password
/// from the credential. Both refusals fire before any connection, so they run identically on both editions. The
/// derived password is carried forward to the process hop exactly as the source begin scope hands it to process.
/// </para>
/// <para>
/// The process hop runs the source process body verbatim: per-instance connect, the SSIS-service and CLR checks
/// via Get-DbaService/Get-Service/Get-DbaSpConfigure, the IntegrationServices catalog load (a non-continue
/// Stop-Function that latches "Can't load server"), the already-exists guard, and the ShouldProcess-gated Create.
/// The ShouldProcess call routes to the real compiled cmdlet ($__realCmdlet) so -WhatIf/-Confirm and the Medium
/// ConfirmImpact are honored by the actual runtime. Write-Message/Stop-Function carry -FunctionName so log
/// attribution and the friendly error id read New-DbaSsisCatalog rather than the hop scriptblock. Surface pinned
/// by migration/baselines/New-DbaSsisCatalog.json.
/// </para>
/// </remarks>
// No [OutputType] is declared: the emitted rows are ad-hoc PSCustomObjects and the catalog types come from
// IntegrationServices assemblies loaded at RUNTIME on Desktop only.
[Cmdlet(VerbsCommon.New, "DbaSsisCatalog", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class NewDbaSsisCatalogCommand : DbaBaseCmdlet
{
    /// <summary>SQL Server you wish to run the function on.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>An alternative way to supply the master password using a PSCredential; only the password is used.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    /// <summary>The master password that encrypts the SSIS catalog database master key.</summary>
    [Parameter(Position = 3)]
    [Alias("Password")]
    public SecureString? SecurePassword { get; set; }

    /// <summary>The name for the SSIS catalog database that will be created. Defaults to 'SSISDB'.</summary>
    [Parameter(Position = 4)]
    public string SsisCatalog { get; set; } = "SSISDB";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Set once the begin block has latched the interrupt (Core guard or missing password).</summary>
    private bool _beginInterrupted;

    /// <summary>The effective master password the begin scope derived (SecurePassword or Credential.Password).</summary>
    private object? _securePassword;

    /// <summary>Set once a process record has latched the interrupt (the non-continue "Can't load server").</summary>
    private bool _bodyInterrupted;

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            SecurePassword, Credential, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__NewDbaSsisCatalogBeginComplete"]?.Value))
            {
                _beginInterrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
                _securePassword = UnwrapHopValue(item.Properties["SecurePassword"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }
    }

    protected override void ProcessRecord()
    {
        if (_beginInterrupted || _bodyInterrupted || Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__NewDbaSsisCatalogProcessComplete"]?.Value))
            {
                _bodyInterrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Credential, _securePassword, SsisCatalog, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // Carried hop state arrives PSObject-wrapped. A PSCustomObject carries its content on the wrapper rather
    // than the BaseObject, so unwrapping one would discard it - keep it wrapped. A SecureString is a plain
    // BaseObject and unwraps cleanly.
    private static object? UnwrapHopValue(object? value)
    {
        if (value is PSObject wrapper && wrapper.BaseObject is not PSCustomObject)
            return wrapper.BaseObject;
        return value;
    }

    // PS: the begin body VERBATIM inside a dot-sourced block so its early returns stay local and the trailing
    // sentinel still runs. Both Stop-Function calls are non-continue, so they latch; the sentinel reports the
    // latch and the derived master password. EnableException is threaded so the friendly-vs-throw decision reads
    // correctly. The source begin has no Test-Bound and no $PSBoundParameters read.
    private const string BeginScript = """
param($SecurePassword, $Credential, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([System.Security.SecureString]$SecurePassword, [System.Management.Automation.PSCredential]$Credential, $EnableException)

    . {
        if ($PSVersionTable.PSEdition -eq "Core") {
            Stop-Function -Message "This command is not supported on Linux or macOS" -FunctionName New-DbaSsisCatalog
            return
        }
        if (-not $SecurePassword -and -not $Credential) {
            Stop-Function -Message "You must specify either -SecurePassword or -Credential" -FunctionName New-DbaSsisCatalog
            return
        }
        if (-not $SecurePassword -and $Credential) {
            $SecurePassword = $Credential.Password
        }
    }

    [pscustomobject]@{ __NewDbaSsisCatalogBeginComplete = $true; Interrupted = (Test-FunctionInterrupt); SecurePassword = $SecurePassword }
} $SecurePassword $Credential $EnableException @__commonParameters 3>&1 2>&1
""";

    // PS: the process body VERBATIM inside a dot-sourced block so early returns stay local and the trailing
    // sentinel still runs. The "Can't load server" Stop-Function is non-continue and latches; the sentinel
    // reports Test-FunctionInterrupt so the next record skips exactly as the source function-scoped latch makes
    // it. The connection catch and already-exists/SSIS-not-running/CLR guards are -Continue and do not latch.
    // The single ShouldProcess gate routes to $__realCmdlet so -WhatIf/-Confirm and Medium ConfirmImpact are
    // honored by the real runtime. Write-Message/Stop-Function carry -FunctionName. EnableException is untyped.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Credential, $SecurePassword, $SsisCatalog, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [System.Management.Automation.PSCredential]$Credential, [System.Security.SecureString]$SecurePassword, [string]$SsisCatalog, $EnableException, $__realCmdlet)

    . {
        if (Test-FunctionInterrupt) {
            return
        }
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaSsisCatalog
            }

            ## check if SSIS and Engine running on box
            try {
                $services = Get-DbaService -ComputerName $server.ComputerName -Credential $Credential -EnableException

                $ssisservice = $Services | Where-Object {
                    $_.ServiceType -eq "SSIS" -and $_.State -eq "Running"
                }
            } catch {
                Write-Message -Level Verbose "Could not connect using Get-DbaService ($PSItem). Trying Get-Service." -FunctionName New-DbaSsisCatalog -ModuleName "dbatools"
            }

            if (-not $ssisservice) {
                if ($instance.IsLocalhost) {
                    $services = Get-Service -ErrorAction Ignore
                } else {
                    $services = Invoke-Command2 -ComputerName $server.ComputerName -Credential $Credential -ScriptBlock { Get-Service } -ErrorAction Ignore
                }

                $ssisservice = $services | Where-Object {
                    ($_.ServiceType -eq "SSIS" -or $_.Name -match "MsDtsServer") -and $_.Status -eq "Running"
                }
                if (-not $ssisservice) {
                    Stop-Function -Message "SSIS is not running on $instance" -Continue -Target $instance -FunctionName New-DbaSsisCatalog
                }
            }

            #if SQL 2012 or higher only validate databases with ContainmentType = NONE
            $clrenabled = Get-DbaSpConfigure -SqlInstance $server -Name IsSqlClrEnabled

            if (-not $clrenabled.RunningValue) {
                Stop-Function -Message "CLR Integration must be enabled. You can enable it by running Set-DbaSpConfigure -SqlInstance $instance -Config IsSqlClrEnabled -Value `$true" -Continue -Target $instance -FunctionName New-DbaSsisCatalog
            }

            try {
                $ssis = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices $server
            } catch {
                Stop-Function -Message "Can't load server" -Target $instance -ErrorRecord $_ -FunctionName New-DbaSsisCatalog
                return
            }

            if ($ssis.Catalogs.Count -gt 0) {
                Stop-Function -Message "SSIS Catalog already exists" -Continue -Target $ssis.Catalogs -FunctionName New-DbaSsisCatalog
            } else {
                if ($__realCmdlet.ShouldProcess($server, "Creating SSIS catalog: $SsisCatalog")) {
                    try {
                        $ssisdb = New-Object Microsoft.SqlServer.Management.IntegrationServices.Catalog ($ssis, $SsisCatalog, $(([System.Runtime.InteropServices.marshal]::PtrToStringAuto([System.Runtime.InteropServices.marshal]::SecureStringToBSTR($SecurePassword)))))
                    } catch {
                        Stop-Function -Message "Failed to create SSIS Catalog: $_" -Target $_ -Continue -FunctionName New-DbaSsisCatalog
                    }
                    try {
                        $ssisdb.Create()
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            SsisCatalog  = $SsisCatalog
                            Created      = $true
                        }
                    } catch {
                        $msg = $_.Exception.InnerException.InnerException.Message
                        if (-not $msg) {
                            $msg = $_
                        }
                        Stop-Function -Message "$msg" -Target $_ -Continue -FunctionName New-DbaSsisCatalog
                    }
                }
            }
        }
    }

    [pscustomobject]@{ __NewDbaSsisCatalogProcessComplete = $true; Interrupted = (Test-FunctionInterrupt) }
} $SqlInstance $SqlCredential $Credential $SecurePassword $SsisCatalog $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
