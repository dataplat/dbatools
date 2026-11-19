#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports SQL Server credentials (optionally with decrypted passwords) to a .sql script. Port of
/// public/Export-DbaCredential.ps1 (W3-014). Two blocks: the begin block runs Test-ExportDirectory
/// ONCE (directory prep, no cross-block state) and the process block does the per-instance work, so
/// the port keeps them as two hops (BeginProcessing / ProcessRecord). Only the process hop STREAMS
/// (DEF-001 cond1+cond2: it emits per instance - $sql on Passthru, Get-ChildItem on file write - AND
/// has reachable Stop-Function -Continue at Connect-DbaInstance / the file write); begin emits
/// nothing. The source reads $PSBoundParameters.Path / $PSBoundParameters.FilePath (explicitly bound
/// values, null when unbound) for Get-ExportFilePath naming - carried verbatim as value-carriers -
/// while the DEFAULTED $Path (Get-DbatoolsConfigValue) is used only by Test-ExportDirectory in begin
/// (the process block, unlike Export-DbaLinkedServer, has no "$Path -or $FilePath" gate). No
/// ShouldProcess. SqlInstance is NOT mandatory and NOT pipeline-bound (matches the source). Positions
/// match the retired function's implicit positional binding (non-switch params 0..5; switches null).
/// The CREATE CREDENTIAL / SECRET password-emitting block is preserved VERBATIM (security-sensitive).
/// Substitutions only: $PSBoundParameters.Path/.FilePath -> the carried bound values, explicit
/// -FunctionName Export-DbaCredential on Stop-Function (W1-090). Surface pinned by
/// migration/baselines/Export-DbaCredential.json.
/// </summary>
[Cmdlet(VerbsData.Export, "DbaCredential")]
public sealed class ExportDbaCredentialCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Alternative Windows credential for password decryption.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    /// <summary>Directory for the exported script (defaults to the configured export path).</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string? Path { get; set; }

    /// <summary>Explicit output file path.</summary>
    [Parameter(Position = 4)]
    [Alias("OutFile", "FileName")]
    [PsStringCast]
    public string? FilePath { get; set; }

    /// <summary>Credential identity/identities to include.</summary>
    [Parameter(Position = 5)]
    [PsStringArrayCast]
    public string[]? Identity { get; set; }

    /// <summary>Exports with a placeholder password instead of the decrypted secret (no DAC needed).</summary>
    [Parameter]
    public SwitchParameter ExcludePassword { get; set; }

    /// <summary>Appends to the output file instead of overwriting.</summary>
    [Parameter]
    public SwitchParameter Append { get; set; }

    /// <summary>Emits the script to the pipeline instead of writing a file.</summary>
    [Parameter]
    public SwitchParameter Passthru { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

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
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Credential, BoundValue("Path"), BoundValue("FilePath"), Identity,
            ExcludePassword.ToBool(), Append.ToBool(), Passthru.ToBool(), EnableException.ToBool(),
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
    // $PSBoundParameters.FilePath -> the carried bound values ($__pathBound / $__filePathBound, null
    // when unbound); explicit -FunctionName Export-DbaCredential on Stop-Function (W1-090). The
    // CREATE CREDENTIAL / SECRET password block is VERBATIM (security-sensitive).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Credential, $__pathBound, $__filePathBound, $Identity, $ExcludePassword, $Append, $Passthru, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [PSCredential]$Credential, $__pathBound, $__filePathBound, [string[]]$Identity, $ExcludePassword, $Append, $Passthru, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # Named-wrapper shim: the process body runs inside a function carrying the command's name,
    # so call-stack-deriving helpers see Export-DbaCredential exactly as in the function world -
    # Get-ExportFilePath builds the export filename from (Get-PSCallStack)[1].Command, and the
    # anonymous scriptblock frame otherwise put a literal <scriptblock> marker in the filename.
    # The dot-sourced invocation keeps the body in the hop scope, so the interrupt latch and
    # any cross-record state behave unchanged.
    function Export-DbaCredential {
    if (Test-FunctionInterrupt) { return }

    if ($IsLinux -or $IsMacOS) {
        Stop-Function -Message "This command is not supported on Linux or macOS" -FunctionName Export-DbaCredential
        return
    }

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
                    Write-Message -Level Verbose -Message "Reusing dedicated admin connection for password retrieval." -FunctionName Export-DbaCredential -ModuleName "dbatools"
                    $server = $instance.InputObject
                } else {
                    Write-Message -Level Verbose -Message "Opening dedicated admin connection for password retrieval." -FunctionName Export-DbaCredential -ModuleName "dbatools"
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9 -DedicatedAdminConnection -WarningAction SilentlyContinue
                    $dacOpened = $true
                }
            } else {
                Write-Message -Level Verbose -Message "Opening or reusing normal connection because passwords are excluded." -FunctionName Export-DbaCredential -ModuleName "dbatools"
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Export-DbaCredential
        }

        if ($ExcludePassword) {
            $credentials = foreach ($cred in $server.Credentials) {
                [PSCustomObject]@{
                    Name            = $cred.Name
                    Quotename       = $server.Query("SELECT QUOTENAME('$($cred.Name.Replace("'", "''"))') AS Quotename").Quotename
                    Identity        = $cred.Identity.ToString()
                    Password        = '<EnterStrongPasswordHere>'
                    MappedClassType = $cred.MappedClassType
                    ProviderName    = $cred.ProviderName
                }
            }
        } else {
            $credentials = Get-DecryptedObject -SqlInstance $server -Credential $Credential -Type Credential -EnableException:$EnableException
        }

        if ($Identity) {
            $credentials = $credentials | Where-Object Identity -in $Identity
        }

        if (-not $credentials) {
            Write-Message -Level Verbose -Message "Nothing to export" -FunctionName Export-DbaCredential -ModuleName "dbatools"
            continue
        }

        $FilePath = Get-ExportFilePath -Path $__pathBound -FilePath $__filePathBound -Type sql -ServerName $instance

        $sql = @()

        foreach ($cred in $credentials) {
            $quotename = $cred.Quotename
            $credName = $cred.Name.Replace("'", "''")
            $identity = $cred.Identity.Replace("'", "''")
            $password = $cred.Password.Replace("'", "''")
            $cryptoSql = ""
            if ($cred.MappedClassType -like 'Cryptographic*') {
                $providerName = $cred.ProviderName
                $cryptoSql = " FOR CRYPTOGRAPHIC PROVIDER $providerName"
            }
            $sql += "IF NOT EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'$credName') CREATE CREDENTIAL $quotename WITH IDENTITY = N'$identity', SECRET = N'$password'" + $cryptoSql
        }

        if ($Passthru) {
            $sql
        } else {
            try {
                if ($Append) {
                    Add-Content -Path $FilePath -Value $sql
                } else {
                    Set-Content -Path $FilePath -Value $sql
                }
                Get-ChildItem -Path $FilePath
            } catch {
                Stop-Function -Message "Can't write to $FilePath" -ErrorRecord $_ -Continue -FunctionName Export-DbaCredential
            }
        }

        if ($dacOpened) {
            $null = $server | Disconnect-DbaInstance -WhatIf:$false
        }
    }
    }
    . Export-DbaCredential
} $SqlInstance $SqlCredential $Credential $__pathBound $__filePathBound $Identity $ExcludePassword $Append $Passthru $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
