#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates database encryption keys in one or more databases.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the encryptor discovery, the
/// certificate backup check, the SMO key creation, and dbatools stream and error handling stay
/// observable-identical to the script implementation.
/// </para>
/// <para>
/// $EncryptorName is MUTATED by the body but is NOT carried across records. The assignment is gated on
/// Test-Bound -Not, and Test-Bound reads $PSBoundParameters, which a plain assignment never touches, so the
/// gate stays open on every record and each record re-runs encryptor discovery against its own database's
/// parent. This is the same distinction drawn in W2-229: a mutated non-pipeline parameter needs a sentinel
/// only when the gate suppressing re-derivation reads the mutated VALUE, and a Test-Bound gate is immune.
/// </para>
/// <para>
/// $smoencryptionkey IS carried. The script assigns it inside the try and reads it in the catch as
/// -Target, so a later record whose New-Object throws before that assignment reports the PREVIOUS record's
/// key object. One process scope spans every record in the script, and a per-record hop would pass null
/// instead, changing the error record's TargetObject and the dbatools log target - the divergence codex
/// confirmed on W2-229's identically-shaped $smocert.
/// </para>
/// <para>
/// The command streams through InvokeScopedStreaming: it emits per database and a later database can raise
/// a terminating -EnableException failure, so a buffered call would discard the keys already created and
/// reported (DEF-001). The body reads $WhatIfPreference directly, which the hop's SupportsShouldProcess
/// scriptblock sets from the forwarded -WhatIf. SOURCE BUG PRESERVED: $db.Certficates is misspelled in the
/// source, so that refresh branch is unreachable dead code - carried verbatim per the do-not-fix law.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaDbEncryptionKey", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaDbEncryptionKeyCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The databases to create the encryption keys in.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; } = new[] { "master" };

    /// <summary>The name of the certificate or asymmetric key that encrypts the key.</summary>
    [Parameter(Position = 3)]
    [Alias("Certificate", "CertificateName")]
    [PsStringCast]
    public string? EncryptorName { get; set; }

    /// <summary>Whether the encryptor is a certificate or an asymmetric key.</summary>
    [Parameter(Position = 4)]
    [ValidateSet("Certificate", "AsymmetricKey")]
    [PsStringCast]
    public string? Type { get; set; } = "Certificate";

    /// <summary>The encryption algorithm for the key.</summary>
    [Parameter(Position = 5)]
    [ValidateSet("Aes128", "Aes192", "Aes256", "TripleDes")]
    [PsStringCast]
    public string? EncryptionAlgorithm { get; set; } = "Aes256";

    /// <summary>Database objects from Get-DbaDatabase for pipeline operations.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    /// <summary>Creates a missing certificate and skips the certificate backup check.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>$smoencryptionkey as the script holds it: assigned in one record, readable by the next.</summary>
    private object? _smoEncryptionKeyState;

    /// <summary>Creates the encryption keys for the databases bound to the current record.</summary>
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
            // The sentinel must be identified by SHAPE as well as by marker property. Matching on the
            // property alone lets any emitted object that happens to carry that name be swallowed as
            // bookkeeping - Update-TypeData can graft a property onto an SMO type, and a real payload
            // would then be silently consumed instead of returned. The hop's sentinel is always a
            // [pscustomobject]; a real payload never is.
            else if (item is not null && item.BaseObject is PSCustomObject && LanguagePrimitives.IsTrue(
                item.Properties["__NewDbaDbEncryptionKeyProcessComplete"]?.Value))
            {
                // W2-067 Assigned-flag: carry the value ONLY when the hop scope actually ASSIGNED it.
                // Get-Variable -Scope 0 cannot see an up-scope variable, so a never-assigned local stays
                // unset and the script's scope-walk to a module/global of the same name still happens.
                // Restoring a plain null instead would create a local and BLOCK that walk.
                _smoEncryptionKeyState = LanguagePrimitives.IsTrue(item.Properties["SmoEncryptionKeyAssigned"]?.Value)
                    ? UnwrapHopValue(item.Properties["SmoEncryptionKey"]?.Value)
                    : null;
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, EncryptorName, Type, EncryptionAlgorithm,
            InputObject, Force.ToBool(), EnableException.ToBool(), this, _smoEncryptionKeyState,
            TestBound(nameof(EncryptorName)),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    /// <summary>
    /// Unwraps a value the hop carried out through its sentinel.
    /// </summary>
    /// <remarks>
    /// A value the script left unset arrives as AutomationNull, which behaves as $null in PowerShell but
    /// unwraps to a truthy, property-less object - so it comes back as null instead. Otherwise the value is
    /// unwrapped ONLY when the wrapper adds nothing: note properties live on the PSObject wrapper rather
    /// than the BaseObject, so unwrapping such a value silently discards them.
    /// </remarks>
    private static object? UnwrapHopValue(object? value)
    {
        if (value is null || ReferenceEquals(value, System.Management.Automation.Internal.AutomationNull.Value))
            return null;
        if (value is not PSObject wrapper)
            return value;
        foreach (PSMemberInfo member in wrapper.Members)
        {
            if (member is PSNoteProperty)
                return wrapper;
        }
        return wrapper.BaseObject;
    }

    // PS: the process body VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet (the ShouldProcess
    // gate); the single Test-Bound -Not read -> the carried by-name flag; -FunctionName on the 6 DIRECT
    // Stop-Function calls; -FunctionName + -ModuleName "dbatools" on the 2 DIRECT Write-Message calls.
    // The hop seeds $smoencryptionkey from the previous record and emits it back out; $EncryptorName is
    // deliberately NOT carried (see the class remarks).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $EncryptorName, $Type, $EncryptionAlgorithm, $InputObject, $Force, $EnableException, $__realCmdlet, $__smoEncryptionKeyCarry, $__encryptorNameBound, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Database, [string]$EncryptorName, [string]$Type, [string]$EncryptionAlgorithm, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $Force, $EnableException, $__realCmdlet, $__smoEncryptionKeyCarry, $__encryptorNameBound, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # $smoencryptionkey as the previous record left it: in the script one process scope spans every
    # record, so a record whose New-Object throws before assigning it reports the PREVIOUS record's key.
    if ($null -ne $__smoEncryptionKeyCarry) { $smoencryptionkey = $__smoEncryptionKeyCarry }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            if ($db.HasDatabaseEncryptionKey) {
                Stop-Function -Message "$($db.Name) on $($db.Parent.Name) already has a database encryption key" -Continue -FunctionName New-DbaDbEncryptionKey
            }

            if ((-not $__encryptorNameBound)) {
                Write-Message -Level Verbose -Message "Name of encryptor not specified, looking for candidates on master" -FunctionName New-DbaDbEncryptionKey -ModuleName "dbatools"

                if ($Type -eq "Certificate") {
                    $null = $db.Parent.Databases["master"].Certificates.Refresh()
                    $dbcert = Get-DbaDbCertificate -SqlInstance $db.Parent -Database master | Where-Object Name -notmatch "##"
                    if ($dbcert.Name.Count -ne 1) {
                        if ($dbcert.Name.Count -lt 1) {
                            Stop-Function -Message "No usable certificates found in master on $($db.Parent.Name)" -Continue -FunctionName New-DbaDbEncryptionKey
                        } else {
                            Stop-Function -Message "More than one certificate found in master, please specify a name" -Continue -FunctionName New-DbaDbEncryptionKey
                        }
                    } else {
                        $EncryptorName = $dbcert.Name
                    }
                } else {
                    $EncryptorName = (Get-DbaDbAsymmetricKey -SqlInstance $db.Parent -Database master).Name
                    if (-not $EncryptorName) {
                        Stop-Function -Message "No usable Asymmetric Keys found in master on $($db.Parent.Name)" -Continue -FunctionName New-DbaDbEncryptionKey
                    }
                }
            }

            # asym is backed up with db, so only check certs for backups
            if ($Type -eq "Certificate") {
                Write-Message -Level Verbose "Getting certificate '$EncryptorName' from $($db.Parent) on $($db.Parent.Name)" -FunctionName New-DbaDbEncryptionKey -ModuleName "dbatools"
                $dbcert = Get-DbaDbCertificate -SqlInstance $db.Parent -Database master -Certificate $EncryptorName
                if (-not $dbcert -and $Force -and $EncryptorName) {
                    $dbcert = New-DbaDbCertificate -SqlInstance $db.Parent -Database master -Name $EncryptorName
                    $null = $db.Parent.Refresh()
                    $null = $db.Parent.Databases["master"].Refresh()
                }
                if ($dbcert.LastBackupDate.Year -eq 1 -and -not $Force -and -not $WhatIfPreference) {
                    Stop-Function -Message "Certificate ($EncryptorName) in master on $($db.Parent) has not been backed up. Please backup your certificate or use -Force to continue" -Continue -FunctionName New-DbaDbEncryptionKey
                }
            }

            if ($__realCmdlet.ShouldProcess($db.Parent.Name, "Creating encryption key for database '$($db.Name)'")) {

                # something is up with .net, force a stop
                $eap = $ErrorActionPreference
                $ErrorActionPreference = 'Stop'
                try {
                    # Shoutout to https://www.mssqltips.com/sqlservertip/6316/configure-sql-server-transparent-data-encryption-with-powershell/
                    $smoencryptionkey = New-Object -TypeName Microsoft.SqlServer.Management.Smo.DatabaseEncryptionKey
                    $smoencryptionkey.Parent = $db
                    $smoencryptionkey.EncryptionAlgorithm = $EncryptionAlgorithm
                    $smoencryptionkey.EncryptionType = "Server$Type"
                    $smoencryptionkey.EncryptorName = $EncryptorName
                    $null = $smoencryptionkey.Create()
                    $null = $db.Refresh()
                    if ($db.Certficates) {
                        $null = $db.Certficates.Refresh()
                    }
                    if ($db.AsymmetricKeys) {
                        $null = $db.AsymmetricKeys.Refresh()
                    }
                    $db | Get-DbaDbEncryptionKey
                } catch {
                    $ErrorActionPreference = $eap
                    Stop-Function -Message "Failed to create encryption key in $($db.Name) on $($db.Parent.Name)" -Target $smoencryptionkey -ErrorRecord $_ -Continue -FunctionName New-DbaDbEncryptionKey
                }
                $ErrorActionPreference = $eap
            }
        }
    $__smoencryptionkeyAssigned = [bool](Get-Variable -Name smoencryptionkey -Scope 0 -ErrorAction SilentlyContinue)

    [pscustomobject]@{ __NewDbaDbEncryptionKeyProcessComplete = $true; SmoEncryptionKey = $(if ($__smoencryptionkeyAssigned) { $smoencryptionkey } else { $null }); SmoEncryptionKeyAssigned = $__smoencryptionkeyAssigned }
} $SqlInstance $SqlCredential $Database $EncryptorName $Type $EncryptionAlgorithm $InputObject $Force $EnableException $__realCmdlet $__smoEncryptionKeyCarry $__encryptorNameBound $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
