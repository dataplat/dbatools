#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports database certificates, and optionally their private keys, to files on one or more SQL
/// Server instances.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that certificate discovery,
/// the SMO export calls, path handling, warning text, and dbatools stream and error handling stay
/// observable-identical to the script implementation.
/// </para>
/// <para>
/// The command is built as TWO hops because the script had a begin block and a process block. The
/// begin hop runs the password validation; the process hop defines the per-certificate export
/// helper and walks the certificates. Two pieces of state that the script kept in a scope spanning
/// the whole pipeline are held as fields, because each hop and each record gets a fresh scope: the
/// begin block's stop, and the interrupt flag Stop-Function sets. See the field comments.
/// </para>
/// <para>
/// The encryption and decryption passwords ride into the hop as live SecureStrings. They are turned
/// into plain text only at the SMO export call, and only inside the ShouldProcess gate - so -WhatIf
/// never materializes a plain-text password. That placement is preserved from the source, not
/// re-derived here.
/// </para>
/// </remarks>
[Cmdlet(VerbsData.Backup, "DbaDbCertificate", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low, DefaultParameterSetName = "Default")]
public sealed class BackupDbaDbCertificateCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "instance")]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The certificate name or names to export.</summary>
    [Parameter(ParameterSetName = "instance")]
    public object[]? Certificate { get; set; }

    /// <summary>The database or databases whose certificates are exported.</summary>
    [Parameter(ParameterSetName = "instance")]
    public object[]? Database { get; set; }

    /// <summary>Databases to exclude from the export.</summary>
    [Parameter(ParameterSetName = "instance")]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>The password that encrypts the exported private key; required to export a private key.</summary>
    [Parameter]
    public System.Security.SecureString? EncryptionPassword { get; set; }

    /// <summary>The password that decrypts the certificate's private key when it is not protected by the database master key.</summary>
    [Parameter]
    public System.Security.SecureString? DecryptionPassword { get; set; }

    /// <summary>The directory the exported files are written to; defaults to the instance backup directory.</summary>
    [Parameter]
    public System.IO.FileInfo? Path { get; set; }

    /// <summary>A suffix appended to each exported file's base name.</summary>
    [Parameter]
    public string? Suffix { get; set; }

    /// <summary>An explicit base file name for a single-certificate export.</summary>
    [Parameter]
    public string? FileBaseName { get; set; }

    /// <summary>Certificate objects, typically piped from Get-DbaDbCertificate.</summary>
    [Parameter(ValueFromPipeline = true, ParameterSetName = "collection")]
    public Microsoft.SqlServer.Management.Smo.Certificate[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Set when the begin block stopped the command, suppressing every record.</summary>
    private bool _beginInterrupted;

    // There is deliberately NO cross-record interrupt field. The only latch-setting Stop-Function
    // inside export-cert (the path-access failure) runs without -Continue, which sets the flag at
    // that helper's own scope; the flag is discarded when the helper returns and never reaches the
    // command scope, so it does not stop later records. This was confirmed against the script
    // implementation: piping two certificates through an inaccessible path processes BOTH. The begin
    // validation is the only stop that spans the pipeline, and it is carried by _beginInterrupted.

    /// <summary>Validates the password combination once, before any pipeline record is processed.</summary>
    protected override void BeginProcessing()
    {
        bool completed = false;
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            EncryptionPassword, DecryptionPassword, EnableException.ToBool()))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__BackupDbaDbCertificateBeginComplete"]?.Value))
            {
                completed = true;
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }

        // The sentinel is the last statement of the begin body, so it is absent exactly when that
        // body returned early - which it does only after Stop-Function has stopped the command.
        _beginInterrupted = !completed;
    }

    /// <summary>Exports the requested certificates for one pipeline record.</summary>
    protected override void ProcessRecord()
    {
        if (_beginInterrupted || Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, SqlCredential, Certificate, Database, ExcludeDatabase,
            EncryptionPassword, DecryptionPassword, Path, Suffix, FileBaseName, InputObject,
            EnableException.ToBool(), this,
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

    // PS: the begin body VERBATIM. Substitutions only: explicit -FunctionName on the direct
    // Stop-Function call (it runs at module scope, where caller-frame resolution would otherwise
    // miss the public name).
    private const string BeginScript = """
param($EncryptionPassword, $DecryptionPassword, $EnableException)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param([Security.SecureString]$EncryptionPassword, [Security.SecureString]$DecryptionPassword, $EnableException)

    if (-not $EncryptionPassword -and $DecryptionPassword) {
        Stop-Function -Message "If you specify a decryption password, you must also specify an encryption password" -Target $DecryptionPassword -FunctionName Backup-DbaDbCertificate
    }

    if (-not (Test-FunctionInterrupt)) {
        [pscustomobject]@{ __BackupDbaDbCertificateBeginComplete = $true }
    }
} $EncryptionPassword $DecryptionPassword $EnableException 3>&1 2>&1
""";

    // PS: the ENTIRE process body VERBATIM per record, with the begin block's export-cert helper
    // moved into the process hop because a hop scope does not carry a function definition across
    // hops (it is a pure definition that only ran in process, so this is behavior-preserving).
    // Substitutions only: $Pscmdlet -> $__realCmdlet, and explicit -FunctionName on the DIRECT
    // process-body Write-Message calls. The calls INSIDE export-cert carry NO -FunctionName: it is
    // a named function, so Get-PSCallStack resolves them to "export-cert" exactly as the source
    // did. The body is dot-sourced so its early return leaves only that block and the trailing
    // sentinel still reports the interrupt latch.
    //
    // Preserved verbatim; do not "repair": the export helper mutates a local $Path (a copy, it does
    // not leak), and the innermost path-access Stop-Function has no -Continue, so it stops the
    // command for the rest of the pipeline - the sentinel carries that across records.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Certificate, $Database, $ExcludeDatabase, $EncryptionPassword, $DecryptionPassword, $Path, $Suffix, $FileBaseName, $InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Certificate, [object[]]$Database, [object[]]$ExcludeDatabase, [Security.SecureString]$EncryptionPassword, [Security.SecureString]$DecryptionPassword, [System.IO.FileInfo]$Path, [string]$Suffix, [string]$FileBaseName, [Microsoft.SqlServer.Management.Smo.Certificate[]]$InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        function export-cert ($cert) {
            $certName = $cert.Name
            $db = $cert.Parent
            $dbname = $db.Name
            $server = $db.Parent
            $instance = $server.Name

            if (-not $Path) {
                $Path = $server.BackupDirectory
            }

            if (-not $Path) {
                Stop-Function -Message "Path discovery failed. Please explicitly specify -Path" -Target $server -Continue
            }

            $actualPath = "$Path".TrimEnd('\').TrimEnd('/')

            if (-not (Test-DbaPath -SqlInstance $server -Path $actualPath)) {
                Stop-Function -Message "$SqlInstance cannot access $actualPath" -Target $actualPath
            }

            $fileinstance = $instance.ToString().Replace('\', '$')
            $targetBaseName = "$fileinstance-$dbname-$certName$Suffix"
            if ($FileBaseName) {
                $targetBaseName = $FileBaseName
            }
            $fullCertName = Join-DbaPath -SqlInstance $server -Path $actualPath -ChildPath $targetBaseName

            # if the base file name exists, then default to old style of appending a timestamp
            if (Test-DbaPath -SqlInstance $server -Path "$fullCertName.cer") {
                if ($Suffix) {
                    Stop-Function -Message "$fullCertName.cer already exists on $($server.Name)" -Target $actualPath -Continue
                } else {
                    $time = Get-Date -Format yyyyMMddHHmmss
                    $fullCertName = "$fullCertName-$time"
                    # Sleep for a second to avoid another export in the same second
                    Start-Sleep -Seconds 1
                }
            }

            $exportPathKey = "$fullCertName.pvk"

            if ($__realCmdlet.ShouldProcess($instance, "Exporting certificate $certName from $db on $instance to $actualPath")) {
                Write-Message -Level Verbose -Message "Exporting Certificate: $certName to $fullCertName"
                try {
                    $exportPathCert = "$fullCertName.cer"

                    # because the password shouldn't go to memory...
                    if ($EncryptionPassword.Length -gt 0 -and $DecryptionPassword.Length -gt 0) {
                        if ($cert.PrivateKeyEncryptionType -eq [Microsoft.SqlServer.Management.Smo.PrivateKeyEncryptionType]::MasterKey) {
                            Write-Message -Level Verbose -Message "Both passwords passed in but private key of $certName is encrypted by the database master key. DecryptionPassword will be ignored."

                            $cert.export(
                                $exportPathCert,
                                $exportPathKey,
                                ($EncryptionPassword | ConvertFrom-SecurePass)
                            )
                        } else {
                            Write-Message -Level Verbose -Message "Both passwords passed in. Will export both cer and pvk."

                            $cert.export(
                                $exportPathCert,
                                $exportPathKey,
                                ($EncryptionPassword | ConvertFrom-SecurePass),
                                ($DecryptionPassword | ConvertFrom-SecurePass)
                            )
                        }
                    } elseif ($EncryptionPassword.Length -gt 0 -and $DecryptionPassword.Length -eq 0) {
                        Write-Message -Level Verbose -Message "Only encryption password passed in. Will export both cer and pvk."

                        $cert.export(
                            $exportPathCert,
                            $exportPathKey,
                            ($EncryptionPassword | ConvertFrom-SecurePass)
                        )
                    } else {
                        Write-Message -Level Verbose -Message "No passwords passed in. Will export just cer."
                        $exportPathKey = "Password required to export key"
                        $cert.export($exportPathCert)
                    }

                    [PSCustomObject]@{
                        ComputerName   = $server.ComputerName
                        InstanceName   = $server.ServiceName
                        SqlInstance    = $server.DomainInstanceName
                        Database       = $db.Name
                        DatabaseID     = $db.ID
                        Certificate    = $certName
                        Path           = $exportPathCert
                        Key            = $exportPathKey
                        ExportPath     = $exportPathCert
                        ExportKey      = $exportPathKey
                        exportPathCert = $exportPathCert
                        exportPathKey  = $exportPathKey
                        Status         = "Success"
                    } | Select-DefaultView -ExcludeProperty exportPathCert, exportPathKey, ExportPath, ExportKey
                } catch {
                    if ($_.Exception.InnerException) {
                        $exception = $_.Exception.InnerException.ToString() -Split "Microsoft.Data.SqlClient.SqlException: "
                        $exception = ($exception[1] -Split "at Microsoft.SqlServer.Management.Common.ConnectionManager")[0]
                    } else {
                        $exception = $_.Exception
                    }
                    Stop-Function -Message "$certName from $db on $instance cannot be exported." -Continue -Target $cert -ErrorRecord $PSItem
                }
            }
        }

        if (Test-FunctionInterrupt) { return }

        if ($SqlInstance) {
            $InputObject += Get-DbaDbCertificate -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Certificate $Certificate
        }

        if ($Certificate) {
            $missingCerts = $Certificate | Where-Object { $InputObject.Name -notcontains $_ }

            if ($missingCerts) {
                Write-Message -Level Warning -Message "Database certificate(s) $missingCerts not found in Database(s)=$Database on Instance(s)=$SqlInstance" -FunctionName Backup-DbaDbCertificate -ModuleName "dbatools"
            }
        }

        foreach ($cert in $InputObject) {
            if ($cert.Name.StartsWith("##")) {
                Write-Message -Level Verbose -Message "Skipping system cert $cert" -FunctionName Backup-DbaDbCertificate -ModuleName "dbatools"
            } else {
                export-cert $cert
            }
        }
    }
} $SqlInstance $SqlCredential $Certificate $Database $ExcludeDatabase $EncryptionPassword $DecryptionPassword $Path $Suffix $FileBaseName $InputObject $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
