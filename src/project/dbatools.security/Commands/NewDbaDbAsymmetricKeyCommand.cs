#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates asymmetric keys in one or more databases.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the key creation, the
/// key-source validation, the owner assignment, the added note properties, the default view, and dbatools
/// stream and error handling stay observable-identical to the script implementation.
/// </para>
/// <para>
/// TWO pieces of state span the pipeline in the script's function scope and are carried here:
/// </para>
/// <para>
/// The begin block's KeySource/KeySourceType xor check calls Stop-Function with NO -Continue and returns,
/// latching the dbatools interrupt; the process block reads it through Test-FunctionInterrupt, so every
/// record after the first returns immediately. That runs once in BeginProcessing and its result latches
/// into a field which short-circuits ProcessRecord.
/// </para>
/// <para>
/// $Name is MUTATED by the body: when it is unset the body assigns the current database's name to it, and
/// because $Name is not pipeline-bound that assignment PERSISTS into later records - so a second piped
/// database does NOT re-derive its own name, it reuses the first one. A per-record hop would reset $Name to
/// the bound value each record and silently diverge, so it rides a state sentinel: the field is seeded with
/// the bound value, threaded into each record's hop, and refreshed from the sentinel the hop emits last.
/// This keeps the script's per-record emission timing, which a collect-then-EndProcessing shape would lose.
/// </para>
/// <para>
/// The command streams through InvokeScopedStreaming: it emits per key and a later key can raise a
/// terminating -EnableException failure, so a buffered call would discard the keys already created and
/// reported (DEF-001). The SecureString rides live and is flattened only by the source's own
/// ConvertFrom-SecurePass inside the ShouldProcess gate. The undefined $Credential referenced by the last
/// Add-Member is a source bug preserved verbatim - it resolves to nothing in both worlds.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaDbAsymmetricKey", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaDbAsymmetricKeyCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The asymmetric key names to create.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Name { get; set; }

    /// <summary>The databases to create the keys in.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Database { get; set; } = new[] { "master" };

    /// <summary>Password protecting the private key.</summary>
    [Parameter(Position = 4)]
    [Alias("Password")]
    public System.Security.SecureString? SecurePassword { get; set; }

    /// <summary>The database user that owns the key.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    public string? Owner { get; set; }

    /// <summary>The executable, file, or assembly the key is created from.</summary>
    [Parameter(Position = 6)]
    [PsStringCast]
    public string? KeySource { get; set; }

    /// <summary>The kind of key source supplied.</summary>
    [Parameter(Position = 7)]
    [PsStringCast]
    [ValidateSet("Executable", "File", "SqlAssembly")]
    public string? KeySourceType { get; set; }

    /// <summary>Database objects from Get-DbaDatabase for pipeline operations.</summary>
    [Parameter(ValueFromPipeline = true, Position = 8)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    /// <summary>The encryption algorithm for the key.</summary>
    [Parameter(Position = 9)]
    [PsStringCast]
    [ValidateSet("Rsa4096", "Rsa3072", "Rsa2048", "Rsa1024", "Rsa512")]
    public string? Algorithm { get; set; } = "Rsa2048";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Set when the begin block latched the dbatools interrupt.</summary>
    private bool _beginInterrupted;

    /// <summary>$Name as the script would hold it, carried across records because the body mutates it.</summary>
    private object? _nameState;

    /// <summary>Runs the begin block's parameter check once and latches its interrupt.</summary>
    protected override void BeginProcessing()
    {
        _nameState = Name;

        bool interrupted = false;
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            TestBound(nameof(KeySource)), TestBound(nameof(KeySourceType)), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__NewDbaDbAsymmetricKeyBeginComplete"]?.Value))
            {
                interrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }

        _beginInterrupted = interrupted;
    }

    /// <summary>Creates the keys for the databases bound to the current record.</summary>
    protected override void ProcessRecord()
    {
        if (_beginInterrupted || Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            // The sentinel is always a [pscustomobject]; a real payload never is. Without the
            // BaseObject check an Update-TypeData-grafted property on an emitted AsymmetricKey
            // would be swallowed as bookkeeping (sibling NewDbaDbCertificate convention).
            else if (item is not null && item.BaseObject is PSCustomObject && LanguagePrimitives.IsTrue(
                item.Properties["__NewDbaDbAsymmetricKeyProcessComplete"]?.Value))
            {
                _nameState = UnwrapHopValue(item.Properties["Name"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, _nameState, Database, SecurePassword, Owner, KeySource, KeySourceType,
            InputObject, Algorithm, EnableException.ToBool(), this,
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

    // PS: the begin block VERBATIM, with its two Test-Bound reads mapped to the carried by-name flags.
    // It reports the interrupt latch it may have set, so ProcessRecord can skip exactly as the script's
    // function-scoped latch makes it.
    private const string BeginScript = """
param($__keySourceBound, $__keySourceTypeBound, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__keySourceBound, $__keySourceTypeBound, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if ((($__keySourceBound) -xor ($__keySourceTypeBound))) {
            Write-Message -Level Verbose -Message 'keysource paramter check' -FunctionName New-DbaDbAsymmetricKey -ModuleName "dbatools"
            Stop-Function -Message 'Both Keysource and KeySourceType must be provided' -FunctionName New-DbaDbAsymmetricKey
            return
        }
    }

    [pscustomobject]@{ __NewDbaDbAsymmetricKeyBeginComplete = $true; Interrupted = (Test-FunctionInterrupt) }
} $__keySourceBound $__keySourceTypeBound $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";

    // PS: the process body VERBATIM inside a dot-sourced block so its early return stays local and the
    // trailing sentinel still runs. Substitutions only: $Pscmdlet -> $__realCmdlet (the ShouldProcess
    // gate); -FunctionName on the DIRECT Stop-Function calls; -FunctionName + -ModuleName "dbatools" on
    // the DIRECT Write-Message calls. The sentinel returns $Name so its in-body mutation survives into
    // the next record, as it does in the script's function scope.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Name, $Database, $SecurePassword, $Owner, $KeySource, $KeySourceType, $InputObject, $Algorithm, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Name, [string[]]$Database, [System.Security.SecureString]$SecurePassword, [string]$Owner, [string]$KeySource, [string]$KeySourceType, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, [string]$Algorithm, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if (Test-FunctionInterrupt) { return }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            if (!($null -ne $name)) {
                Write-Message -Level Verbose -Message "Name of asymmetric key not specified, setting it to '$db'" -FunctionName New-DbaDbAsymmetricKey -ModuleName "dbatools"
                $Name = $db.Name
            }

            foreach ($askey in $Name) {
                if ($null -ne $db.AsymmetricKeys[$askey]) {
                    Stop-Function -Message "Asymmetric Key '$askey' already exists in $($db.Name) on $($db.Parent.Name)" -Target $db -Continue -FunctionName New-DbaDbAsymmetricKey
                }

                if ($__realCmdlet.ShouldProcess($db.Parent.Name, "Creating asymmetric key for database '$($db.Name)'")) {

                    # something is up with .net, force a stop
                    $eap = $ErrorActionPreference
                    $ErrorActionPreference = 'Stop'
                    try {
                        $smokey = New-Object -TypeName Microsoft.SqlServer.Management.Smo.AsymmetricKey $db, $askey
                        if ($owner -ne '') {
                            if ((Get-DbaDbUser -SqlInstance $db.Parent -Database $db.name | Where-Object name -eq $owner).count -eq 1) {
                                Write-Message -Level Verbose -Message "Setting key owner to $owner" -FunctionName New-DbaDbAsymmetricKey -ModuleName "dbatools"
                                $smokey.owner = $owner
                            } else {
                                Stop-Function -Message "$owner is unkown or ambiguous in $($db.name)" -Target $db -Continue -FunctionName New-DbaDbAsymmetricKey
                            }
                        }
                        if ('' -ne $Keysource) {
                            switch ($KeySourceType) {
                                'Executable' {
                                    Write-Message -Level Verbose -Message 'Executable passed in as key source' -FunctionName New-DbaDbAsymmetricKey -ModuleName "dbatools"
                                    if (!(Test-DbaPath -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Path $KeySource)) {
                                        Stop-Function -Message "Instance $SqlInstance cannot see $keysource to create key, skipping" -Target $db -Continue -FunctionName New-DbaDbAsymmetricKey
                                    }
                                }
                                'File' {
                                    Write-Message -Level Verbose -Message 'File passed in as key source' -FunctionName New-DbaDbAsymmetricKey -ModuleName "dbatools"
                                    if (!(Test-DbaPath -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Path $KeySource)) {
                                        Stop-Function -Message "Instance $SqlInstance cannot see $keysource to create key, skipping" -Target $db -Continue -FunctionName New-DbaDbAsymmetricKey
                                    }
                                }
                                'SqlAssembly' {
                                    Write-Message -Level Verbose -Message 'SqlAssembly passed in as key source' -FunctionName New-DbaDbAsymmetricKey -ModuleName "dbatools"
                                    if ($null -eq (Get-DbaDbAssembly -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $db -Name $KeySource)) {
                                        Stop-Function -Message "Instance $SqlInstance cannot see $keysource to create key, skipping" -Target $db -Continue -FunctionName New-DbaDbAsymmetricKey
                                    }
                                }
                            }
                            if ($SecurePassword) {
                                $smokey.Create($KeySource, [Microsoft.SqlServer.Management.Smo.AsymmetricKeySourceType]::$KeySourceType, ($SecurePassword | ConvertFrom-SecurePass))
                            } else {
                                $smokey.Create($Keysource, [Microsoft.SqlServer.Management.Smo.AsymmetricKeySourceType]::$KeySourceType)
                            }

                        } else {
                            Write-Message -Level Verbose -Message 'Creating normal key without source' -FunctionName New-DbaDbAsymmetricKey -ModuleName "dbatools"
                            if ($SecurePassword) {
                                $smokey.Create([Microsoft.SqlServer.Management.Smo.AsymmetricKeyEncryptionAlgorithm]::$Algorithm, ($SecurePassword | ConvertFrom-SecurePass))
                            } else {
                                $smokey.Create([Microsoft.SqlServer.Management.Smo.AsymmetricKeyEncryptionAlgorithm]::$Algorithm)
                            }
                        }

                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name ComputerName -value $db.Parent.ComputerName
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name InstanceName -value $db.Parent.ServiceName
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name SqlInstance -value $db.Parent.DomainInstanceName
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name Database -value $db.Name
                        Add-Member -Force -InputObject $smokey -MemberType NoteProperty -Name Credential -value $Credential
                        Select-DefaultView -InputObject $smokey -Property ComputerName, InstanceName, SqlInstance, Database, Name, Owner, KeyEncryptionAlgorithm, KeyLength, PrivateKeyEncryptionType, Thumbprint
                    } catch {
                        $ErrorActionPreference = $eap
                        Stop-Function -Message "Failed to create asymmetric key in $($db.Name) on $($db.Parent.Name)" -Target $smocert -ErrorRecord $_ -Continue -FunctionName New-DbaDbAsymmetricKey
                    }
                    $ErrorActionPreference = $eap
                }
            }
        }
    }

    [pscustomobject]@{ __NewDbaDbAsymmetricKeyProcessComplete = $true; Name = $Name }
} $SqlInstance $SqlCredential $Name $Database $SecurePassword $Owner $KeySource $KeySourceType $InputObject $Algorithm $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
