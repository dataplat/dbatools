#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes database roles, re-owning or dropping the schemas they own first. Port of
/// public/Remove-DbaDbRole.ps1 (W2-164); the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// A process-only port with THREE ShouldProcess gates, all routed to $__realCmdlet with their target
/// and action strings byte-for-byte: one for removing the role, one for re-owning a schema to [dbo],
/// and one for dropping a schema. There is no begin or end block and no cross-block state, so nothing
/// needs a sentinel carry; the pre-port DEF-012 detector is clean in both shapes, and here that is
/// meaningful rather than an artifact of the tool's scope, because there is no other block for a
/// carry to hide in.
///
/// NO continue-guard wrapper. Both early exits are plain `return`s - the "you must pipe in a role..."
/// guard at the top of process, and the `default` arm of the input-type switch. Neither is a
/// `continue`. Note the second one is nested inside `foreach ($input in $InputObject)` and still uses
/// `return`, which in the source exits the FUNCTION rather than the loop; a return inside the hop
/// scriptblock reproduces exactly that, ending the body for the record. The single
/// Stop-Function -Continue sits inside a genuine enclosing foreach (over $dbRoles).
///
/// $input SHADOWING, worth stating because it looks alarming and is not: the source's loop is
/// `foreach ($input in $InputObject)`, which rebinds PowerShell's automatic $input. Inside the hop the
/// scriptblock has its own automatic $input, but the foreach binds the name locally for the duration
/// of the loop exactly as it does in the function, and the body only ever reads the loop value. No
/// substitution is needed and none was made - the name is left verbatim.
///
/// ZERO Test-Bound calls. The top guard tests parameter VALUES
/// (`-not $InputObject -and -not $SqlInstance`), and -Force is read as a VALUE inside the
/// owned-objects decision (`($ownedUrns -and $Force)`), never as a bound flag. So no bound-flag
/// substitution is carried at all, and -Force crosses as a real boolean the body can evaluate rather
/// than as a preference hint.
///
/// TWO ValueFromPipeline parameters (SqlInstance and InputObject). E's investigation of that shape
/// concluded there is NO two-VFP binding class - the apparent divergence was traced to warning
/// suppression, not binding - so both are reproduced exactly as declared with no transformation
/// attribute, which is the conclusion E reached after removing one that demonstrably did nothing.
///
/// -SqlInstance is declared `[DbaInstance[]]` in the source, which LOOKS like a different type from
/// the DbaInstanceParameter[] used by most siblings. It is not: `DbaInstance` is a dbatools TYPE
/// ACCELERATOR for Dataplat.Dbatools.Parameter.DbaInstanceParameter (verified against the live
/// accelerator table), and the baseline accordingly pins the resolved
/// Dataplat.Dbatools.Parameter.DbaInstanceParameter[]. The C# therefore declares the resolved type -
/// the accelerator has no meaning outside PowerShell. This also explains why the body's type switch
/// dispatches on the 'Dataplat.Dbatools.Parameter.DbaInstanceParameter' full name and still matches
/// values bound through the accelerator. I initially wrote this comment claiming the distinction was
/// load-bearing; the compiler rejected the name and the accelerator table showed it was the same
/// type, so the claim is corrected rather than left standing.
///
/// Only other body edits are -FunctionName Remove-DbaDbRole on the direct Stop-Function and
/// Write-Message sites.
///
/// Surface pinned by migration/baselines/Remove-DbaDbRole.json
/// (sourceSha256 405ae33ef93237f6c8f8bd94823634775da8627fad9e7398255427cb4198506c): no named parameter
/// sets; SqlInstance 0 ValueFromPipeline, SqlCredential 1, Database 2, ExcludeDatabase 3, Role 4,
/// ExcludeRole 5, InputObject 6 ValueFromPipeline; IncludeSystemDbs / Force / EnableException
/// non-positional switches; outputType empty. Positions declared explicitly per the
/// positional-binding-loss class.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbRole", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaDbRoleCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>The role(s) to remove.</summary>
    [Parameter(Position = 4)]
    public string[]? Role { get; set; }

    /// <summary>The role(s) to exclude.</summary>
    [Parameter(Position = 5)]
    public string[]? ExcludeRole { get; set; }

    /// <summary>Also process system databases.</summary>
    [Parameter]
    public SwitchParameter IncludeSystemDbs { get; set; }

    /// <summary>Server, database or database-role object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public object[]? InputObject { get; set; }

    /// <summary>Re-own schemas that own objects to [dbo] and remove the role anyway.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
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
        }, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, Role, ExcludeRole,
            IncludeSystemDbs.ToBool(), InputObject, Force.ToBool(), EnableException.ToBool(),
            this, NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block verbatim. Edits: the three $PSCmdlet gates -> $__realCmdlet, and
    // -FunctionName Remove-DbaDbRole on the direct Stop-Function and Write-Message sites. The
    // foreach loop variable is left as $input, verbatim, per the class remarks.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Role, $ExcludeRole, $IncludeSystemDbs, $InputObject, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, [string[]]$Role, [string[]]$ExcludeRole, $IncludeSystemDbs, [object[]]$InputObject, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not $InputObject -and -not $SqlInstance) {
        Stop-Function -Message "You must pipe in a role, database, or server or specify a SqlInstance" -FunctionName Remove-DbaDbRole
        return
    }

    if ($SqlInstance) {
        $InputObject = $SqlInstance
    }

    foreach ($input in $InputObject) {
        $inputType = $input.GetType().FullName
        switch ($inputType) {
            'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject" -FunctionName Remove-DbaDbRole -ModuleName "dbatools"
                $dbRoles = Get-DbaDbRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$True
            }
            'Microsoft.SqlServer.Management.Smo.Server' {
                Write-Message -Level Verbose -Message "Processing Server through InputObject" -FunctionName Remove-DbaDbRole -ModuleName "dbatools"
                $dbRoles = Get-DbaDbRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$True
            }
            'Microsoft.SqlServer.Management.Smo.Database' {
                Write-Message -Level Verbose -Message "Processing Database through InputObject" -FunctionName Remove-DbaDbRole -ModuleName "dbatools"
                $dbRoles = $input | Get-DbaDbRole -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$True
            }
            'Microsoft.SqlServer.Management.Smo.DatabaseRole' {
                Write-Message -Level Verbose -Message "Processing DatabaseRole through InputObject" -FunctionName Remove-DbaDbRole -ModuleName "dbatools"
                $dbRoles = $input
            }
            default {
                Stop-Function -Message "InputObject is not a server, database, or database role." -FunctionName Remove-DbaDbRole
                return
            }
        }

        foreach ($dbRole in $dbRoles) {
            $db = $dbRole.Parent
            $instance = $db.Parent
            $ownedObjects = $false
            $alterSchemas = @()
            $dropSchemas = @()

            if ((!$db.IsSystemObject) -or ($db.IsSystemObject -and $IncludeSystemDbs )) {
                if ((!$dbRole.IsFixedRole) -and ($dbRole.Name -ne 'public')) {
                    if ($__realCmdlet.ShouldProcess($instance, "Remove role $dbRole from database $db")) {
                        # Handle schemas owned by the role
                        $ownedSchemas = $db.Schemas | Where-Object { $_.Owner -eq $dbRole.Name }

                        if ($ownedSchemas) {
                            Write-Message -Level Verbose -Message "Role $dbRole owns $($ownedSchemas.Count) schema(s)." -FunctionName Remove-DbaDbRole -ModuleName "dbatools"

                            # Need to gather up the schema changes so they can be done in a non-destructive order
                            foreach ($schema in $ownedSchemas) {
                                # Drop any schema that is the same name as the role
                                if ($schema.Name -eq $dbRole.Name) {
                                    # Check for owned objects early so we can exit before any changes are made
                                    $ownedUrns = $schema.EnumOwnedObjects()
                                    if (-not $ownedUrns) {
                                        $dropSchemas += $schema
                                    } else {
                                        Write-Message -Level Warning -Message "Role $dbRole owns the Schema $schema, which owns $($ownedUrns.Count) object(s). Role $dbRole will not be removed." -FunctionName Remove-DbaDbRole -ModuleName "dbatools"
                                        $ownedObjects = $true
                                    }
                                }

                                # Change the owner of any schema not the same name as the role
                                if ($schema.Name -ne $dbRole.Name) {
                                    # Check for owned objects early so we can exit before any changes are made
                                    $ownedUrns = $schema.EnumOwnedObjects()
                                    if (($ownedUrns -and $Force) -or (-not $ownedUrns)) {
                                        $alterSchemas += $schema
                                    } else {
                                        Write-Message -Level Warning -Message "Role $dbRole owns the Schema $schema, which owns $($ownedUrns.Count) object(s). If you want to change the schema's owner to [dbo] and drop the role anyway, use -Force parameter. Role $dbRole will not be removed." -FunctionName Remove-DbaDbRole -ModuleName "dbatools"
                                        $ownedObjects = $true
                                    }
                                }
                            }
                        }

                        if (-not $ownedObjects) {
                            try {
                                # Alter Schemas
                                foreach ($schema in $alterSchemas) {
                                    Write-Message -Level Verbose -Message "Owner of Schema $schema will be changed to [dbo]." -FunctionName Remove-DbaDbRole -ModuleName "dbatools"
                                    if ($__realCmdlet.ShouldProcess($instance, "Change the owner of Schema $schema to [dbo].")) {
                                        $schema.Owner = "dbo"
                                        $schema.Alter()
                                    }
                                }

                                # Drop Schemas
                                foreach ($schema in $dropSchemas) {
                                    if ($__realCmdlet.ShouldProcess($instance, "Drop Schema $schema from Database $db.")) {
                                        $schema.Drop()
                                    }
                                }

                                # Drop the role
                                $dbRole.Drop()
                                Write-Message -Level Verbose -Message "Role $dbRole removed from database $db on instance $instance" -FunctionName Remove-DbaDbRole -ModuleName "dbatools"
                            } catch {
                                Stop-Function -Message "Failed to remove role $dbRole from database $db on instance $instance" -ErrorRecord $_ -Continue -FunctionName Remove-DbaDbRole
                            }
                        }
                    }
                } else {
                    Write-Message -Level Verbose -Message "Cannot remove fixed role $dbRole from database $db on instance $instance" -FunctionName Remove-DbaDbRole -ModuleName "dbatools"
                }
            } else {
                Write-Message -Level Verbose -Message "Can only remove roles from System database when IncludeSystemDbs switch used." -FunctionName Remove-DbaDbRole -ModuleName "dbatools"
            }
        }
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Role $ExcludeRole $IncludeSystemDbs $InputObject $Force $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
