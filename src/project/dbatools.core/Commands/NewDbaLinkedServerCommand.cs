#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates linked servers. Port of public/New-DbaLinkedServer.ps1 (W3-067). The process
/// body rides one VERBATIM module hop per record inside a DOT-SOURCED inner block (W1-108:
/// three validation `Stop-Function; return` early exits - the source LACKS the Interrupted
/// prologue, so the validations re-fire per record exactly as the function's did; no
/// C#-side latch). $Pscmdlet.ShouldProcess routes to the REAL cmdlet (ConfirmImpact Low
/// mirrored). The __w3067State sentinel carries the $InputObject += Connect-DbaInstance
/// accumulation (W1-070 + the F1 named-at-begin rebind discriminator) and stale locals.
/// [PsStringCast] on the ValidateSet SecurityContext (W1-032). SECURITY, source-verbatim:
/// the SpecifiedSecurityContext branch flattens the caller-supplied SecureString through
/// the private ConvertFrom-SecurePass INTO the sp_addlinkedsrvlogin @rmtpassword T-SQL text
/// - shipped provisioning behavior reproduced exactly (the sproc interface is plaintext);
/// the SecureString itself rides the hop as the live object and never appears in messages
/// or logs. The interpolated sp_addlinkedsrvlogin/sp_droplinkedsrvlogin queries keep the
/// source T-SQL text (verbatim-hop convention). Ten Test-Bound reads carried as flags. NO
/// WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/New-DbaLinkedServer.json (implicit positions 0-12,
/// InputObject Server[] pos12 VFP, ConfirmImpact Low).
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaLinkedServer", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaLinkedServerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The linked server name.</summary>
    [Parameter(Position = 2)]
    public string? LinkedServer { get; set; }

    /// <summary>The product name of the data source.</summary>
    [Parameter(Position = 3)]
    public string? ServerProduct { get; set; }

    /// <summary>The unique programmatic identifier of the OLE DB provider.</summary>
    [Parameter(Position = 4)]
    public string? Provider { get; set; }

    /// <summary>The data source per the OLE DB provider interpretation.</summary>
    [Parameter(Position = 5)]
    public string? DataSource { get; set; }

    /// <summary>The location per the OLE DB provider interpretation.</summary>
    [Parameter(Position = 6)]
    public string? Location { get; set; }

    /// <summary>The provider connection string.</summary>
    [Parameter(Position = 7)]
    public string? ProviderString { get; set; }

    /// <summary>The catalog used when connecting through the provider.</summary>
    [Parameter(Position = 8)]
    public string? Catalog { get; set; }

    /// <summary>Login mapping behavior for non-mapped logins.</summary>
    [Parameter(Position = 9)]
    [PsStringCast]
    [ValidateSet("NoConnection", "WithoutSecurityContext", "CurrentSecurityContext", "SpecifiedSecurityContext")]
    public string SecurityContext { get; set; } = "WithoutSecurityContext";

    /// <summary>The remote user for SpecifiedSecurityContext.</summary>
    [Parameter(Position = 10)]
    public string? SecurityContextRemoteUser { get; set; }

    /// <summary>The remote user password for SpecifiedSecurityContext.</summary>
    [Parameter(Position = 11)]
    public System.Security.SecureString? SecurityContextRemoteUserPassword { get; set; }

    /// <summary>SMO Server object(s) from Connect-DbaInstance.</summary>
    [Parameter(ValueFromPipeline = true, Position = 12)]
    public Microsoft.SqlServer.Management.Smo.Server[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Fn-scope $InputObject accumulation across records (the bag rides the hop).
    private Hashtable? _state;
    private object? _inputObjectState;
    private object? _lastBoundInputObject;
    private bool _bindInitialized;
    private bool _inputObjectNamedBound;

    protected override void BeginProcessing()
    {
        // Pipeline bindings are absent at begin time - the F1 named-at-begin rebind
        // discriminator (codex W3-002 F1, family-wide).
        _inputObjectNamedBound = TestBound(nameof(InputObject));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // W1-070 + F1: a piped Server re-binds EVERY record it arrives in.
        if ((!_inputObjectNamedBound && TestBound(nameof(InputObject))) ||
            !ReferenceEquals(InputObject, _lastBoundInputObject) || !_bindInitialized)
        {
            _inputObjectState = InputObject;
            _lastBoundInputObject = InputObject;
            _bindInitialized = true;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3067State"))
            {
                _state = sentinel["__w3067State"] as Hashtable;
                if (_state is not null)
                {
                    _inputObjectState = _state["InputObject"];
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
        }, ProcessScript,
            SqlInstance, SqlCredential, LinkedServer, ServerProduct, Provider, DataSource,
            Location, ProviderString, Catalog, SecurityContext, SecurityContextRemoteUser,
            SecurityContextRemoteUserPassword, _inputObjectState, EnableException.ToBool(),
            _state,
            TestBound(nameof(LinkedServer)), TestBound(nameof(ServerProduct)),
            TestBound(nameof(Provider)), TestBound(nameof(DataSource)),
            TestBound(nameof(Location)), TestBound(nameof(ProviderString)),
            TestBound(nameof(Catalog)), TestBound(nameof(SecurityContext)),
            TestBound(nameof(SecurityContextRemoteUser)),
            TestBound(nameof(SecurityContextRemoteUserPassword)), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the ENTIRE process body VERBATIM inside a dot-sourced inner block (three
    // validation early returns; the trailing state sentinel still emits). Substitutions
    // only: Test-Bound X -> carried $__boundX flags, $Pscmdlet -> $__realCmdlet, and
    // explicit -FunctionName New-DbaLinkedServer on Stop-Function (W1-090). The
    // sp_*linkedsrvlogin queries and the ConvertFrom-SecurePass flatten are the SOURCE's
    // own shipped text - verbatim.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $LinkedServer, $ServerProduct, $Provider, $DataSource, $Location, $ProviderString, $Catalog, $SecurityContext, $SecurityContextRemoteUser, $SecurityContextRemoteUserPassword, $InputObject, $EnableException, $__state, $__boundLinkedServer, $__boundServerProduct, $__boundProvider, $__boundDataSource, $__boundLocation, $__boundProviderString, $__boundCatalog, $__boundSecurityContext, $__boundSecurityContextRemoteUser, $__boundSecurityContextRemoteUserPassword, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string]$LinkedServer, [string]$ServerProduct, [string]$Provider, [string]$DataSource, [string]$Location, [string]$ProviderString, [string]$Catalog, [string]$SecurityContext, [string]$SecurityContextRemoteUser, [Security.SecureString]$SecurityContextRemoteUserPassword, [Microsoft.SqlServer.Management.Smo.Server[]]$InputObject, $EnableException, $__state, $__boundLinkedServer, $__boundServerProduct, $__boundProvider, $__boundDataSource, $__boundLocation, $__boundProviderString, $__boundCatalog, $__boundSecurityContext, $__boundSecurityContextRemoteUser, $__boundSecurityContextRemoteUserPassword, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # restore fn-scope locals mutated by earlier records
    if ($null -ne $__state) {
        $server = $__state.server
        $newLinkedServer = $__state.newLinkedServer
        $instance = $__state.instance
    }

    . {
        if (-not $__boundLinkedServer) {
            Stop-Function -Message "LinkedServer is required" -FunctionName New-DbaLinkedServer
            return
        }

        if ($SecurityContext -eq "SpecifiedSecurityContext") {
            if (-not $__boundSecurityContextRemoteUser) {
                Stop-Function -Message "SecurityContextRemoteUser is required when SpecifiedSecurityContext is used" -FunctionName New-DbaLinkedServer
                return
            } elseif (-not $__boundSecurityContextRemoteUserPassword) {
                Stop-Function -Message "SecurityContextRemoteUserPassword is required when SpecifiedSecurityContext is used" -FunctionName New-DbaLinkedServer
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        }

        foreach ($server in $InputObject) {

            if ($server.LinkedServers.Name -contains $LinkedServer) {
                Stop-Function -Message "Linked server $LinkedServer already exists on $($server.Name)" -Continue -FunctionName New-DbaLinkedServer
            }

            if ($__realCmdlet.ShouldProcess($server.Name, "Creating the linked server $LinkedServer on $($server.Name)")) {
                try {
                    $newLinkedServer = New-Object Microsoft.SqlServer.Management.Smo.LinkedServer -ArgumentList $server, $LinkedServer

                    if ($__boundServerProduct) {
                        $newLinkedServer.ProductName = $ServerProduct
                    }

                    if ($__boundProvider) {
                        $newLinkedServer.ProviderName = $Provider
                    }

                    if ($__boundDataSource) {
                        $newLinkedServer.DataSource = $DataSource
                    }

                    if ($__boundLocation) {
                        $newLinkedServer.Location = $Location
                    }

                    if ($__boundProviderString) {
                        $newLinkedServer.ProviderString = $ProviderString
                    }

                    if ($__boundCatalog) {
                        $newLinkedServer.Catalog = $Catalog
                    }

                    $newLinkedServer.Create()

                    if ($__boundSecurityContext) {
                        if ($SecurityContext -eq 'NoConnection') {
                            $server.Query("EXEC master.dbo.sp_droplinkedsrvlogin @rmtsrvname = N'$LinkedServer', @locallogin = NULL")
                        } elseif ($SecurityContext -eq 'WithoutSecurityContext') {
                            $server.Query("EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N'$LinkedServer', @locallogin = NULL, @useself = N'False', @rmtuser = N''")
                        } elseif ($SecurityContext -eq 'CurrentSecurityContext') {
                            $server.Query("EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N'$LinkedServer', @locallogin = NULL, @useself = N'True', @rmtuser = N''")
                        } elseif ($SecurityContext -eq 'SpecifiedSecurityContext') {
                            $server.Query("EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N'$LinkedServer', @locallogin = NULL, @useself = N'False', @rmtuser = N'$SecurityContextRemoteUser', @rmtpassword = N'$($SecurityContextRemoteUserPassword | ConvertFrom-SecurePass)'")
                        }
                    }

                    $server | Get-DbaLinkedServer -LinkedServer $LinkedServer
                } catch {
                    Stop-Function -Message "Failure on $($server.Name) to create the linked server $LinkedServer" -ErrorRecord $_ -Continue -FunctionName New-DbaLinkedServer
                }
            }
        }
    }
    @{ __w3067State = @{ InputObject = $InputObject; server = $server; newLinkedServer = $newLinkedServer; instance = $instance } }
} $SqlInstance $SqlCredential $LinkedServer $ServerProduct $Provider $DataSource $Location $ProviderString $Catalog $SecurityContext $SecurityContextRemoteUser $SecurityContextRemoteUserPassword $InputObject $EnableException $__state $__boundLinkedServer $__boundServerProduct $__boundProvider $__boundDataSource $__boundLocation $__boundProviderString $__boundCatalog $__boundSecurityContext $__boundSecurityContextRemoteUser $__boundSecurityContextRemoteUserPassword $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
