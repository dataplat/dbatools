#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Drops database users, re-owning or dropping the schemas they own first. Port of
/// public/Remove-DbaDbUser.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// The source is begin/process/end and defines a NESTED HELPER, Remove-DbUser, in begin, which both
/// process and end call. The helper is a pure definition capturing no state, so it is emitted into
/// BOTH hop bodies rather than carried - defining it per hop is identical to defining it once.
///
/// The helper's four ShouldProcess gates are deliberately NOT routed to this cmdlet. They belong to
/// Remove-DbUser's own $PSCmdlet in the source, and routing them would change attribution AND make
/// -Confirm's "Yes to All" persist across helper calls, where the script function gives every call a
/// fresh $PSCmdlet. Every other row in this satellite routes its gates; this one must not, and the
/// difference is that here the gates were never the command's to begin with. Verified rather than
/// assumed: -WhatIf forwarded to the hop scriptblock still reaches the helper's gate and suppresses
/// the action, so a -WhatIf run cannot silently drop users.
///
/// $pipedUsers accumulates ACROSS RECORDS - process appends piped users to it and end does the whole
/// deletion in one pass. That deferral is deliberate and the source says why: dropping while
/// enumerating a collection piped straight from Get-DbaDbUser raises "Collection was modified;
/// enumeration operation may not execute." So the collection rides a sentinel between records and is
/// emitted PLAIN, never comma-wrapped - a wrapped carry collapses to a single element and silently
/// loses every record but the last.
///
/// The begin body runs at the top of each hop and then the carried collection overwrites its
/// "$pipedUsers = @( )" initialiser, which reproduces begin-runs-once without special-casing it.
///
/// $Force does two separate jobs and both are preserved: it sets $ConfirmPreference = 'none' in
/// begin (folded into the hop - a preference set there does reach a gate, measured separately), and
/// it is read semantically inside the helper, where ($ownedUrns -And $Force) decides whether a schema
/// that owns objects gets re-owned to [dbo] rather than blocking the drop. So it crosses as a real
/// value the helper reads, not merely as a preference.
///
/// -FunctionName is added ONLY to the process and end bodies. Inside the helper it is deliberately
/// absent: Remove-DbUser is a named function in the hop too, so Stop-Function and Write-Message
/// called from within it resolve "Remove-DbUser" from the call stack exactly as they do in the
/// function world. Forcing the outer command name there would rename those messages.
///
/// -SqlInstance is at POSITION 1, not 0 - unusual, and pinned exactly as the source declares it.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbUser", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium, DefaultParameterSetName = "User")]
[OutputType(typeof(PSObject))]
public sealed class RemoveDbaDbUserCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ParameterSetName = "User", Mandatory = true, Position = 1, ValueFromPipeline = true)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(ParameterSetName = "User")]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Only these databases.</summary>
    [Parameter(ParameterSetName = "User")]
    public object[]? Database { get; set; }

    /// <summary>Skip these databases.</summary>
    [Parameter(ParameterSetName = "User")]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>The user or users to drop.</summary>
    [Parameter(ParameterSetName = "User", Mandatory = true)]
    public object[]? User { get; set; }

    /// <summary>SMO user object(s), typically from Get-DbaDbUser.</summary>
    [Parameter(ParameterSetName = "Object", Mandatory = true, ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.User[]? InputObject { get; set; }

    /// <summary>Re-own schemas that own objects to [dbo] instead of refusing to drop the user.</summary>
    [Parameter(ParameterSetName = "User")]
    [Parameter(ParameterSetName = "Object")]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The piped users accumulated across records. The source's "$pipedUsers = @( )" in begin is this
    // empty starting state; it is deliberately not re-initialised per record, because end consumes
    // the whole collection once.
    private object? _pipedUsers;

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__removeDbaDbUserState"]?.Value))
            {
                _pipedUsers = item.Properties["PipedUsers"]?.Value;
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
            SqlInstance, SqlCredential, Database, ExcludeDatabase, User, InputObject, Force,
            EnableException.ToBool(), _pipedUsers,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
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
        }, EndScript,
            Force, EnableException.ToBool(), _pipedUsers,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source's BEGIN body (including the Remove-DbUser helper) VERBATIM, then its PROCESS
    // body. The only edit is -FunctionName on the process body's own Stop-Function/Write-Message;
    // nothing inside the helper is touched.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $User, $InputObject, $Force, $EnableException, $__carriedPipedUsers, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, [object[]]$User, [Microsoft.SqlServer.Management.Smo.User[]]$InputObject, $Force, $EnableException, $__carriedPipedUsers, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    try {

            if ($Force) { $ConfirmPreference = 'none' }

            $pipedUsers = @( )

            function Remove-DbUser {
                [CmdletBinding(SupportsShouldProcess)]
                param ([Microsoft.SqlServer.Management.Smo.User[]]$users)

                foreach ($user in $users) {
                    $db = $user.Parent
                    $server = $db.Parent
                    $ownedObjects = $false
                    $alterSchemas = @()
                    $dropSchemas = @()
                    Write-Message -Level Verbose -Message "Removing User $user from Database $db on target $server"

                    if ($Pscmdlet.ShouldProcess($user, "Removing user from Database $db on target $server")) {
                        # Drop Schemas owned by the user before dropping the user
                        # Azure SQL Database doesn't support EnumOwnedObjects(), so we need to use T-SQL query instead
                        if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                            $splatQuery = @{
                                SqlInstance     = $server
                                Database        = $db.Name
                                Query           = "SELECT s.name FROM sys.schemas s WHERE s.principal_id = USER_ID('$($user.Name)')"
                                EnableException = $true
                            }
                            $ownedSchemaNames = Invoke-DbaQuery @splatQuery | Select-Object -ExpandProperty name
                            $schemaUrns = @()
                            foreach ($schemaName in $ownedSchemaNames) {
                                $schema = $db.Schemas[$schemaName]
                                if ($schema) {
                                    $schemaUrns += $schema.Urn
                                }
                            }
                        } else {
                            $schemaUrns = $user.EnumOwnedObjects() | Where-Object Type -EQ Schema
                        }

                        if ($schemaUrns) {
                            Write-Message -Level Verbose -Message "User $user owns $($schemaUrns.Count) schema(s)."

                            # Need to gather up the schema changes so they can be done in a non-destructive order
                            foreach ($schemaUrn in $schemaUrns) {
                                $schema = $server.GetSmoObject($schemaUrn)

                                # Drop any schema that is the same name as the user
                                if ($schema.Name -EQ $user.Name) {
                                    # Check for owned objects early so we can exit before any changes are made
                                    $ownedUrns = $schema.EnumOwnedObjects()
                                    if (-Not $ownedUrns) {
                                        $dropSchemas += $schema
                                    } else {
                                        Write-Message -Level Warning -Message "User owns objects in the database and will not be removed."
                                        foreach ($ownedUrn in $ownedUrns) {
                                            $obj = $server.GetSmoObject($ownedUrn)
                                            Write-Message -Level Warning -Message "User $user owns $($obj.GetType().Name) $obj"
                                        }
                                        $ownedObjects = $true
                                    }
                                }

                                # Change the owner of any schema not the same name as the user
                                if ($schema.Name -NE $user.Name) {
                                    # Check for owned objects early so we can exit before any changes are made
                                    $ownedUrns = $schema.EnumOwnedObjects()
                                    if (($ownedUrns -And $Force) -Or (-Not $ownedUrns)) {
                                        $alterSchemas += $schema
                                    } else {
                                        Write-Message -Level Warning -Message "User $user owns the Schema $schema, which owns $($ownedUrns.Count) object(s).  If you want to change the schemas' owner to [dbo] and drop the user anyway, use -Force parameter.  User $user will not be removed."
                                        $ownedObjects = $true
                                    }
                                }
                            }
                        }

                        if (-Not $ownedObjects) {
                            try {
                                # Alter Schemas
                                foreach ($schema in $alterSchemas) {
                                    Write-Message -Level Verbose -Message "Owner of Schema $schema will be changed to [dbo]."
                                    if ($PSCmdlet.ShouldProcess($server, "Change the owner of Schema $schema to [dbo].")) {
                                        $schema.Owner = "dbo"
                                        $schema.Alter()
                                    }
                                }

                                # Drop Schemas
                                foreach ($schema in $dropSchemas) {
                                    if ($PSCmdlet.ShouldProcess($server, "Drop Schema $schema from Database $db.")) {
                                        $schema.Drop()
                                    }
                                }

                                # Finally, Drop user
                                if ($PSCmdlet.ShouldProcess($server, "Drop User $user from Database $db.")) {
                                    $user.Drop()
                                }

                                $status = "Dropped"

                            } catch {
                                Write-Error -Message "Could not drop $user from Database $db on target $server"
                                $status = "Not Dropped"
                            }

                            [PSCustomObject]@{
                                ComputerName = $server.ComputerName
                                InstanceName = $server.ServiceName
                                SqlInstance  = $server.DomainInstanceName
                                Database     = $db.name
                                User         = $user
                                Status       = $status
                            }
                        }
                    }
                }
            }

        # The begin block above has just re-run its "$pipedUsers = @( )" initialiser. Restore what
        # earlier records collected, so begin behaves as run-once without special-casing it.
        if ($null -ne $__carriedPipedUsers) { $pipedUsers = @( $__carriedPipedUsers ) }

            if ($InputObject) {
                $pipedUsers += $InputObject
            } else {
                foreach ($instance in $SqlInstance) {
                    try {
                        $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                    } catch {
                        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Remove-DbaDbUser
                    }

                    $databases = $server.Databases | Where-Object IsAccessible

                    if ($Database) {
                        $databases = $databases | Where-Object Name -In $Database
                    }
                    if ($ExcludeDatabase) {
                        $databases = $databases | Where-Object Name -NotIn $ExcludeDatabase
                    }

                    foreach ($db in $databases) {
                        Write-Message -Level Verbose -Message "Get users in Database $db on target $server" -FunctionName Remove-DbaDbUser -ModuleName "dbatools"
                        $users = Get-DbaDbUser -SqlInstance $server -Database $db.Name
                        $users = $users | Where-Object Name -In $User
                        Remove-DbUser $users
                    }
                }
            }

    } finally {
        # PLAIN, never ", @( $pipedUsers )" - a comma-wrapped carry collapses to one element on the
        # next hop and silently loses every record but the last.
        [pscustomobject]@{
            __removeDbaDbUserState = $true
            PipedUsers             = $pipedUsers
        }
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $User $InputObject $Force $EnableException $__carriedPipedUsers $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the source's BEGIN body (including the helper) VERBATIM again, then its END body. The end
    // block is where the deletion actually happens, on the whole accumulated collection at once.
    private const string EndScript = """
param($Force, $EnableException, $__carriedPipedUsers, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param($Force, $EnableException, $__carriedPipedUsers, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if ($Force) { $ConfirmPreference = 'none' }

        $pipedUsers = @( )

        function Remove-DbUser {
            [CmdletBinding(SupportsShouldProcess)]
            param ([Microsoft.SqlServer.Management.Smo.User[]]$users)

            foreach ($user in $users) {
                $db = $user.Parent
                $server = $db.Parent
                $ownedObjects = $false
                $alterSchemas = @()
                $dropSchemas = @()
                Write-Message -Level Verbose -Message "Removing User $user from Database $db on target $server"

                if ($Pscmdlet.ShouldProcess($user, "Removing user from Database $db on target $server")) {
                    # Drop Schemas owned by the user before dropping the user
                    # Azure SQL Database doesn't support EnumOwnedObjects(), so we need to use T-SQL query instead
                    if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                        $splatQuery = @{
                            SqlInstance     = $server
                            Database        = $db.Name
                            Query           = "SELECT s.name FROM sys.schemas s WHERE s.principal_id = USER_ID('$($user.Name)')"
                            EnableException = $true
                        }
                        $ownedSchemaNames = Invoke-DbaQuery @splatQuery | Select-Object -ExpandProperty name
                        $schemaUrns = @()
                        foreach ($schemaName in $ownedSchemaNames) {
                            $schema = $db.Schemas[$schemaName]
                            if ($schema) {
                                $schemaUrns += $schema.Urn
                            }
                        }
                    } else {
                        $schemaUrns = $user.EnumOwnedObjects() | Where-Object Type -EQ Schema
                    }

                    if ($schemaUrns) {
                        Write-Message -Level Verbose -Message "User $user owns $($schemaUrns.Count) schema(s)."

                        # Need to gather up the schema changes so they can be done in a non-destructive order
                        foreach ($schemaUrn in $schemaUrns) {
                            $schema = $server.GetSmoObject($schemaUrn)

                            # Drop any schema that is the same name as the user
                            if ($schema.Name -EQ $user.Name) {
                                # Check for owned objects early so we can exit before any changes are made
                                $ownedUrns = $schema.EnumOwnedObjects()
                                if (-Not $ownedUrns) {
                                    $dropSchemas += $schema
                                } else {
                                    Write-Message -Level Warning -Message "User owns objects in the database and will not be removed."
                                    foreach ($ownedUrn in $ownedUrns) {
                                        $obj = $server.GetSmoObject($ownedUrn)
                                        Write-Message -Level Warning -Message "User $user owns $($obj.GetType().Name) $obj"
                                    }
                                    $ownedObjects = $true
                                }
                            }

                            # Change the owner of any schema not the same name as the user
                            if ($schema.Name -NE $user.Name) {
                                # Check for owned objects early so we can exit before any changes are made
                                $ownedUrns = $schema.EnumOwnedObjects()
                                if (($ownedUrns -And $Force) -Or (-Not $ownedUrns)) {
                                    $alterSchemas += $schema
                                } else {
                                    Write-Message -Level Warning -Message "User $user owns the Schema $schema, which owns $($ownedUrns.Count) object(s).  If you want to change the schemas' owner to [dbo] and drop the user anyway, use -Force parameter.  User $user will not be removed."
                                    $ownedObjects = $true
                                }
                            }
                        }
                    }

                    if (-Not $ownedObjects) {
                        try {
                            # Alter Schemas
                            foreach ($schema in $alterSchemas) {
                                Write-Message -Level Verbose -Message "Owner of Schema $schema will be changed to [dbo]."
                                if ($PSCmdlet.ShouldProcess($server, "Change the owner of Schema $schema to [dbo].")) {
                                    $schema.Owner = "dbo"
                                    $schema.Alter()
                                }
                            }

                            # Drop Schemas
                            foreach ($schema in $dropSchemas) {
                                if ($PSCmdlet.ShouldProcess($server, "Drop Schema $schema from Database $db.")) {
                                    $schema.Drop()
                                }
                            }

                            # Finally, Drop user
                            if ($PSCmdlet.ShouldProcess($server, "Drop User $user from Database $db.")) {
                                $user.Drop()
                            }

                            $status = "Dropped"

                        } catch {
                            Write-Error -Message "Could not drop $user from Database $db on target $server"
                            $status = "Not Dropped"
                        }

                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $db.name
                            User         = $user
                            Status       = $status
                        }
                    }
                }
            }
        }

    $pipedUsers = @( )
    if ($null -ne $__carriedPipedUsers) { $pipedUsers = @( $__carriedPipedUsers ) }

        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbUser.
        Remove-DbUser $pipedUsers

} $Force $EnableException $__carriedPipedUsers $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
