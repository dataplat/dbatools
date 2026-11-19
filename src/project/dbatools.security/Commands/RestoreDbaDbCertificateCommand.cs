#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Imports database certificates from .cer files (and their private keys) into a database.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the directory-vs-file path
/// expansion, the certificate-name derivation chain, the two-stage SMO Create fallback, the ShouldProcess
/// gate, and dbatools stream and error handling stay observable-identical to the script implementation.
/// </para>
/// <para>
/// SqlInstance is Mandatory singular; pipeline input arrives ByPropertyName on Path (aliases
/// FullName/ExportPath) and KeyFilePath (alias Key), which rebind on every record - and the VFP-local
/// classification shows no branch-assigned local read outside its iteration (the body's lowercase $path
/// assignment overwrites the Path parameter under the directory branch, but per-record rebinding resets it
/// exactly like the function world), so this is a straightforward PER-RECORD streaming hop. The body is
/// dot-sourced inside the hop so the connection-failure early return stays record-local. Streaming via
/// InvokeScopedStreaming: the body emits one certificate object per import inside the gate and a later path
/// can Stop-Function under -EnableException. Both string-array parameters carry the conservative
/// PsStringArrayCast (null-element bind parity; passes everything else through so ByPropertyName binding is
/// never preempted).
/// </para>
/// <para>
/// DecryptionPassword has an INTERACTIVE computed default - (Read-Host -AsSecureString) evaluated only when
/// the parameter is unbound - so BeginProcessing resolves it ONCE per invocation through a Read-Host
/// mini-hop, exactly like a script parameter default: a multi-record pipeline prompts once, and an
/// explicitly bound value (including null) suppresses the prompt (the accepted interactive-prompt
/// deviation class). Both SecureStrings ride live; the source's own
/// ConvertFrom-SecurePass flattens them only inside the ShouldProcess gate, so -WhatIf never materializes a
/// password. The $PSBoundParameters.Name truthiness read carries as the raw bound value. The single
/// $Pscmdlet.ShouldProcess gate routes to $__realCmdlet (ConfirmImpact High).
/// </para>
/// </remarks>
[Cmdlet(VerbsData.Restore, "DbaDbCertificate", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "Default")]
public sealed class RestoreDbaDbCertificateCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Certificate files or directories to import from.</summary>
    [Parameter(Mandatory = true, ValueFromPipelineByPropertyName = true, Position = 2)]
    [Alias("FullName", "ExportPath")]
    [PsStringArrayCast]
    public string[]? Path { get; set; }

    /// <summary>Private key files matching the certificates.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 3)]
    [Alias("Key")]
    [PsStringArrayCast]
    public string[]? KeyFilePath { get; set; }

    /// <summary>Password that encrypts the private key inside the database.</summary>
    [Parameter(Position = 4)]
    public System.Security.SecureString? EncryptionPassword { get; set; }

    /// <summary>Database to import the certificate into. Defaults to master.</summary>
    [Parameter(Position = 5)]
    public string? Database { get; set; } = "master";

    /// <summary>Name for the restored certificate. Defaults to a name derived from the file.</summary>
    [Parameter(Position = 6)]
    public string? Name { get; set; }

    /// <summary>Password the certificate backup was encrypted with. Prompted for when omitted.</summary>
    [Parameter(Position = 7)]
    [Alias("Password", "SecurePassword")]
    public System.Security.SecureString? DecryptionPassword { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>DecryptionPassword resolved once per invocation, exactly like the script's parameter default.</summary>
    private System.Security.SecureString? _resolvedDecryptionPassword;

    /// <summary>Resolves the DecryptionPassword default before any pipeline record arrives.</summary>
    protected override void BeginProcessing()
    {
        // The script's (Read-Host -AsSecureString) parameter default evaluates ONCE per invocation and
        // ONLY when the parameter is unbound - an explicitly bound value, including null, suppresses it.
        // Resolving here keeps a multi-record pipeline from prompting once per record.
        if (TestBound(nameof(DecryptionPassword)))
        {
            _resolvedDecryptionPassword = DecryptionPassword;
        }
        else
        {
            foreach (PSObject? item in NestedCommand.InvokeScoped(this, DecryptionPasswordPromptScript))
            {
                _resolvedDecryptionPassword = item?.BaseObject as System.Security.SecureString;
            }
        }
    }

    /// <summary>Imports the certificates for the current pipeline record.</summary>
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
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Path, KeyFilePath, EncryptionPassword, Database, Name,
            _resolvedDecryptionPassword,
            TestBound(nameof(Name)) ? Name : null,
            EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // The source's DecryptionPassword parameter default, run in BeginProcessing when the parameter is
    // unbound so the prompt fires once per invocation like a script parameter default. It evaluates
    // INSIDE the dbatools module scope, exactly where the script function's default expression runs -
    // a caller-local Read-Host function or alias is invisible there in both worlds. The discovery
    // commands are module-qualified so a caller-local Get-Module/Where-Object/Select-Object shim
    // cannot divert the lookup either.
    private const string DecryptionPasswordPromptScript = """
$__dbatoolsModule = Microsoft.PowerShell.Core\Get-Module -Name dbatools | Microsoft.PowerShell.Core\Where-Object ModuleType -eq "Script" | Microsoft.PowerShell.Utility\Select-Object -First 1
& $__dbatoolsModule { Read-Host "Decryption password" -AsSecureString }
""";

    // PS: the process body VERBATIM, dot-sourced for the early return. Substitutions only: $Pscmdlet ->
    // $__realCmdlet (the ShouldProcess gate); $PSBoundParameters.Name -> the carried raw bound value;
    // -FunctionName on the 4 DIRECT Stop-Function calls; -FunctionName + -ModuleName "dbatools" on the 5
    // DIRECT Write-Message calls. DecryptionPassword always arrives resolved (bound value, or the
    // once-per-invocation Read-Host default from BeginProcessing).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Path, $KeyFilePath, $EncryptionPassword, $Database, $Name, $DecryptionPassword, $__rawBoundName, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Path, [string[]]$KeyFilePath, [System.Security.SecureString]$EncryptionPassword, [string]$Database, [string]$Name, $DecryptionPassword, $__rawBoundName, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        . {
        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -FunctionName Restore-DbaDbCertificate
            return
        }

        foreach ($dir in $Path) {
            if (-not (Test-DbaPath -SqlInstance $server -Path $dir)) {
                Stop-Function -Message "$SqlInstance cannot access $dir" -Continue -Target $dir -FunctionName Restore-DbaDbCertificate
            }

            try {
                $isdir = ($server.Query("EXEC master.dbo.xp_fileexist '$dir'")).Item(1)
            } catch {
                Stop-Function -Message $_ -ErrorRecord $_ -Target $server.Name -Continue -FunctionName Restore-DbaDbCertificate
            }
            if ($isdir) {
                Write-Message -Level Verbose -Message "Path is a directory - processing all certs within" -FunctionName Restore-DbaDbCertificate -ModuleName "dbatools"
                $path = (Get-DbaFile -SqlInstance $server -Path $dir -FileType cer).Filename
            }

            foreach ($fullname in $path) {
                Write-Message -Level Verbose -Message ("Processing {0}" -f $fullname) -FunctionName Restore-DbaDbCertificate -ModuleName "dbatools"

                $directory = Split-Path $fullname
                $filename = Split-Path $fullname -Leaf
                $certname = [io.path]::GetFileNameWithoutExtension($filename)
                $fullcertname = Join-DbaPath -SqlInstance $server -Path $directory -ChildPath "$certname.cer"

                if (-not $KeyFilePath) {
                    $privatekey = Join-DbaPath -SqlInstance $server -Path $directory -ChildPath "$certname.pvk"
                } else {
                    $privatekey = $KeyFilePath
                }

                $instance = $server.Name
                $fileinstance = $instance.ToString().Replace('\', '$')
                $certname = $certname.Replace("$fileinstance-$Database-", "")
                if ($certname -match "-$Database-") {
                    $tempcertname = $certname -split "-" | Select-Object -First 1 -Skip 2
                    if ($tempcertname) {
                        $certname = $tempcertname
                    }
                }

                if ($certname -match '([0-9]{4})(0[1-9]|1[0-2])(0[1-9]|[1-2][0-9]|3[0-1])(2[0-3]|[01][0-9])([0-5][0-9])([0-5][0-9])') {
                    $certname = $certname.Replace($matches[0], "")
                }
                $certname = $certname.TrimEnd("-")
                if ($__rawBoundName) {
                    $certificatename = $Name
                } else {
                    $certificatename = $certname
                }

                if ($__realCmdlet.ShouldProcess("$certificatename on $SqlInstance", "Importing certificate to $Database")) {
                    $smocert = New-Object Microsoft.SqlServer.Management.Smo.Certificate
                    $smocert.Name = $certificatename
                    $smocert.Parent = $server.Databases[$Database]
                    Write-Message -Level Verbose -Message "Creating Certificate: $certificatename" -FunctionName Restore-DbaDbCertificate -ModuleName "dbatools"
                    Write-Message -Level Verbose -Message "Full certificate path: $fullcertname" -FunctionName Restore-DbaDbCertificate -ModuleName "dbatools"
                    Write-Message -Level Verbose -Message "Private key: $privatekey" -FunctionName Restore-DbaDbCertificate -ModuleName "dbatools"
                    try {
                        if ($EncryptionPassword) {
                            $smocert.Create($fullcertname, 1, $privatekey, ($DecryptionPassword | ConvertFrom-SecurePass), ($EncryptionPassword | ConvertFrom-SecurePass))
                        } else {
                            $smocert.Create($fullcertname, 1, $privatekey, ($DecryptionPassword | ConvertFrom-SecurePass))
                        }
                    } catch {
                        try {
                            if ($EncryptionPassword) {
                                $smocert.Create($fullcertname, $([Microsoft.SqlServer.Management.Smo.CertificateSourceType]::"File"), $privatekey, ($DecryptionPassword | ConvertFrom-SecurePass), ($EncryptionPassword | ConvertFrom-SecurePass))
                            } else {
                                $smocert.Create($fullcertname, $([Microsoft.SqlServer.Management.Smo.CertificateSourceType]::"File"), $privatekey, ($DecryptionPassword | ConvertFrom-SecurePass))
                            }
                        } catch {
                            Stop-Function -Message $_ -ErrorRecord $_ -Target $instance -Continue -FunctionName Restore-DbaDbCertificate
                        }
                    }
                    Get-DbaDbCertificate -SqlInstance $server -Database $Database -Certificate $smocert.Name
                }
            }
        }
        }
} $SqlInstance $SqlCredential $Path $KeyFilePath $EncryptionPassword $Database $Name $DecryptionPassword $__rawBoundName $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
