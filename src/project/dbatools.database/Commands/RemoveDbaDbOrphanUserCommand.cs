#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes orphaned users, re-owning or dropping the schemas they own first. Port of
/// public/Remove-DbaDbOrphanUser.ps1; the workflow remains a module-scoped PowerShell compatibility
/// hop.
///
/// The hop runs once PER INSTANCE. The source foreaches $SqlInstance and keeps no cross-instance
/// state in that loop, so the split is safe; Unlike Set-DbaDbQueryStoreOption there is no pre-loop
/// guard here, so it needs no run-once machinery either - the process body IS the instance loop.
/// An earlier revision of this comment justified the split by claiming a single whole-array hop would
/// "emit all verbose ahead of all results". That was WRONG and is retracted: InvokeScopedStreaming
/// streams, so records surface in production order either way. The split is retained because it
/// bounds each instance's failure to its own invocation, not for any ordering reason.
///
/// The source's begin block does TWO things - "if ($Force) { $ConfirmPreference = 'none' }" and an
/// $eol constant - and both fold into the top of the hop, since -Force is not a pipeline parameter
/// and setting the preference per invocation is identical to setting it once. That fold is sound because a
/// $ConfirmPreference set inside the hop still reaches a gate routed to the outer cmdlet -
/// ShouldProcess resolves the preference from the scope chain at call time, measured separately with
/// a failing control.
///
/// All FIVE ShouldProcess gates are routed to the OUTER cmdlet ($Pscmdlet becomes $__realCmdlet),
/// which keeps -Confirm's "Yes to All" answer alive across pipeline records rather than letting a
/// per-record inner runtime forget it. (Counted mechanically, not by eye: an earlier revision of this
/// comment said three.)
///
/// No local needs a cross-record carry, and the accumulators are the part worth checking rather than
/// assuming: $AlterSchemaOwner and $DropSchema are built with += and read together to compose the
/// DROP USER batch, which is exactly the shape that forced guarded carries on other rows. Both are
/// reset to "" INSIDE the per-user loop that consumes them, immediately before the appends, so
/// nothing leaks between users or databases. $db, $DatabaseCollection, $dbuser, $ExistLogin and
/// $query are each assigned and read within one iteration, and $server is assigned at the top of the
/// instance loop whose failure path is Stop-Function -Continue, which skips every remaining statement
/// of that iteration including the reads.
///
/// No graceful-stop latch: the source has no Test-FunctionInterrupt guard, so a later record simply
/// re-enters the process body. Carrying a latch would suppress output the function repeats.
///
/// Note that BOTH -SqlInstance and -User are ValueFromPipeline. That does not change the hop
/// design - each binds per record as usual - but it means a caller can pipe either, and the
/// per-instance split is over whatever -SqlInstance holds for the current record.
///
/// $StackSource IS HOP-SAFE, and this is worth recording because it looks like it should not be. The
/// body calls Get-PSCallStack and branches on the CALLER's identity: a call from Repair-DbaDbOrphanUser
/// trusts the -User collection it was handed, anything else goes and discovers users itself. A hop
/// inserts extra scriptblock frames, so this is the same family as Test-Bound - a guard that inspects
/// the very thing the hop changes - and it was reported as a defect on review.
///
/// It is not one, and the reason is the indexing: $CallStack[$CallStack.Count - 2] counts from the
/// BOTTOM of the stack while the hop's frames are added at the TOP. Measured rather than argued -
/// the function shape resolves "Repair-DbaDbOrphanUser" through frames
/// <ScriptBlock> <- Remove-DbaDbOrphanUser <- Repair-DbaDbOrphanUser <- script, and the hop shape
/// resolves the SAME value through three additional inner <ScriptBlock> frames. Had the source used
/// (Get-PSCallStack)[1] - top-relative, as Get-DbaDbBackupHistory does - it WOULD have broken, and
/// that command is not yet ported. Anyone porting it should treat this as a live hazard.
///
/// The hop streams rather than buffers. This command MUTATES server state (schema re-ownership and DROP USER).
/// Note precisely what a streamed object does and does not mean here: the schema-action objects are
/// emitted BEFORE the final ExecuteNonQuery that applies the batch, so an emitted record reports
/// intent, not a completed repair - a later declined gate or a failed execution can leave an emitted
/// object whose mutation never landed. Streaming is still correct, because buffering would discard
/// the record of everything that DID complete when a later database throws under -EnableException;
/// but an earlier revision of this comment claimed emitted objects "record completed repairs", and
/// that overstated it.
///
/// The termination BOUNDARY is the thing to get right on this command, and it is now the shared
/// runtime's job rather than this file's. The source applies -WarningAction / -ErrorAction Stop
/// inside its own try blocks, so a Stop is converted in the body and caught there; a hop that let
/// the streaming callback re-emit the record instead would terminate OUTSIDE that catch, which on a
/// command that re-owns schemas and drops users changes which side effects have already landed.
/// NestedCommand.PropagateActionPreferences sets the preference variables for the invocation window,
/// which is what puts the conversion back in the body.
///
/// The integration leg discriminates the two. Its fixture is two databases with one orphan user
/// apiece, the first user owning a populated schema, and the surviving second user shows only that
/// the run stopped early - the streaming re-emit would halt before the second database under a
/// caller-side conversion too. What separates them is the terminating error's identity: converting
/// in the body raises from Write-Message, the cmdlet that emitted the warning, so the error carries
/// activity Write-Message and id ActionPreferenceStop,...WriteMessageCommand, where a caller-side
/// conversion would name whatever re-emitted the warning to the host. Measured in the function
/// world. It is still UNRUN against this cmdlet - the shipped satellite does not export it yet - so
/// the assertion first bites at flip. -ErrorAction Stop is not observable here at all: the body
/// raises no non-terminating error, so binding it is indistinguishable from a plain run.
///
/// ONE KNOWN SHARED-RUNTIME GAP REMAINS. Warnings raised by NESTED calls are lost: the function
/// emits a Connect-DbaInstance connection warning and its own Stop-Function warning, and this port
/// emits only the second, in both warning modes. The mechanism originally proposed - "compiled
/// nested cmdlets bypass the 3>&1 merge" - is NOT well supported and should not be repeated as fact.
/// PSCmdlet.WriteWarning produces an ordinary stream-3 WarningRecord, which the redirection and the
/// demultiplexer both handle, so "the child is compiled" cannot by itself be the cause; a real
/// bypass would need direct host/UI writes, a separate pipeline or runspace, or a different code
/// path in the child. The MEASUREMENT stands and the diagnosis does not.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbOrphanUser", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(PSObject))]
public sealed class RemoveDbaDbOrphanUserCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only repair these databases.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Skip these databases.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Only remove these users.</summary>
    [Parameter(Position = 4, ValueFromPipeline = true)]
    public object[]? User { get; set; }

    /// <summary>Force the removal, including dependent objects.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // One hop PER INSTANCE, not one for the whole array: the instance loop keeps no
        // cross-instance state and emits verbose per database, so a single hop would batch that
        // verbose ahead of all output. The body still foreaches $SqlInstance, so a single-element
        // array runs exactly one iteration.
        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
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
            }, BodyScript,
                new[] { instance }, SqlCredential, Database, ExcludeDatabase, User,
                Force, EnableException.ToBool(), this,
                NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        }
    }

    // PS: the source's begin line followed by its process body VERBATIM. Substitutions only:
    // $Pscmdlet -> $__realCmdlet, and -FunctionName on Stop-Function/Write-Message.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $User, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, [object[]]$User, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

            if ($Force) { $ConfirmPreference = 'none' }
            $eol = [System.Environment]::NewLine

            foreach ($Instance in $SqlInstance) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $Instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Remove-DbaDbOrphanUser
                }

                $DatabaseCollection = $server.Databases | Where-Object IsAccessible | Where-Object ReadOnly -eq $false

                if ($Database) {
                    $DatabaseCollection = $DatabaseCollection | Where-Object Name -In $Database
                }
                if ($ExcludeDatabase) {
                    $DatabaseCollection = $DatabaseCollection | Where-Object Name -NotIn $ExcludeDatabase
                }

                $CallStack = Get-PSCallStack | Select-Object -Property *
                if ($CallStack.Count -eq 1) {
                    $StackSource = $CallStack[0].Command
                } else {
                    #-2 because index base is 0 and we want the one before the last (the last is the actual command)
                    $StackSource = $CallStack[($CallStack.Count - 2)].Command
                }

                if ($DatabaseCollection) {
                    foreach ($db in $DatabaseCollection) {
                        try {
                            #if SQL 2012 or higher only validate databases with ContainmentType = NONE
                            if ($server.versionMajor -gt 10) {
                                if ($db.ContainmentType -ne [Microsoft.SqlServer.Management.Smo.ContainmentType]::None) {
                                    Write-Message -Level Warning -Message "Database '$db' is a contained database. Contained databases can't have orphaned users. Skipping validation." -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"
                                    Continue
                                }
                            }

                            if ($StackSource -eq "Repair-DbaDbOrphanUser") {
                                Write-Message -Level Verbose -Message "Call origin: Repair-DbaDbOrphanUser." -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"
                                #Will use collection from parameter ($User)
                                $users = $User
                            } else {
                                Write-Message -Level Verbose -Message "Validating users on database $db." -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"

                                $users = (Get-DbaDbOrphanUser -SqlInstance $server -Database $db.Name).SmoUser
                                if ($User.Count -gt 0) {
                                    $users = $users | Where-Object { $User -contains $_.Name }
                                }
                            }

                            if ($users.Count -gt 0) {
                                Write-Message -Level Verbose -Message "Orphan users found." -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"
                                foreach ($dbuser in $users) {
                                    $SkipUser = $false

                                    $ExistLogin = $null

                                    if ($StackSource -ne "Repair-DbaDbOrphanUser") {
                                        #Need to validate Existing Login because the call does not came from Repair-DbaDbOrphanUser
                                        $ExistLogin = $server.logins | Where-Object {
                                            $_.Isdisabled -eq $False -and
                                            $_.IsSystemObject -eq $False -and
                                            $_.IsLocked -eq $False -and
                                            $_.Name -eq $dbuser.Name
                                        }
                                    }

                                    #Schemas only appears on SQL Server 2005 (v9.0)
                                    if ($server.versionMajor -gt 8) {

                                        #reset variables
                                        $AlterSchemaOwner = ""
                                        $DropSchema = ""

                                        #Validate if user owns any schema
                                        $Schemas = @()
                                        $Schemas = $db.Schemas | Where-Object Owner -eq $dbuser.Name

                                        if (@($Schemas).Count -gt 0) {
                                            Write-Message -Level Verbose -Message "User $dbuser owns one or more schemas." -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"

                                            foreach ($sch in $Schemas) {
                                                <#
                                                    On sql server 2008 or lower the EnumObjects method does not accept empty parameter.
                                                    0x1FFFFFFF is the way we can say we want everything known by those versions

                                                    When it is a higher version we can use empty to get all
                                                #>
                                                if ($server.versionMajor -lt 11) {
                                                    $NumberObjects = ($db.EnumObjects(0x1FFFFFFF) | Where-Object { $_.Schema -eq $sch.Name } | Measure-Object).Count
                                                } else {
                                                    $NumberObjects = ($db.EnumObjects() | Where-Object { $_.Schema -eq $sch.Name } | Measure-Object).Count
                                                }

                                                if ($NumberObjects -gt 0) {
                                                    if ($Force) {
                                                        Write-Message -Level Verbose -Message "Parameter -Force was used! The schema '$($sch.Name)' have $NumberObjects underlying objects. We will change schema owner to 'dbo' and drop the user." -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"

                                                        if ($__realCmdlet.ShouldProcess($db.Name, "Changing schema '$($sch.Name)' owner to 'dbo'. -Force used.")) {
                                                            $AlterSchemaOwner += "ALTER AUTHORIZATION ON SCHEMA::[$($sch.Name)] TO [dbo]$eol"

                                                            [PSCustomObject]@{
                                                                ComputerName      = $server.ComputerName
                                                                InstanceName      = $server.ServiceName
                                                                SqlInstance       = $server.DomainInstanceName
                                                                DatabaseName      = $db.Name
                                                                SchemaName        = $sch.Name
                                                                Action            = "ALTER OWNER"
                                                                SchemaOwnerBefore = $sch.Owner
                                                                SchemaOwnerAfter  = "dbo"
                                                            }
                                                        }
                                                    } else {
                                                        Write-Message -Level Warning -Message "Schema '$($sch.Name)' owned by user $($dbuser.Name) have $NumberObjects underlying objects. If you want to change the schemas' owner to 'dbo' and drop the user anyway, use -Force parameter. Skipping user '$dbuser'." -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"
                                                        $SkipUser = $true
                                                        break
                                                    }
                                                } else {
                                                    if ($sch.Name -eq $dbuser.Name) {
                                                        Write-Message -Level Verbose -Message "The schema '$($sch.Name)' have the same name as user $dbuser. Schema will be dropped." -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"

                                                        if ($__realCmdlet.ShouldProcess($db.Name, "Dropping schema '$($sch.Name)'.")) {
                                                            $DropSchema += "DROP SCHEMA [$($sch.Name)]"

                                                            [PSCustomObject]@{
                                                                ComputerName      = $server.ComputerName
                                                                InstanceName      = $server.ServiceName
                                                                SqlInstance       = $server.DomainInstanceName
                                                                DatabaseName      = $db.Name
                                                                SchemaName        = $sch.Name
                                                                Action            = "DROP"
                                                                SchemaOwnerBefore = $sch.Owner
                                                                SchemaOwnerAfter  = "N/A"
                                                            }
                                                        }
                                                    } else {
                                                        Write-Message -Level Warning -Message "Schema '$($sch.Name)' does not have any underlying object. Ownership will be changed to 'dbo' so the user can be dropped. Remember to re-check permissions on this schema." -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"

                                                        if ($__realCmdlet.ShouldProcess($db.Name, "Changing schema '$($sch.Name)' owner to 'dbo'.")) {
                                                            $AlterSchemaOwner += "ALTER AUTHORIZATION ON SCHEMA::[$($sch.Name)] TO [dbo]$eol"

                                                            [PSCustomObject]@{
                                                                ComputerName      = $server.ComputerName
                                                                InstanceName      = $server.ServiceName
                                                                SqlInstance       = $server.DomainInstanceName
                                                                DatabaseName      = $db.Name
                                                                SchemaName        = $sch.Name
                                                                Action            = "ALTER OWNER"
                                                                SchemaOwnerBefore = $sch.Owner
                                                                SchemaOwnerAfter  = "dbo"
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                        } else {
                                            Write-Message -Level Verbose -Message "User $dbuser does not own any schema. Will be dropped." -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"
                                        }

                                        # https://github.com/dataplat/dbatools/issues/7130
                                        $dbUserName = $dbuser.ToString()
                                        if (-not ($dbUserName.StartsWith("[") -and $dbUserName.EndsWith("]"))) {
                                            $dbUserName = "[" + $dbUserName + "]"
                                        }

                                        $query = "$AlterSchemaOwner $eol$DropSchema $($eol)DROP USER " + $dbUserName

                                        Write-Message -Level Debug -Message $query -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"
                                    } else {
                                        $query = "EXEC master.dbo.sp_droplogin @loginame = N'$($dbuser.name)'"
                                    }

                                    if ($ExistLogin) {
                                        if (-not $SkipUser) {
                                            if ($Force) {
                                                if ($__realCmdlet.ShouldProcess($db.Name, "Dropping user $dbuser using -Force")) {
                                                    $server.Databases[$db.Name].ExecuteNonQuery($query) | Out-Null
                                                    Write-Message -Level Verbose -Message "User $dbuser was dropped from $($db.Name). -Force parameter was used." -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"
                                                }
                                            } else {
                                                Write-Message -Level Warning -Message "Orphan user $($dbuser.Name) has a matching login. The user will not be dropped. If you want to drop anyway, use -Force parameter." -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"
                                                Continue
                                            }
                                        }
                                    } else {
                                        if (-not $SkipUser) {
                                            if ($__realCmdlet.ShouldProcess($db.Name, "Dropping user $dbuser")) {
                                                $server.Databases[$db.Name].ExecuteNonQuery($query) | Out-Null
                                                Write-Message -Level Verbose -Message "User $dbuser was dropped from $($db.Name)." -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"
                                            }
                                        }
                                    }
                                }
                            } else {
                                Write-Message -Level Verbose -Message "No orphan users found on database $db." -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"
                            }
                            #reset collection
                            $users = $null
                        } catch {
                            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $db -Continue -FunctionName Remove-DbaDbOrphanUser
                        }
                    }
                } else {
                    Write-Message -Level Verbose -Message "There are no databases to analyse." -FunctionName Remove-DbaDbOrphanUser -ModuleName "dbatools"
                }
            }

} $SqlInstance $SqlCredential $Database $ExcludeDatabase $User $Force $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
