#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates certificates in one or more databases.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the certificate creation, the
/// password handling, the added note properties, the default view, and dbatools stream and error handling
/// stay observable-identical to the script implementation.
/// </para>
/// <para>
/// The body MUTATES $Name and $Subject, which normally forces a state sentinel so the assignments survive
/// into the next record. Here they must NOT survive: both assignments are gated on Test-Bound -Not, and
/// Test-Bound reads $PSBoundParameters, which a plain assignment never touches. The gate therefore stays
/// open on every record, and each record unconditionally re-derives both values from its own $db, discarding
/// whatever the previous record left behind. Measured directly - two piped databases, both parameters
/// unbound - the script gives the SECOND database its own name and subject rather than reusing the first's.
/// A per-record hop reproduces that exactly; a sentinel carrying the values forward would be inert machinery
/// resting on a false premise, so there is none.
/// </para>
/// <para>
/// The two [datetime] parameters carry [PsDateTimeCast] for invariant-culture bind parity, and their
/// computed defaults are resolved in BeginProcessing - during binding, before pipeline enumeration - exactly
/// as the script's parameter defaults are. ExpirationDate defaults to StartDate.AddYears(5), so the resolved
/// StartDate feeds it: resolving either per record would let a slow pipeline drift the dates apart.
/// </para>
/// <para>
/// The command streams through InvokeScopedStreaming: it emits per certificate and a later certificate can
/// raise a terminating -EnableException failure, so a buffered call would discard the certificates already
/// created and reported (DEF-001). The SecureString rides live and is flattened only by the source's own
/// ConvertFrom-SecurePass inside the ShouldProcess gate. The undefined $Credential referenced by the last
/// Add-Member is a source bug preserved verbatim - it resolves to nothing in both worlds.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaDbCertificate", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaDbCertificateCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The certificate names to create.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Name { get; set; }

    /// <summary>The databases to create the certificates in.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Database { get; set; } = new[] { "master" };

    /// <summary>The certificate subjects.</summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? Subject { get; set; }

    /// <summary>The date the certificate becomes valid. Defaults to now.</summary>
    [Parameter(Position = 5)]
    [PsDateTimeCast]
    public DateTime StartDate { get; set; }

    /// <summary>The date the certificate expires. Defaults to five years after StartDate.</summary>
    [Parameter(Position = 6)]
    [PsDateTimeCast]
    public DateTime ExpirationDate { get; set; }

    /// <summary>Marks the certificate active for service broker dialogs.</summary>
    [Parameter]
    public SwitchParameter ActiveForServiceBrokerDialog { get; set; }

    /// <summary>Password protecting the certificate's private key.</summary>
    [Parameter(Position = 7)]
    [Alias("Password")]
    public System.Security.SecureString? SecurePassword { get; set; }

    /// <summary>Database objects from Get-DbaDatabase for pipeline operations.</summary>
    [Parameter(ValueFromPipeline = true, Position = 8)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>The certificate dates resolved at bind time, exactly like the script's parameter defaults.</summary>
    private DateTime _resolvedStartDate;
    private DateTime _resolvedExpirationDate;

    /// <summary>$smocert as the script holds it: assigned in one record and readable by the next.</summary>
    private object? _smocertState;

    /// <summary>Whether the last record's hop scope actually ASSIGNED $smocert - distinguishes an
    /// assigned $null (seed it: the source scope holds null and blocks any scope-walk) from
    /// never-assigned (leave unset so the scope-walk the source would do still happens).</summary>
    private bool _smocertAssigned;

    /// <summary>Resolves the computed date defaults before any pipeline record is processed.</summary>
    protected override void BeginProcessing()
    {
        bool startBound = TestBound(nameof(StartDate));
        bool expirationBound = TestBound(nameof(ExpirationDate));

        // Both defaults are PowerShell EXPRESSIONS - (Get-Date) and $StartDate.AddYears(5) - evaluated by
        // the engine in the function's own module scope during binding. Computing them in C# instead
        // diverges twice over: DateTime.Now bypasses command resolution, so a module-scoped override or
        // Pester mock of Get-Date that the script honours would be invisible; and DateTime.AddYears
        // surfaces a raw ArgumentOutOfRangeException on overflow where the script's method binder surfaces
        // MethodInvocationException (measured with -StartDate ([datetime]::MaxValue)). So the whole default
        // chain is evaluated BY PowerShell, in dbatools module scope, in the script's own order - the
        // ExpirationDate expression reading whatever StartDate resolved to.
        //
        // This runs in BeginProcessing, which like binding happens before ANY record, so an overflow still
        // throws on an empty pipeline and a slow pipeline still cannot drift the two dates apart.
        // Only the BOUND dates go in: an unbound one must be absent so the resolver's own default
        // expression fires for it, exactly as an unsupplied parameter does in the script.
        Hashtable splatDates = new Hashtable();
        if (startBound)
            splatDates["StartDate"] = StartDate;
        if (expirationBound)
            splatDates["ExpirationDate"] = ExpirationDate;

        foreach (PSObject item in NestedCommand.InvokeScoped(this, DefaultDateScript, splatDates))
        {
            if (item?.BaseObject is not PSCustomObject)
                continue;

            // Convert rather than type-test: Get-Date emits a PSObject-WRAPPED DateTime (it carries a
            // DisplayHint note property), so an "is DateTime" test silently misses and leaves the date at
            // DateTime.MinValue - which SQL Server rejects with "An invalid date or time was specified".
            // The script's [datetime] binder already rejected anything unconvertible before this point, so
            // these conversions cannot fail; they only strip the PSObject wrapper.
            if (LanguagePrimitives.TryConvertTo(item.Properties["StartDate"]?.Value, out DateTime resolvedStart))
                _resolvedStartDate = resolvedStart;
            if (LanguagePrimitives.TryConvertTo(item.Properties["ExpirationDate"]?.Value, out DateTime resolvedExpiration))
                _resolvedExpirationDate = resolvedExpiration;
        }
    }

    // The dates are resolved by a FUNCTION whose param block MIRRORS the source's own: same [datetime]
    // types, same default expressions, same order. That hands the whole job to the PowerShell PARAMETER
    // BINDER, which is what the script uses - so the defaults resolve through normal command resolution
    // AND a value the binder cannot convert fails the way the script fails it.
    //
    // It must be a FUNCTION, not the scriptblock this hop otherwise uses. Measured: invoking a scriptblock
    // through & $module { param(...) } binds its defaults LENIENTLY - a Get-Date shadowed to return two
    // dates leaves $StartDate null and the next default then dies on InvokeMethodOnNull. The identical
    // param block on a function binds strictly and raises ParameterBindingArgumentTransformationException,
    // which is exactly what the script raises. Bound values are splatted in so unbound ones fall through
    // to their defaults, mirroring how the script's own binding behaves.
    private const string DefaultDateScript = """
param($__splatDates)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__splatDates)
    function __Resolve-DbaDbCertificateDate {
        param([datetime]$StartDate = (Get-Date), [datetime]$ExpirationDate = $StartDate.AddYears(5))
        [pscustomobject]@{ StartDate = $StartDate; ExpirationDate = $ExpirationDate }
    }
    __Resolve-DbaDbCertificateDate @__splatDates
} $__splatDates
""";

    /// <summary>Creates the certificates for the databases bound to the current record.</summary>
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
            // bookkeeping - Update-TypeData can graft a property onto every SMO Certificate, and the
            // created certificate would then be silently consumed instead of returned. The hop's sentinel
            // is always a [pscustomobject]; a real payload never is.
            else if (item is not null && item.BaseObject is PSCustomObject && LanguagePrimitives.IsTrue(
                item.Properties["__NewDbaDbCertificateProcessComplete"]?.Value))
            {
                // W2-067 Assigned-flag: carry the value ONLY when the hop scope actually ASSIGNED it.
                // Get-Variable -Scope 0 cannot see an up-scope variable, so a never-assigned local stays
                // unset and the script's scope-walk to a module/global of the same name still happens.
                // Restoring a plain null instead would create a local and BLOCK that walk.
                _smocertAssigned = LanguagePrimitives.IsTrue(item.Properties["SmocertAssigned"]?.Value);
                _smocertState = _smocertAssigned ? UnwrapHopValue(item.Properties["Smocert"]?.Value) : null;
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Name, Database, Subject, _resolvedStartDate,
            _resolvedExpirationDate, ActiveForServiceBrokerDialog.ToBool(), SecurePassword, InputObject,
            EnableException.ToBool(), this, _smocertState, _smocertAssigned,
            TestBound(nameof(Name)), TestBound(nameof(Subject)),
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
    // gate); the two Test-Bound -Not reads -> the carried by-name flags; -FunctionName on the 2 DIRECT
    // Stop-Function calls; -FunctionName + -ModuleName "dbatools" on the 4 DIRECT Write-Message calls.
    // $Name and $Subject are NOT carried - see the class remarks; the script re-derives both every record.
    // $smocert IS carried. The script assigns it inside the try, so if a LATER record's New-Object throws
    // before that assignment, the catch's -Target $smocert receives the PREVIOUS record's certificate. A
    // per-record hop starts with $smocert unset and would pass null, changing the error record's
    // TargetObject and the dbatools log target. Measured: a process-block assignment does survive into the
    // next record of the same invocation, so the hop seeds $smocert in and emits it back out.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Name, $Database, $Subject, $StartDate, $ExpirationDate, $ActiveForServiceBrokerDialog, $SecurePassword, $InputObject, $EnableException, $__realCmdlet, $__smocertCarry, $__smocertCarryAssigned, $__nameBound, $__subjectBound, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Name, [string[]]$Database, [string[]]$Subject, [datetime]$StartDate, [datetime]$ExpirationDate, $ActiveForServiceBrokerDialog, [System.Security.SecureString]$SecurePassword, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__realCmdlet, $__smocertCarry, $__smocertCarryAssigned, $__nameBound, $__subjectBound, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # $smocert as the previous record left it: in the script one process scope spans every record, so a
    # record whose New-Object throws before assigning it reports the PREVIOUS record's certificate.
    if ($null -ne $__smocertCarryAssigned -and [bool]$__smocertCarryAssigned) { $smocert = $__smocertCarry }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            if ((-not $__nameBound)) {
                $Name = $db.Name
                Write-Message -Level Verbose -Message "Name of certificate not specified, setting it to '$name'" -FunctionName New-DbaDbCertificate -ModuleName "dbatools"
            }

            if ((-not $__subjectBound)) {
                Write-Message -Level Verbose -Message "Subject not specified, setting it to '$Name Database Certificate'" -FunctionName New-DbaDbCertificate -ModuleName "dbatools"
                $subject = "$Name Database Certificate"
            }

            foreach ($cert in $Name) {
                $null = $db.Certificates.Refresh()
                if ($null -ne $db.Certificates[$cert]) {
                    Stop-Function -Message "Certificate '$cert' already exists in $($db.Name) on $($db.Parent.Name)" -Target $db -Continue -FunctionName New-DbaDbCertificate
                }

                if ($__realCmdlet.ShouldProcess($db.Parent.Name, "Creating certificate for database '$($db.Name)'")) {

                    # something is up with .net, force a stop
                    $eap = $ErrorActionPreference
                    $ErrorActionPreference = 'Stop'
                    try {
                        $smocert = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Certificate $db, $cert
                        $smocert.StartDate = $StartDate
                        $smocert.Subject = $Subject
                        $smocert.ExpirationDate = $ExpirationDate
                        $smocert.ActiveForServiceBrokerDialog = $ActiveForServiceBrokerDialog

                        if ($SecurePassword) {
                            Write-Message -Level Verbose -Message "Creating certificate with password" -FunctionName New-DbaDbCertificate -ModuleName "dbatools"
                            $smocert.Create(($SecurePassword | ConvertFrom-SecurePass))
                        } else {
                            Write-Message -Level Verbose -Message "Creating certificate without password, so it'll be protected by the master key" -FunctionName New-DbaDbCertificate -ModuleName "dbatools"
                            $smocert.Create()
                        }

                        Add-Member -Force -InputObject $smocert -MemberType NoteProperty -Name ComputerName -value $db.Parent.ComputerName
                        Add-Member -Force -InputObject $smocert -MemberType NoteProperty -Name InstanceName -value $db.Parent.ServiceName
                        Add-Member -Force -InputObject $smocert -MemberType NoteProperty -Name SqlInstance -value $db.Parent.DomainInstanceName
                        Add-Member -Force -InputObject $smocert -MemberType NoteProperty -Name Database -value $db.Name
                        Add-Member -Force -InputObject $smocert -MemberType NoteProperty -Name Credential -value $Credential
                        Select-DefaultView -InputObject $smocert -Property ComputerName, InstanceName, SqlInstance, Database, Name, Subject, StartDate, ActiveForServiceBrokerDialog, ExpirationDate, Issuer, LastBackupDate, Owner, PrivateKeyEncryptionType, Serial
                    } catch {
                        $ErrorActionPreference = $eap
                        Stop-Function -Message "Failed to create certificate in $($db.Name) on $($db.Parent.Name)" -Target $smocert -ErrorRecord $_ -Continue -FunctionName New-DbaDbCertificate
                    }
                    $ErrorActionPreference = $eap
                }
            }
        }
    $__smocertAssigned = [bool](Get-Variable -Name smocert -Scope 0 -ErrorAction SilentlyContinue)

    [pscustomobject]@{ __NewDbaDbCertificateProcessComplete = $true; Smocert = $(if ($__smocertAssigned) { $smocert } else { $null }); SmocertAssigned = $__smocertAssigned }
} $SqlInstance $SqlCredential $Name $Database $Subject $StartDate $ExpirationDate $ActiveForServiceBrokerDialog $SecurePassword $InputObject $EnableException $__realCmdlet $__smocertCarry $__smocertCarryAssigned $__nameBound $__subjectBound $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
