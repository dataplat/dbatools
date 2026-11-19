#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a SQL Server endpoint (database mirroring, Service Broker, SOAP or T-SQL).
/// Port of public/New-DbaEndpoint.ps1; surface pinned by
/// migration/baselines/New-DbaEndpoint.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaEndpoint", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaEndpointCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The endpoint name; defaults to hadr_endpoint for database mirroring.</summary>
    [Parameter(Position = 2)]
    [Alias("Endpoint")]
    public string? Name { get; set; }

    /// <summary>The endpoint type.</summary>
    [Parameter(Position = 3)]
    [ValidateSet("DatabaseMirroring", "ServiceBroker", "Soap", "TSql")]
    [PsStringCast]
    public string Type { get; set; } = "DatabaseMirroring";

    /// <summary>The endpoint protocol.</summary>
    [Parameter(Position = 4)]
    [ValidateSet("Tcp", "NamedPipes", "Http", "Via", "SharedMemory")]
    [PsStringCast]
    public string Protocol { get; set; } = "Tcp";

    /// <summary>The mirroring role served by the endpoint.</summary>
    [Parameter(Position = 5)]
    [ValidateSet("All", "None", "Partner", "Witness")]
    [PsStringCast]
    public string Role { get; set; } = "All";

    /// <summary>Endpoint encryption requirement.</summary>
    [Parameter(Position = 6)]
    [ValidateSet("Disabled", "Required", "Supported")]
    [PsStringCast]
    public string EndpointEncryption { get; set; } = "Required";

    /// <summary>Endpoint encryption algorithm.</summary>
    [Parameter(Position = 7)]
    [ValidateSet("Aes", "AesRC4", "None", "RC4", "RC4Aes")]
    [PsStringCast]
    public string EncryptionAlgorithm { get; set; } = "Aes";

    /// <summary>The endpoint authentication order.</summary>
    [Parameter(Position = 8)]
    [ValidateSet("Certificate", "CertificateKerberos", "CertificateNegotiate", "CertificateNtlm", "Kerberos", "KerberosCertificate", "Negotiate", "NegotiateCertificate", "Ntlm", "NtlmCertificate")]
    [PsStringCast]
    public string? AuthenticationOrder { get; set; }

    /// <summary>Certificate used to authenticate the endpoint.</summary>
    [Parameter(Position = 9)]
    public string? Certificate { get; set; }

    /// <summary>The IP address the endpoint listens on.</summary>
    [Parameter(Position = 10)]
    public System.Net.IPAddress IPAddress { get; set; } = System.Net.IPAddress.Parse("0.0.0.0");

    /// <summary>The endpoint TCP port.</summary>
    [Parameter(Position = 11)]
    public int Port { get; set; }

    /// <summary>The endpoint SSL port.</summary>
    [Parameter(Position = 12)]
    public int SslPort { get; set; }

    /// <summary>The endpoint owner login.</summary>
    [Parameter(Position = 13)]
    public string? Owner { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        base.BeginProcessing();

        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("New-DbaEndpoint");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // WHOLE-RECORD hop. The source has NO begin block; the single ShouldProcess gate runs on
        // the INNER hop scriptblock's own $Pscmdlet (inner re-declares SupportsShouldProcess +
        // ConfirmImpact Low - never prompting by default, exactly like the function). Because
        // SqlInstance is a per-record VFP axis, an explicit -Confirm answer of Yes/No-to-All must
        // survive BETWEEN piped records the way the source's single function-scope $Pscmdlet
        // does: the W3-082 prompt-state transplant carries lastShouldProcessContinueStatus
        // through the __w4044State sentinel. The loop-less validation Stop-Function+return exits
        // the record via the dot-block frame; the in-loop sites are -Continue.
        //
        // NO cross-record PARAMETER carry, and that is a decision: the source assigns $Name and
        // $Owner inside process{}, but BOTH sit under Test-Bound guards. Test-Bound reads the
        // BINDING, which never changes between records, so both assignments RE-RUN every record -
        // $Name re-assigns the same constant and $Owner RE-DERIVES Get-SaLoginName from the
        // CURRENT record's server. Carrying $Owner would pin the first record's sa login onto the
        // second record's instance, a divergence the source does not have. (Contrast a VALUE
        // guard `if (-not $X)`, which IS sticky and does need a carry.) Probe with controls:
        // migration/notes/W4-044-guard-type-probe.txt.
        // [DEF-001] closed via InvokeScopedStreaming (ab7492c). Streaming changes -WhatIf transcript
        // capture (documented observability change, not behaviour); the parity runner strips the
        // transcript gate-message. Fleet-confirmed non-blocker (C's streamed ShouldProcess wave, MSTest 487/487).
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w4044State"))
            {
                _state = sentinel["__w4044State"] as Hashtable;
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
            SqlInstance, SqlCredential, Name, Type, Protocol, Role, EndpointEncryption,
            EncryptionAlgorithm, AuthenticationOrder, Certificate, IPAddress, Port, SslPort,
            Owner, EnableException.ToBool(),
            TestBound(nameof(Name)), TestBound(nameof(Owner)), TestBound(nameof(SslPort)),
            TestBound(nameof(AuthenticationOrder)), _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and cmp-proven byte-exact after
    // stripping four -FunctionName appends and reversing the four Test-Bound rewrites (SOURCE
    // comments). The gate uses the inner block's own $Pscmdlet; the dot-block preserves the
    // source's early return. The W3-082 prompt-state transplant brackets the body.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Name, $Type, $Protocol, $Role, $EndpointEncryption, $EncryptionAlgorithm, $AuthenticationOrder, $Certificate, $IPAddress, $Port, $SslPort, $Owner, $EnableException, $__boundName, $__boundOwner, $__boundSslPort, $__boundAuthenticationOrder, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string]$Name, [string]$Type, [string]$Protocol, [string]$Role, [string]$EndpointEncryption, [string]$EncryptionAlgorithm, [string]$AuthenticationOrder, [string]$Certificate, [System.Net.IPAddress]$IPAddress, [int]$Port, [int]$SslPort, [string]$Owner, $EnableException, $__boundName, $__boundOwner, $__boundSslPort, $__boundAuthenticationOrder, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified)
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "New-DbaEndpoint: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if (-not $__boundName) { # SOURCE: if ((Test-Bound -ParameterName Name -Not)) {
            if ($Type -eq 'DatabaseMirroring') {
                $Name = 'hadr_endpoint'
            } else {
                Stop-Function -Message "Name is required when Type is not DatabaseMirroring" -FunctionName New-DbaEndpoint
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaEndpoint
            }

            if (-not $__boundOwner) { # SOURCE: if (-not (Test-Bound -ParameterName Owner)) {
                $Owner = Get-SaLoginName -SqlInstance $server
            }

            if ($Certificate) {
                $cert = Get-DbaDbCertificate -SqlInstance $server -Certificate $Certificate
                if (-not $cert) {
                    Stop-Function -Message "Certificate $Certificate does not exist on $instance" -Target $Certificate -Continue -FunctionName New-DbaEndpoint
                }
            }

            # Thanks to https://github.com/mmessano/PowerShell/blob/master/SQL-ConfigureDatabaseMirroring.ps1
            if ($Port) {
                $tcpPort = $port
            } else {
                $thisport = (Get-DbaEndpoint -SqlInstance $server).Protocol.Tcp
                $measure = $thisport | Measure-Object ListenerPort -Maximum

                if ($thisport.ListenerPort -eq 0) {
                    $tcpPort = 5022
                } elseif ($measure.Maximum) {
                    $maxPort = $measure.Maximum
                    #choose a random port that is greater than the current max port
                    $tcpPort = $maxPort + (New-Object Random).Next(1, 500)
                } else {
                    $maxPort = 5000
                    #choose a random port that is greater than the current max port
                    $tcpPort = $maxPort + (New-Object Random).Next(1, 500)
                }
            }

            if ($Pscmdlet.ShouldProcess($server.Name, "Creating endpoint $Name of type $Type using protocol $Protocol and if TCP then using IPAddress $IPAddress and Port $tcpPort")) {
                try {
                    $endpoint = New-Object Microsoft.SqlServer.Management.Smo.EndPoint $server, $Name
                    $endpoint.ProtocolType = [Microsoft.SqlServer.Management.Smo.ProtocolType]::$Protocol
                    $endpoint.EndpointType = [Microsoft.SqlServer.Management.Smo.EndpointType]::$Type
                    $endpoint.Owner = $Owner
                    if ($Protocol -eq "TCP") {
                        $endpoint.Protocol.Tcp.ListenerIPAddress = $IPAddress
                        $endpoint.Protocol.Tcp.ListenerPort = $tcpPort
                        $endpoint.Payload.DatabaseMirroring.ServerMirroringRole = [Microsoft.SqlServer.Management.Smo.ServerMirroringRole]::$Role
                        if ($__boundSslPort) { # SOURCE: if (Test-Bound -ParameterName SslPort) {
                            $endpoint.Protocol.Http.SslPort = $SslPort
                        }
                        $endpoint.Payload.DatabaseMirroring.EndpointEncryption = [Microsoft.SqlServer.Management.Smo.EndpointEncryption]::$EndpointEncryption
                        $endpoint.Payload.DatabaseMirroring.EndpointEncryptionAlgorithm = [Microsoft.SqlServer.Management.Smo.EndpointEncryptionAlgorithm]::$EncryptionAlgorithm
                        if ($__boundAuthenticationOrder) { # SOURCE: if (Test-Bound -ParameterName AuthenticationOrder) {
                            $endpoint.Payload.DatabaseMirroring.EndpointAuthenticationOrder = [Microsoft.SqlServer.Management.Smo.EndpointAuthenticationOrder]::$AuthenticationOrder
                        }
                    }
                    if ($Certificate) {
                        $outscript = $endpoint.Script()
                        $outscript = $outscript.Replace("ROLE = ALL,", "ROLE = ALL, AUTHENTICATION = CERTIFICATE $cert,")
                        $server.Query($outscript)
                    } else {
                        $null = $endpoint.Create()
                    }

                    $server.Endpoints.Refresh()
                    Get-DbaEndpoint -SqlInstance $server -Endpoint $name
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName New-DbaEndpoint
                }
            }
        }
    }

    @{ __w4044State = @{ shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $Name $Type $Protocol $Role $EndpointEncryption $EncryptionAlgorithm $AuthenticationOrder $Certificate $IPAddress $Port $SslPort $Owner $EnableException $__boundName $__boundOwner $__boundSslPort $__boundAuthenticationOrder $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}