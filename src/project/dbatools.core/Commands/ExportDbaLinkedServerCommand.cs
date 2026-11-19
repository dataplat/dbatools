#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports linked servers (optionally with decrypted passwords) to a .sql script. Port of
/// public/Export-DbaLinkedServer.ps1 (W3-015). Two blocks: the begin block runs
/// Test-ExportDirectory ONCE (directory prep, no cross-block state) and the process block does
/// the per-instance work, so the port keeps them as two hops (BeginProcessing / ProcessRecord).
/// Only the process hop STREAMS (DEF-001 cond1+cond2: it emits per instance - $sql on Passthru,
/// Get-ChildItem on file write, or $sql otherwise - AND has reachable Stop-Function -Continue at
/// Connect-DbaInstance / Get-DecryptedObject / the file write); begin emits nothing.
/// PARAMETER-VALUE carriers: the source reads $PSBoundParameters.Path / $PSBoundParameters.FilePath
/// (the EXPLICITLY bound values, null when unbound) to drive Get-ExportFilePath's naming - carried
/// verbatim - while the DEFAULTED $Path (Get-DbatoolsConfigValue 'Path.DbatoolsExport') is what
/// Test-ExportDirectory (begin) and the "$Path -or $FilePath" write-gate (process line 195) use, so
/// $Path's default is re-applied in BOTH hops. No ShouldProcess. Positions match the retired
/// function's implicit positional binding (non-switch params 0..6; switches null). The password
/// decryption / rmtpassword-substitution block is preserved VERBATIM (security-sensitive).
/// Substitutions only: $PSBoundParameters.Path/.FilePath -> the carried bound values, explicit
/// -FunctionName Export-DbaLinkedServer on Stop-Function (W1-090). Surface pinned by
/// migration/baselines/Export-DbaLinkedServer.json.
/// </summary>
[Cmdlet(VerbsData.Export, "DbaLinkedServer")]
public sealed class ExportDbaLinkedServerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Linked server name(s) to include.</summary>
    [Parameter(Position = 1)]
    public string[]? LinkedServer { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 2)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Alternative Windows credential for password decryption.</summary>
    [Parameter(Position = 3)]
    public PSCredential? Credential { get; set; }

    /// <summary>Directory for the exported script (defaults to the configured export path).</summary>
    [Parameter(Position = 4)]
    public string? Path { get; set; }

    /// <summary>Explicit output file path.</summary>
    [Parameter(Position = 5)]
    [Alias("OutFile", "FileName")]
    public string? FilePath { get; set; }

    /// <summary>Exports without the linked server passwords (no DAC needed).</summary>
    [Parameter]
    public SwitchParameter ExcludePassword { get; set; }

    /// <summary>Appends to the output file instead of overwriting.</summary>
    [Parameter]
    public SwitchParameter Append { get; set; }

    /// <summary>Emits the script to the pipeline instead of writing a file.</summary>
    [Parameter]
    public SwitchParameter Passthru { get; set; }

    /// <summary>Linked server object(s) piped from Get-DbaLinkedServer.</summary>
    [Parameter(Position = 6)]
    public Microsoft.SqlServer.Management.Smo.LinkedServer[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Cross-record carriers for $rmtuser + $password (W3-015 DEF-012): the source's process-block
    // $rmtuser/$password (assigned only under $map.Identity -isnot [dbnull], read unconditionally in the
    // rmtpassword substitution) persist across piped records AND across maps/linked-servers/instances
    // within a record, so a dbnull-Identity $map after a non-dbnull one substitutes the PRIOR credential.
    // Each record runs in a fresh hop scope that loses that, so the finals are captured OUT via the
    // sentinel and seeded back INTO the next record, reproducing (not sanitizing) the legacy stale-carry.
    // PLAIN VALUE carry (strings, may be null); no assigned-flag (per plan / W2-075).
    private object? _carriedRmtuser;
    private object? _carriedPassword;

    protected override void BeginProcessing()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BeginScript,
            BoundValue("Path"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__exportLsCarry"))
            {
                if (sentinel["__exportLsCarry"] is Hashtable state)
                {
                    _carriedRmtuser = state["Rmtuser"];
                    _carriedPassword = state["Password"];
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
            SqlInstance, LinkedServer, SqlCredential, Credential, BoundValue("Path"), BoundValue("FilePath"),
            ExcludePassword.ToBool(), Append.ToBool(), Passthru.ToBool(), InputObject, EnableException.ToBool(),
            _carriedRmtuser, _carriedPassword,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private object? BoundValue(string name)
    {
        return MyInvocation.BoundParameters.TryGetValue(name, out object? value) ? value : null;
    }

    // PS: the begin block. $Path's runtime default (Get-DbatoolsConfigValue) is re-applied when the
    // parameter was not bound, then Test-ExportDirectory runs ONCE. Verbatim otherwise.
    private const string BeginScript = """
param($__pathBound, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__pathBound, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $Path = if ($null -ne $__pathBound) { $__pathBound } else { Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport' }
    $null = Test-ExportDirectory -Path $Path
} $__pathBound $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process body VERBATIM per record. Substitutions only: $PSBoundParameters.Path /
    // $PSBoundParameters.FilePath -> the carried bound values ($__pathBound / $__filePathBound,
    // null when unbound); the DEFAULTED $Path (for the line-195 write-gate) is re-applied at the
    // top; explicit -FunctionName Export-DbaLinkedServer on Stop-Function (W1-090). The password
    // decryption / rmtpassword substitution is VERBATIM (security-sensitive).
    private const string ProcessScript = """
param($SqlInstance, $LinkedServer, $SqlCredential, $Credential, $__pathBound, $__filePathBound, $ExcludePassword, $Append, $Passthru, $InputObject, $EnableException, $__carriedRmtuser, $__carriedPassword, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [string[]]$LinkedServer, [PSCredential]$SqlCredential, [PSCredential]$Credential, $__pathBound, $__filePathBound, $ExcludePassword, $Append, $Passthru, [Microsoft.SqlServer.Management.Smo.LinkedServer[]]$InputObject, $EnableException, $__carriedRmtuser, $__carriedPassword, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $Path = if ($null -ne $__pathBound) { $__pathBound } else { Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport' }

    # Named-wrapper shim: the process body runs inside a function carrying the command's name,
    # so call-stack-deriving helpers see Export-DbaLinkedServer exactly as in the function world -
    # Get-ExportFilePath builds the export filename from (Get-PSCallStack)[1].Command, and the
    # anonymous scriptblock frame otherwise put a literal <scriptblock> marker in the filename.
    # The dot-sourced invocation keeps the body in the hop scope, so the interrupt latch and
    # any cross-record state behave unchanged.
    function Export-DbaLinkedServer {
    if (Test-FunctionInterrupt) { return }

    if ($IsLinux -or $IsMacOS) {
        Stop-Function -Message "This command is not supported on Linux or macOS" -FunctionName Export-DbaLinkedServer
        return
    }

    $rmtuser = $__carriedRmtuser
    $password = $__carriedPassword

    try {
    foreach ($instance in $SqlInstance) {
        try {
            # Do we need a dedicated admin connection to the source for password retrieval?
            # If passwords are excluded, we don't need a DAC
            if ($ExcludePassword) { $dacNeeded = $false } else { $dacNeeded = $true }

            # Do we have a dedicated admin connection already?
            $dacConnected = $instance.Type -eq 'Server' -and $instance.InputObject.Name -match '^ADMIN:'

            $dacOpened = $false
            if ($dacNeeded) {
                if ($dacConnected) {
                    Write-Message -Level Verbose -Message "Reusing dedicated admin connection for password retrieval." -FunctionName Export-DbaLinkedServer -ModuleName "dbatools"
                    $server = $instance.InputObject
                } else {
                    Write-Message -Level Verbose -Message "Opening dedicated admin connection for password retrieval." -FunctionName Export-DbaLinkedServer -ModuleName "dbatools"
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9 -DedicatedAdminConnection -WarningAction SilentlyContinue
                    $dacOpened = $true
                }
            } else {
                Write-Message -Level Verbose -Message "Opening or reusing normal connection because passwords are excluded." -FunctionName Export-DbaLinkedServer -ModuleName "dbatools"
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            $InputObject = $server.LinkedServers
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Export-DbaLinkedServer
        }

        if ($LinkedServer) {
            $InputObject = $InputObject | Where-Object Name -in $LinkedServer
        }

        if (-not $InputObject) {
            Write-Message -Level Verbose -Message "Nothing to export" -FunctionName Export-DbaLinkedServer -ModuleName "dbatools"
            continue
        }

        $FilePath = Get-ExportFilePath -Path $__pathBound -FilePath $__filePathBound -Type sql -ServerName $instance

        $sql = @()

        if ($ExcludePassword) {
            $sql += $InputObject.Script()
        } else {
            try {
                $decrypted = Get-DecryptedObject -SqlInstance $server -Credential $Credential -Type LinkedServer -EnableException:$EnableException
            } catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_ -FunctionName Export-DbaLinkedServer
            }

            foreach ($ls in $InputObject) {
                $currentls = $decrypted | Where-Object Name -eq $ls.Name
                if ($currentls.Password) {
                    $tempsql = $ls.Script()
                    foreach ($map in $currentls) {
                        if ($map.Identity -isnot [dbnull]) {
                            $rmtuser = $map.Identity.Replace("'", "''")
                            $password = $map.Password.Replace("'", "''")
                        }
                        $tempsql = $tempsql.Replace(' /* For security reasons the linked server remote logins password is changed with ######## */', '')
                        $tempsql = $tempsql.Replace("rmtuser=N'$rmtuser',@rmtpassword='########'", "rmtuser=N'$rmtuser',@rmtpassword='$password'")
                    }
                    $sql += $tempsql
                } else {
                    $sql += $ls.Script()
                }
            }
        }
        if ($Passthru) {
            $sql
        } elseif ($Path -or $FilePath) {
            try {
                if ($Append) {
                    Add-Content -Path $FilePath -Value $sql
                } else {
                    Set-Content -Path $FilePath -Value $sql
                }
                Get-ChildItem -Path $FilePath
            } catch {
                Stop-Function -Message "Can't write to $FilePath" -ErrorRecord $_ -Continue -FunctionName Export-DbaLinkedServer
            }
        } else {
            $sql
        }

        if ($dacOpened) {
            $null = $server | Disconnect-DbaInstance -WhatIf:$false
        }
    }
    } finally {
        @{ __exportLsCarry = @{ Rmtuser = $rmtuser; Password = $password } }
    }
    }
    . Export-DbaLinkedServer
} $SqlInstance $LinkedServer $SqlCredential $Credential $__pathBound $__filePathBound $ExcludePassword $Append $Passthru $InputObject $EnableException $__carriedRmtuser $__carriedPassword $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
