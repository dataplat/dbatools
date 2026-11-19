#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports the service master key of one or more SQL Server instances to password-protected key files.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the connection, the SMO
/// export call, path handling, the output decoration, and dbatools stream and error handling stay
/// observable-identical to the script implementation.
/// </para>
/// <para>
/// The script's begin block only substituted the key credential's password for the SecurePassword;
/// that deterministic substitution is done here in C# (the SecureString is never converted to plain
/// text), so the command needs a single process hop. The export password rides into the hop as a live
/// SecureString and is turned into plain text only at the SMO export call, and only inside the
/// ShouldProcess gate - so -WhatIf never materializes a plain-text password.
/// </para>
/// </remarks>
[Cmdlet(VerbsData.Backup, "DbaServiceMasterKey", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class BackupDbaServiceMasterKeyCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>A credential whose password is used to encrypt the exported service master key.</summary>
    [Parameter(Position = 2)]
    public PSCredential? KeyCredential { get; set; }

    /// <summary>The password that encrypts the exported service master key.</summary>
    [Parameter(Position = 3)]
    [Alias("Password")]
    public System.Security.SecureString? SecurePassword { get; set; }

    /// <summary>The directory the exported files are written to; defaults to the instance backup directory.</summary>
    [Parameter(Position = 4)]
    public string? Path { get; set; }

    /// <summary>An explicit base file name for the exported key file.</summary>
    [Parameter(Position = 5)]
    public string? FileBaseName { get; set; }

    private System.Security.SecureString? _promptedSecurePassword;

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Exports the service master key for one pipeline record.</summary>
    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // PS begin: "if ($KeyCredential) { $SecurePassword = $KeyCredential.Password }". A bound
        // KeyCredential replaces SecurePassword outright, even if its password is empty - so this is a
        // ternary on whether KeyCredential was supplied, never a null-coalesce on the value. The
        // SecureString is passed on as-is; it is not converted here.
        System.Security.SecureString? effectivePassword = KeyCredential != null
            ? KeyCredential.Password
            : SecurePassword ?? _promptedSecurePassword;

        // [DEF-001] streamed via InvokeScopedStreaming: the body loops $SqlInstance emitting one
        // key object per instance (Select-DefaultView) and carries loop-local -Continue
        // Stop-Functions that throw terminating under -EnableException; a buffered InvokeScoped
        // would lose an earlier instance's already-emitted key object when a later instance throws.
        // Streaming yields each record as produced, so earlier emits survive. The command-specific
        // sentinel carries a password entered interactively in the hop so later pipeline records
        // reuse the source function's answer.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__backupDbaServiceMasterKeyProcess"))
            {
                if (sentinel["__backupDbaServiceMasterKeyProcess"] is Hashtable state &&
                    state["SecurePassword"] is System.Security.SecureString promptedSecurePassword)
                {
                    _promptedSecurePassword = promptedSecurePassword;
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
            SqlInstance, SqlCredential, KeyCredential, effectivePassword, Path, FileBaseName,
            EnableException.ToBool(), this,
            TestBound(nameof(Path)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the ENTIRE process body VERBATIM per record. The begin credential-to-password substitution
    // is applied in C# (effectivePassword), so the hop receives $SecurePassword already resolved.
    // Substitutions only: $Pscmdlet -> $__realCmdlet; "Test-Bound -ParameterName Path -Not" -> the
    // carried "-not $__boundPath" flag; and -FunctionName on the direct Stop-Function/Write-Message
    // calls. The Read-Host prompt path is preserved verbatim - it is only reached when neither a
    // password nor a key credential is supplied, exactly as in the source, and is not exercised by
    // the tests.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $KeyCredential, $SecurePassword, $Path, $FileBaseName, $EnableException, $__realCmdlet, $__boundPath, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [PSCredential]$KeyCredential, [Security.SecureString]$SecurePassword, [string]$Path, [string]$FileBaseName, $EnableException, $__realCmdlet, $__boundPath, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Backup-DbaServiceMasterKey
        }

        if (-not $__boundPath) {
            $Path = $server.BackupDirectory
        }

        if (-not $Path) {
            Stop-Function -Message "Path discovery failed. Please explicitly specify -Path" -Target $server -Continue -FunctionName Backup-DbaServiceMasterKey
        }

        if (!(Test-DbaPath -SqlInstance $server -Path $Path)) {
            Stop-Function -Message "$instance cannot access $Path" -Target $server -Continue -FunctionName Backup-DbaServiceMasterKey
        }


        $masterkey = $server.ServiceMasterKey

        # If you pass a password param, then you will not be prompted, but it wouldn't be a good idea to build in insecurity
        if (-not $SecurePassword -and -not $KeyCredential) {
            $SecurePassword = Read-Host -AsSecureString -Prompt "You must enter an encryption password for $instance"
            $SecurePassword2 = Read-Host -AsSecureString -Prompt "Type the password again"

            if (($SecurePassword | ConvertFrom-SecurePass) -ne ($SecurePassword2 | ConvertFrom-SecurePass)) {
                Stop-Function -Message "Passwords do not match" -Continue -FunctionName Backup-DbaServiceMasterKey
            }
        }

        $Path = $Path.TrimEnd("\")
        $Path = $Path.TrimEnd("/")
        $fileinstance = $instance.ToString().Replace('\', '$')
        $targetBaseName = "$fileinstance-servicemasterkey"
        if ($FileBaseName) {
            $targetBaseName = $FileBaseName
        }

        $exportFileName = Join-DbaPath -SqlInstance $server -Path $Path -ChildPath "$targetBaseName.key"

        # if the base file name exists, then default to old style of appending a timestamp
        if (Test-DbaPath -SqlInstance $server -Path $exportFileName) {
            $time = Get-Date -Format yyyyMMddHHmmss
            $exportFileName = Join-DbaPath -SqlInstance $server -Path $Path -ChildPath "$targetBaseName-$time.key"
            # Sleep for a second to avoid another export in the same second
            Start-Sleep -Seconds 1
        }

        if ($__realCmdlet.ShouldProcess($instance, "Backing up service master key to $exportFileName")) {
            try {
                $masterkey.Export($exportFileName, ($SecurePassword | ConvertFrom-SecurePass))
                $status = "Success"
            } catch {
                $status = "Failure"
                Write-Message -Level Warning -Message "Backup failure: $($_.Exception.InnerException)" -FunctionName Backup-DbaServiceMasterKey -ModuleName "dbatools"
            }

            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Filename -value $exportFileName
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Status -value $status

            Select-DefaultView -InputObject $masterkey -Property ComputerName, InstanceName, SqlInstance, 'Filename as Path', Status
        }
    }
    @{ __backupDbaServiceMasterKeyProcess = @{ SecurePassword = $SecurePassword } }
} $SqlInstance $SqlCredential $KeyCredential $SecurePassword $Path $FileBaseName $EnableException $__realCmdlet $__boundPath $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

