#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates database master keys in one or more databases.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the password prompt, the SMO
/// master key creation, the added note properties, the default view, and dbatools stream and error handling
/// stay observable-identical to the script implementation.
/// </para>
/// <para>
/// The begin block resolves $SecurePassword ONCE - from -Credential, or by prompting with Read-Host when
/// neither -Credential nor -SecurePassword was supplied - and every record then uses that one value. It runs
/// in BeginProcessing for exactly that reason: prompting per record would ask the operator once per piped
/// database instead of once per invocation. The resolved password rides a state sentinel out of the begin
/// hop and into each record's hop. Read-Host is carried verbatim and resolves inside dbatools module scope,
/// which is where the script's own prompt runs.
/// </para>
/// <para>
/// $masterkey IS carried across records. The script assigns it inside the try and reads it in the catch as
/// -Target, so a later record whose New-Object throws before that assignment reports the PREVIOUS record's
/// master key object. One process scope spans every record in the script; a per-record hop would pass null
/// and change the error record's TargetObject and the dbatools log target.
/// </para>
/// <para>
/// The command streams through InvokeScopedStreaming: it emits per database and a later database can raise a
/// terminating -EnableException failure, so a buffered call would discard the keys already created and
/// reported (DEF-001). TWO SOURCE BUGS PRESERVED verbatim per the do-not-fix law: the Get-DbaDatabase call
/// passes -ExcludeDatabase $ExcludeDatabase but there is NO -ExcludeDatabase parameter, so it always passes
/// nothing; and the catch's message interpolates $instance, which is likewise undefined and renders empty.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaDbMasterKey", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class NewDbaDbMasterKeyCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Credential whose password protects the master key.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    /// <summary>The databases to create the master keys in.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Database { get; set; } = new[] { "master" };

    /// <summary>The password that protects the master key.</summary>
    [Parameter(Position = 4)]
    [Alias("Password")]
    public System.Security.SecureString? SecurePassword { get; set; }

    /// <summary>Database objects from Get-DbaDatabase for pipeline operations.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>$SecurePassword as the begin block resolved it: prompted at most once per invocation.</summary>
    private object? _securePasswordState;

    /// <summary>$masterkey as the script holds it: assigned in one record, readable by the next.</summary>
    private object? _masterKeyState;

    /// <summary>Runs the begin block once, resolving the password before any record is processed.</summary>
    protected override void BeginProcessing()
    {
        _securePasswordState = SecurePassword;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && item.BaseObject is PSCustomObject && LanguagePrimitives.IsTrue(
                item.Properties["__NewDbaDbMasterKeyBeginComplete"]?.Value))
            {
                _securePasswordState = UnwrapHopValue(item.Properties["SecurePassword"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, BeginScript,
            Credential, SecurePassword, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    /// <summary>Creates the master keys for the databases bound to the current record.</summary>
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
            // Identified by SHAPE as well as by marker property: matching on the property alone would let
            // an Update-TypeData graft that name onto an SMO type and have a real payload silently
            // swallowed as bookkeeping. The sentinel is always a pscustomobject; a payload never is.
            else if (item is not null && item.BaseObject is PSCustomObject && LanguagePrimitives.IsTrue(
                item.Properties["__NewDbaDbMasterKeyProcessComplete"]?.Value))
            {
                // W2-067 Assigned-flag: carry the value ONLY when the hop scope actually ASSIGNED it.
                // Get-Variable -Scope 0 cannot see an up-scope variable, so a never-assigned local stays
                // unset and the script's scope-walk to a module/global of the same name still happens.
                // Restoring a plain null instead would create a local and BLOCK that walk.
                _masterKeyState = LanguagePrimitives.IsTrue(item.Properties["MasterKeyAssigned"]?.Value)
                    ? UnwrapHopValue(item.Properties["MasterKey"]?.Value)
                    : null;
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, _securePasswordState, InputObject,
            EnableException.ToBool(), this, _masterKeyState,
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

    // PS: the begin body VERBATIM, dot-sourced so its assignment lands in the hop's own scope, then
    // returned through the sentinel. Read-Host is carried unqualified exactly as the source writes it and
    // resolves inside dbatools module scope, which is where the script's prompt runs.
    private const string BeginScript = """
param($Credential, $SecurePassword, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([System.Management.Automation.PSCredential]$Credential, [System.Security.SecureString]$SecurePassword, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if ($Credential) {
            $SecurePassword = $Credential.Password
        } else {
            if (-not $SecurePassword) {
                $SecurePassword = Read-Host "Password" -AsSecureString
            }
        }
    }

    [pscustomobject]@{ __NewDbaDbMasterKeyBeginComplete = $true; SecurePassword = $SecurePassword }
} $Credential $SecurePassword $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";

    // PS: the process body VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet (the ShouldProcess
    // gate) and -FunctionName on the 2 DIRECT Stop-Function calls. There are no Write-Message or
    // Test-Bound calls in this body. The hop seeds $masterkey from the previous record and emits it back
    // out so the catch's -Target matches the script's cross-record scope.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $SecurePassword, $InputObject, $EnableException, $__realCmdlet, $__masterKeyCarry, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Database, [System.Security.SecureString]$SecurePassword, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__realCmdlet, $__masterKeyCarry, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # $masterkey as the previous record left it: in the script one process scope spans every record, so a
    # record whose New-Object throws before assigning it reports the PREVIOUS record's master key.
    if ($null -ne $__masterKeyCarry) { $masterkey = $__masterKeyCarry }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -Database $Database -ExcludeDatabase $ExcludeDatabase -SqlCredential $SqlCredential
        }

        foreach ($db in $InputObject) {
            if ($null -ne $db.MasterKey) {
                Stop-Function -Message "Master key already exists in the $($db.Name) database on $($db.Parent.Name)" -Target $db -Continue -FunctionName New-DbaDbMasterKey
            }

            if ($__realCmdlet.ShouldProcess($db.Parent.Name, "Creating master key for database '$($db.Name)'")) {
                try {
                    $masterkey = New-Object Microsoft.SqlServer.Management.Smo.MasterKey $db
                    $masterkey.Create(($SecurePassword | ConvertFrom-SecurePass))

                    Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name ComputerName -value $db.Parent.ComputerName
                    Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name InstanceName -value $db.Parent.ServiceName
                    Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name SqlInstance -value $db.Parent.DomainInstanceName
                    Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Database -value $db.Name

                    Select-DefaultView -InputObject $masterkey -Property ComputerName, InstanceName, SqlInstance, Database, CreateDate, DateLastModified, IsEncryptedByServer
                } catch {
                    Stop-Function -Message "Failed to create master key in $db on $instance" -Target $masterkey -ErrorRecord $_ -Continue -FunctionName New-DbaDbMasterKey
                }
            }
        }
    # Ignore, not SilentlyContinue. SilentlyContinue silences the STREAM and still appends the
    # record to $Error, so every record that never assigned $masterkey left a VariableNotFound in
    # the caller's $Error that the script implementation does not produce -- measured as six extra
    # entries in $Error and in -ErrorVariable across one run. Ignore writes nothing anywhere.
    $__masterkeyAssigned = [bool](Get-Variable -Name masterkey -Scope 0 -ErrorAction Ignore)

    [pscustomobject]@{ __NewDbaDbMasterKeyProcessComplete = $true; MasterKey = $(if ($__masterkeyAssigned) { $masterkey } else { $null }); MasterKeyAssigned = $__masterkeyAssigned }
} $SqlInstance $SqlCredential $Database $SecurePassword $InputObject $EnableException $__realCmdlet $__masterKeyCarry $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
