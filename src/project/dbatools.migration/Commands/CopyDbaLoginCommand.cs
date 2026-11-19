#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies SQL Server logins between instances with passwords, SIDs, roles and permissions intact.
/// Port of public/Copy-DbaLogin.ps1.
/// </summary>
/// <remarks>
/// The workflow stays a module-scoped PowerShell compatibility hop: the body leans on
/// Get-DbaLogin, New-DbaLogin, Export-DbaLogin, Get-DbaPermission, Invoke-DbaQuery, the private
/// Update-SqlPermission and Get-ErrorMessage helpers, SMO Login/Database/Job mutation and
/// Select-DefaultView - all of which keep engine semantics where they were. The compiled cmdlet
/// supplies the real ShouldProcess runtime.
///
/// The function's begin block folds into the per-record hop. Its only two products are the
/// Copy-Login helper definition and the $ConfirmPreference assignment, both derived from
/// parameters that cannot arrive by pipeline, so re-deriving them per record produces exactly
/// what the single begin run produced.
///
/// No cross-record value carriers, and the dominance proof for every process-block local:
/// $loginsCollection is reset to @() at the top of every record; $foundLogins is read only
/// inside the branch that assigns it; $sourceServer and $sourceVersionMajor are assigned as the
/// first two statements of the login loop that reads them; $destServer's only failure path is a
/// Stop-Function -Continue bound to the destination loop that guards every read;
/// $destVersionMajor, $sa, $destSa and $saName are all assigned immediately before their reads.
/// Copy-Login's own locals - including the $disabled re-enable flag - live in a fresh function
/// scope per call in both worlds.
///
/// Interrupted IS read, because the source reads it: process opens with
/// "if (Test-FunctionInterrupt) { return }", so a non--Continue Stop-Function on one piped record
/// must stop every record after it. The hop's own Test-FunctionInterrupt call cannot do that job
/// any more - each record runs in a fresh scope, and Stop-Function writes its flag with
/// Set-Variable -Scope 1 - so the latch rides back through the nested-command interrupt beacon
/// into the ProcessRecord guard instead. The line stays where the source has it.
///
/// -WhatIf and -Confirm are carried into the hop rather than only routed through $__realCmdlet:
/// Copy-Login declares its own SupportsShouldProcess, and New-DbaLogin, Update-SqlPermission,
/// Get-DbaPermission and Invoke-DbaQuery all inherit $WhatIfPreference from it. Splatting the
/// bound values into the hop's [CmdletBinding(SupportsShouldProcess)] block reproduces that
/// inheritance; without it those nested commands would mutate under -WhatIf. Surface pinned by
/// migration/baselines/Copy-DbaLogin.json.
/// </remarks>
[Cmdlet(VerbsCommon.Copy, "DbaLogin", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaLoginCommand : DbaBaseCmdlet
{
    /// <summary>Source SQL Server instance. Requires sysadmin access and SQL Server 2000 or higher.</summary>
    [Parameter(ParameterSetName = "File", Mandatory = true)]
    [Parameter(ParameterSetName = "SqlInstance", Mandatory = true)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>Destination SQL Server instances. Requires sysadmin access and SQL Server 2000 or higher.</summary>
    [Parameter(ParameterSetName = "SqlInstance", Mandatory = true)]
    [Parameter(ParameterSetName = "InputObject", Mandatory = true)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only copy these logins from the source instance. Accepts wildcards.</summary>
    [Parameter]
    public object[]? Login { get; set; }

    /// <summary>Skip these logins during the copy. Accepts wildcards.</summary>
    [Parameter]
    public object[]? ExcludeLogin { get; set; }

    /// <summary>Exclude NT SERVICE accounts and other system-generated logins.</summary>
    [Parameter]
    public SwitchParameter ExcludeSystemLogins { get; set; }

    /// <summary>Rename the destination sa account to match the source sa account name.</summary>
    [Parameter(ParameterSetName = "Live")]
    [Parameter(ParameterSetName = "SqlInstance")]
    public SwitchParameter SyncSaName { get; set; }

    /// <summary>Export login creation scripts to a T-SQL file instead of copying to a destination.</summary>
    [Parameter(ParameterSetName = "File", Mandatory = true)]
    public string? OutFile { get; set; }

    /// <summary>Login objects from Get-DbaLogin or another dbatools command.</summary>
    [Parameter(ParameterSetName = "InputObject", ValueFromPipeline = true)]
    public object[]? InputObject { get; set; }

    /// <summary>Renames logins during the copy; keys are the old names, values the new ones.</summary>
    [Parameter]
    public System.Collections.Hashtable? LoginRenameHashtable { get; set; }

    /// <summary>Terminate active sessions for logins being replaced under -Force.</summary>
    [Parameter]
    public SwitchParameter KillActiveConnection { get; set; }

    /// <summary>Generate new SIDs for the copied logins instead of preserving the originals.</summary>
    [Parameter]
    public SwitchParameter NewSid { get; set; }

    /// <summary>Drop and recreate logins that already exist on the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>Copy object-level permissions in addition to database and server roles.</summary>
    [Parameter]
    public SwitchParameter ObjectLevel { get; set; }

    /// <summary>Create the logins without copying server roles, database permissions or securables.</summary>
    [Parameter]
    public SwitchParameter ExcludePermissionSync { get; set; }

    /// <summary>Sync server-level permissions only, skipping database-level mappings.</summary>
    [Parameter]
    public SwitchParameter ExcludeDatabaseMapping { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

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
        }, BodyScript,
            Source, SourceSqlCredential, Destination, DestinationSqlCredential, Login,
            ExcludeLogin, ExcludeSystemLogins.ToBool(), SyncSaName.ToBool(), OutFile, InputObject,
            LoginRenameHashtable, KillActiveConnection.ToBool(), NewSid.ToBool(), Force.ToBool(),
            ObjectLevel.ToBool(), ExcludePermissionSync.ToBool(), ExcludeDatabaseMapping.ToBool(),
            EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"),
            NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"),
            NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string BodyScript = """
param($Source, $SourceSqlCredential, $Destination, $DestinationSqlCredential, $Login, $ExcludeLogin, $ExcludeSystemLogins, $SyncSaName, $OutFile, $InputObject, $LoginRenameHashtable, $KillActiveConnection, $NewSid, $Force, $ObjectLevel, $ExcludePermissionSync, $ExcludeDatabaseMapping, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    # The flag parameters are deliberately untyped. This block is called with positional
    # arguments and PowerShell excludes [switch] parameters from positional binding, so a single
    # [switch] in the list shifts every argument after it. They arrive as real booleans, which
    # every truthiness test and pass-through below reads the way a switch reads.
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, [PSCredential]$SourceSqlCredential,
        [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, [PSCredential]$DestinationSqlCredential,
        [object[]]$Login, [object[]]$ExcludeLogin, $ExcludeSystemLogins, $SyncSaName,
        [string]$OutFile, [object[]]$InputObject, [hashtable]$LoginRenameHashtable,
        $KillActiveConnection, $NewSid, $Force, $ObjectLevel, $ExcludePermissionSync,
        $ExcludeDatabaseMapping, $EnableException, $__realCmdlet)

    if ($Force) { $ConfirmPreference = 'none' }
    function Copy-Login {
        [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
        Param (
            $SourceServer,
            $DestServer,
            $Login,
            $Exclude
        )
        $destinstance = $DestServer.Name
        if ($LoginRenameHashtable.Keys -contains $Login.name) {
            $newUserName = $LoginRenameHashtable[$Login.name]
        } else {
            $newUserName = $Login.name
        }

        $copyLoginStatus = [PSCustomObject]@{
            SourceServer      = $sourceServer.Name
            DestinationServer = $destServer.Name
            Type              = "Login - $($Login.LoginType)"
            Name              = $newUserName
            DestinationLogin  = $newUserName
            SourceLogin       = $Login.name
            Status            = $null
            Notes             = $null
            DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
        }

        if ($ExcludeLogin -contains $Login.name) { continue }

        if ($Login.id -eq 1) { continue }

        if ($newUserName.StartsWith("##") -or $newUserName -eq 'sa') {
            Write-Message -Level Verbose -Message "Skipping $newUserName."
            continue
        }

        if ($newUserName -like "BUILTIN\Administrators" -and $sourceServer.HostPlatform -eq "Linux") {
            if ($__realCmdlet.ShouldProcess($destinstance, "Skipping BUILTIN\Administrators")) {
                Write-Message -Level Verbose -Message "BUILTIN\Administrators is a critical system login and should not be dropped. Skipping."
                $copyLoginStatus.Status = "Skipped"
                $copyLoginStatus.Notes = "BUILTIN\Administrators is a critical system login"
                $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            }
            continue
        }

        if ($Login.LoginType -like 'Window*' -and $destServer.DatabaseEngineEdition -eq 'SqlManagedInstance' ) {
            if ($__realCmdlet.ShouldProcess($destinstance, "$Login is a Windows login and not supported on a SQL Managed Instance, skipping on $destInstance")) {
                Write-Message -Level Verbose -Message "$Login is a Windows login and not supported on a SQL Managed Instance, skipping on $destInstance"
                $copyLoginStatus.Status = "Skipped"
                $copyLoginStatus.Notes = "$($Login.name) is a Windows login, not supported on a SQL Managed Instance"
                $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            }
            continue
        }

        # Here we don't need the FullComputerName, but only the machine name to compare to the host part of the login name. So ComputerName should be fine.
        $serverName = $sourceServer.ComputerName

        $currentLogin = $DestServer.ConnectionContext.truelogin

        if ($currentLogin -eq $newUserName -and $force) {
            if ($__realCmdlet.ShouldProcess($destinstance, "Login $newUserName is skipped because it is performing the migration")) {
                Write-Message -Level Verbose -Message "Cannot drop login performing the migration. Skipping."
                $copyLoginStatus.Status = "Skipped"
                $copyLoginStatus.Notes = "Current login"
                $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            }
            continue
        }

        if (($destServer.LoginMode -ne [Microsoft.SqlServer.Management.Smo.ServerLoginMode]::Mixed) -and ($Login.LoginType -eq [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin)) {
            Write-Message -Level Verbose -Message "$Destination does not have Mixed Mode enabled. [$($Login.Name)] is an SQL Login. Enable mixed mode authentication after the migration completes to use this type of login."
        }

        $userBase = ($Login.Name.Split("\")[0]).ToLowerInvariant()

        if ($serverName -eq $userBase -or $Login.Name.StartsWith("NT ")) {
            if ($sourceServer.ComputerName -ne $destServer.ComputerName) {
                if ($__realCmdlet.ShouldProcess($destinstance, "Skipping $($Login.Name) because it is a local machine name")) {
                    Write-Message -Level Verbose -Message "$($Login.Name) was skipped because it is a local machine name."
                    $copyLoginStatus.Status = "Skipped"
                    $copyLoginStatus.Notes = "Local machine name"
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                continue
            } else {
                if ($ExcludeSystemLogins) {
                    if ($__realCmdlet.ShouldProcess($destinstance, "$($Login.Name) was skipped because ExcludeSystemLogins was specified")) {
                        Write-Message -Level Verbose -Message "$($Login.Name) was skipped because ExcludeSystemLogins was specified."
                        $copyLoginStatus.Status = "Skipped"
                        $copyLoginStatus.Notes = "System login"
                        $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                }
                Write-Message -Level Verbose -Message "Skipping local login $($Login.Name) since the source and destination server reside on the same machine."
            }
        }

        if ($null -ne $destServer.Logins.Item($newUserName) -and !$force) {
            if ($__realCmdlet.ShouldProcess($destinstance, "Skipping $newUserName because it exists at destination")) {
                Write-Message -Level Verbose -Message "$newUserName already exists in destination. Use -Force to drop and recreate."
                $copyLoginStatus.Status = "Skipped"
                $copyLoginStatus.Notes = "Already exists on destination"
                $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            }
            continue
        }

        if ($null -ne $destServer.Logins.Item($newUserName) -and $force) {
            if ($newUserName -eq $destServer.ServiceAccount) {
                if ($__realCmdlet.ShouldProcess($destinstance, "$newUserName is the destination service account, skipping drop")) {
                    Write-Message -Level Verbose -Message "$newUserName is the destination service account. Skipping drop."
                    $copyLoginStatus.Status = "Skipped"
                    $copyLoginStatus.Notes = "Destination service account"
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                continue
            }

            if ($newUserName -like "BUILTIN\Administrators" -and $destServer.HostPlatform -eq "Linux") {
                if ($__realCmdlet.ShouldProcess($destinstance, "Skipping BUILTIN\Administrators")) {
                    Write-Message -Level Verbose -Message "BUILTIN\Administrators is a critical system login and should not be dropped. Skipping."
                    $copyLoginStatus.Status = "Skipped"
                    $copyLoginStatus.Notes = "BUILTIN\Administrators is a critical system login"
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                continue
            }

            # Check if dropping this Windows group would lock out the current user (Issue #8572)
            if ($Login.LoginType -eq "WindowsGroup") {
                # Only check if current login is not directly in the logins list (access via group only)
                $currentLoginIsDirect = $currentLogin -in $destServer.Logins.Name
                if (-not $currentLoginIsDirect) {
                    Write-Message -Level Verbose -Message "Current login '$currentLogin' is not a direct login on $destinstance"

                    # Check if this is a high-privilege group
                    # Note: $groupLogin is guaranteed to exist here because we're inside the block
                    # that checks: if ($null -ne $destServer.Logins.Item($newUserName) -and $force)
                    $groupLogin = $destServer.Logins.Item($newUserName)
                    $isHighPrivilege = $false

                    # Check for sysadmin or securityadmin roles
                    if ($groupLogin.IsMember("sysadmin") -or $groupLogin.IsMember("securityadmin")) {
                        $isHighPrivilege = $true
                    }

                    # Check for ALTER ANY LOGIN permission
                    if (-not $isHighPrivilege) {
                        try {
                            $splatPermissions = @{
                                SqlInstance = $destServer
                                Login       = $newUserName
                            }
                            $permissions = Get-DbaPermission @splatPermissions | Where-Object { $_.Permission -eq "ALTER ANY LOGIN" -and $_.State -eq "GRANT" }
                            if ($permissions) {
                                $isHighPrivilege = $true
                            }
                        } catch {
                            Write-Message -Level Verbose -Message "Could not check ALTER ANY LOGIN permission for $newUserName"
                        }
                    }

                    # If this is a high-privilege group, check if current user is a member
                    if ($isHighPrivilege) {
                        Write-Message -Level Verbose -Message "Group '$newUserName' has high privileges - checking membership"
                        try {
                            $memberCheckQuery = "EXEC xp_logininfo @acctname, @option = 'members'"
                            $splatMemberCheck = @{
                                SqlInstance     = $destServer
                                Query           = $memberCheckQuery
                                SqlParameter    = @{ acctname = $newUserName }
                                EnableException = $true
                            }
                            $members = Invoke-DbaQuery @splatMemberCheck
                            $memberNames = $members."account name"

                            if ($currentLogin -in $memberNames) {
                                if ($__realCmdlet.ShouldProcess($destinstance, "Skipping $newUserName - potential lockout risk")) {
                                    Write-Message -Level Warning -Message "Skipping $newUserName. You appear to access this server only through this Windows group. Dropping it with -Force may lock you out. Either: 1) Add your individual login first, 2) Use -ExcludeLogin to skip this group, or 3) Ensure you have another way to access this server."
                                    $copyLoginStatus.Status = "Skipped"
                                    $copyLoginStatus.Notes = "Potential lockout risk - current user may depend on this group for access"
                                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                }
                                continue
                            }
                        } catch {
                            # If we cannot enumerate members (permission issues), err on the side of caution
                            if ($__realCmdlet.ShouldProcess($destinstance, "Skipping $newUserName - cannot verify group membership")) {
                                Write-Message -Level Warning -Message "Cannot enumerate members of $newUserName. If you are a member of this group, dropping it may lock you out. Either: 1) Add your individual login first, 2) Use -ExcludeLogin to skip this group, or 3) Ensure you have another way to access this server."
                                $copyLoginStatus.Status = "Skipped"
                                $copyLoginStatus.Notes = "Cannot verify group membership - potential lockout risk"
                                $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            }
                            continue
                        }
                    }
                }
            }

            if ($__realCmdlet.ShouldProcess($destinstance, "Dropping $newUserName")) {

                # Kill connections, delete user
                Write-Message -Level Verbose -Message "Attempting to migrate $newUserName"
                Write-Message -Level Verbose -Message "Force was specified. Attempting to drop $newUserName on $destinstance."

                try {
                    $ownedDbs = $destServer.Databases | Where-Object Owner -eq $newUserName

                    foreach ($ownedDb in $ownedDbs) {
                        Write-Message -Level Verbose -Message "Changing database owner for $($ownedDb.name) from $newUserName to sa."
                        $ownedDb.SetOwner('sa')
                        $ownedDb.Alter()
                    }

                    $ownedJobs = $destServer.JobServer.Jobs | Where-Object OwnerLoginName -eq $newUserName

                    foreach ($ownedJob in $ownedJobs) {
                        Write-Message -Level Verbose -Message "Changing job owner for $($ownedJob.name) from $newUserName to sa."
                        $ownedJob.Set_OwnerLoginName('sa')
                        $ownedJob.Alter()
                    }

                    $activeConnections = $destServer.EnumProcesses() | Where-Object Login -eq $newUserName

                    if ($activeConnections -and $KillActiveConnection) {
                        if (!$destServer.Logins.Item($newUserName).IsDisabled) {
                            $disabled = $true
                            $destServer.Logins.Item($newUserName).Disable()
                        }

                        $activeConnections | ForEach-Object { $destServer.KillProcess($_.Spid) }
                        Write-Message -Level Verbose -Message "-KillActiveConnection was provided. There are $($activeConnections.Count) active connections killed."
                    } elseif ($activeConnections) {
                        Write-Message -Level Verbose -Message "There are $($activeConnections.Count) active connections found for the login $newUserName. Utilize -KillActiveConnection to kill the connections."
                    }
                    try {
                        $destServer.Logins.Item($newUserName).Drop()
                    } catch {
                        # just in case the kill didn't work, it'll leave behind a disabled account
                        if ($disabled) { $destServer.Logins.Item($newUserName).Enable() }
                        throw $_
                    }
                    Write-Message -Level Verbose -Message "Successfully dropped $newUserName on $destinstance."
                } catch {
                    $copyLoginStatus.Status = "Failed"
                    $copyLoginStatus.Notes = (Get-ErrorMessage -Record $_)
                    $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Could not drop $newuserName on $destinstance | $PSItem"
                    continue
                }
            }
        }

        if ($__realCmdlet.ShouldProcess($destinstance, "Adding SQL login $newUserName")) {

            Write-Message -Level Verbose -Message "Attempting to add $newUserName to $destinstance."
            try {
                $splatNewLogin = @{
                    SqlInstance          = $destServer
                    InputObject          = $Login
                    NewSid               = $NewSid
                    LoginRenameHashtable = $LoginRenameHashtable
                }
                if ($Login.DefaultDatabase -notin $destServer.Databases.Name) {
                    $copyLoginStatus.Notes = "Database $($Login.DefaultDatabase) does not exist on $destServer, switching DefaultDatabase to 'master' for $($Login.Name)"
                    Write-Message -Level Warning -Message $copyLoginStatus.Notes
                    $splatNewLogin.DefaultDatabase = 'master'
                }
                $destLogin = New-DbaLogin @splatNewLogin -EnableException:$true
                $copyLoginStatus.Status = "Successful"
            } catch {
                $copyLoginStatus.Status = "Failed"
                $copyLoginStatus.Notes = (Get-ErrorMessage -Record $_)
                $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                Write-Message -Level Verbose -Message "Could not create $newuserName on $destinstance | $PSItem"
                continue
            }

            $copyLoginStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

            if (-not $ExcludePermissionSync) {
                if ($__realCmdlet.ShouldProcess($destinstance, "Updating SQL login $newUserName permissions")) {
                    # In rare cases, when the instance has a case sensitive collation and there are two logins that differ only in case, New-DbaLogin will return them both into $destLogin
                    # So we loop, just in case...
                    foreach ($dl in $destLogin) {
                        $splatPermission = @{
                            SourceServer           = $sourceServer
                            SourceLogin            = $Login
                            DestServer             = $destServer
                            DestLogin              = $dl
                            ObjectLevel            = $ObjectLevel
                            ExcludeDatabaseMapping = $ExcludeDatabaseMapping
                        }
                        Update-SqlPermission @splatPermission
                    }
                }
            }
        }
    }

    if (Test-FunctionInterrupt) { return }
    $loginsCollection = @()
    if ($InputObject) {
        $loginsCollection += $InputObject
    } else {
        $loginsCollection += Get-DbaLogin -SqlInstance $Source -SqlCredential $SourceSqlCredential -Login $Login -EnableException:$EnableException
    }

    # Warn if specific logins were requested but not found
    if ($Login -and -not $InputObject) {
        $foundLogins = $loginsCollection.Name
        foreach ($requestedLogin in $Login) {
            if ($requestedLogin -notin $foundLogins) {
                Write-Message -Level Warning -Message "Login '$requestedLogin' not found on source instance $Source" -FunctionName Copy-DbaLogin -ModuleName "dbatools"
            }
        }
    }

    if ($OutFile) {
        $splatExportLogin = @{
            SqlInstance     = $Source
            SqlCredential   = $SourceSqlCredential
            FilePath        = $OutFile
            Login           = $loginsCollection
            ObjectLevel     = $ObjectLevel
            ExcludeLogin    = $ExcludeLogin
            EnableException = $EnableException
        }
        if ($ExcludeDatabaseMapping) {
            $splatExportLogin.ExcludeDatabase = $true
        }
        return (Export-DbaLogin @splatExportLogin)
    }
    foreach ($loginObject in $loginsCollection) {
        $sourceServer = $loginObject.Parent
        $sourceVersionMajor = $sourceServer.VersionMajor

        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -AzureUnsupported
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue -FunctionName Copy-DbaLogin
            }

            $destVersionMajor = $destServer.VersionMajor
            if ($sourceVersionMajor -gt 10 -and $destVersionMajor -lt 11) {
                Stop-Function -Message "Login migration from version $sourceVersionMajor to $destVersionMajor is not supported." -Target $sourceServer -FunctionName Copy-DbaLogin
            }

            if ($sourceVersionMajor -lt 8 -or $destVersionMajor -lt 8) {
                Stop-Function -Message "SQL Server 7 and below are not supported." -Target $sourceServer -FunctionName Copy-DbaLogin
            }

            if ($destserver.ConnectionContext.TrueLogin -notin $destserver.Logins.Name -and $Force) {
                if ($Login -or $ExcludeLogin -or $InputObject) {
                    Write-Message -Level Verbose -Message "Force was used and $($destserver.ConnectionContext.TrueLogin) not found in logins list but an explicit Login or ExcludeLogin was specified, so we trust you won't drop the group that allows $($destserver.ConnectionContext.TrueLogin) access. Proceeding." -FunctionName Copy-DbaLogin -ModuleName "dbatools"
                } else {
                    Stop-Function -Message "Force was used, no explicit -Login or -ExcludeLogin was specified and $($destserver.ConnectionContext.TrueLogin) cannot be found in the logins list. It may be part of a group. This will likely result in you being locked out of the server. To use Force, $($destserver.ConnectionContext.TrueLogin) must be added directly to logins before proceeding." -Target $destserver -FunctionName Copy-DbaLogin
                    continue
                }
            }

            Write-Message -Level Verbose -Message "Attempting Login Migration." -FunctionName Copy-DbaLogin -ModuleName "dbatools"
            Copy-Login -sourceserver $sourceServer -destserver $destServer -Login $loginObject -Exclude $ExcludeLogin

            if ($SyncSaName) {
                $sa = $sourceServer.Logins | Where-Object id -eq 1
                $destSa = $destServer.Logins | Where-Object id -eq 1
                $saName = $sa.Name
                if ($saName -ne $destSa.name) {
                    Write-Message -Level Verbose -Message "Changing sa username to match source ($saName)." -FunctionName Copy-DbaLogin -ModuleName "dbatools"
                    if ($__realCmdlet.ShouldProcess($destinstance, "Changing sa username to match source ($saName)")) {
                        try {
                            $destSa.Rename($saName)
                            $destSa.Alter()
                        } catch {
                            Write-Message -Level Verbose -Message "Could not change sa username to match source ($saName) on $destinstance | $PSItem" -FunctionName Copy-DbaLogin -ModuleName "dbatools"
                        }
                    }
                }
            }
        }
    }
} $Source $SourceSqlCredential $Destination $DestinationSqlCredential $Login $ExcludeLogin $ExcludeSystemLogins $SyncSaName $OutFile $InputObject $LoginRenameHashtable $KillActiveConnection $NewSid $Force $ObjectLevel $ExcludePermissionSync $ExcludeDatabaseMapping $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
