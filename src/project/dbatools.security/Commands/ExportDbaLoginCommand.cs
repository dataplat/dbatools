#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports login definitions from a SQL Server instance as T-SQL scripts.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that login enumeration, the
/// generated T-SQL, permission scripting, file output, and dbatools stream and error handling stay
/// observable-identical to the script implementation.
/// </para>
/// <para>
/// The script has begin, process, and end blocks and produces all of its output from the end block,
/// which walks a collection the process block fills. The port collects the piped InputObject records
/// across ProcessRecord and then, in EndProcessing, runs ONE hop that executes the begin body, the
/// process body over the collected records, and the end body in a single scope - so the accumulators
/// persist naturally. The process body is only run when a record was actually processed, matching the
/// script (an empty pipeline runs begin and end but not process); it is dot-sourced so its early
/// returns leave only that block and the end body still emits.
/// </para>
/// <para>
/// The two config-value parameter defaults (Path, BatchSeparator) are reproduced inside the hop,
/// applied only when the caller did not bind them. The end block's Get-ExportFilePath call reads the
/// caller's bound Path and FilePath, which a hop cannot see, so those bound values are carried in
/// explicitly. Every switch parameter is carried as a plain bool and received untyped, because a
/// switch in the inner CmdletBinding scriptblock is excluded from positional binding.
/// </para>
/// </remarks>
[Cmdlet(VerbsData.Export, "DbaLogin", SupportsShouldProcess = true)]
public sealed class ExportDbaLoginCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Server, database, or login objects to export, typically piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 2)]
    public object[]? InputObject { get; set; }

    /// <summary>The login or logins to export.</summary>
    [Parameter(Position = 3)]
    public object[]? Login { get; set; }

    /// <summary>Logins to exclude.</summary>
    [Parameter(Position = 4)]
    public object[]? ExcludeLogin { get; set; }

    /// <summary>The database or databases whose login mappings are exported.</summary>
    [Parameter(Position = 5)]
    public object[]? Database { get; set; }

    /// <summary>A default database to assign in the generated CREATE LOGIN statements.</summary>
    [Parameter(Position = 6)]
    public string? DefaultDatabase { get; set; }

    /// <summary>The directory the exported script is written to.</summary>
    [Parameter(Position = 7)]
    public string? Path { get; set; }

    /// <summary>An explicit output file path.</summary>
    [Parameter(Position = 8)]
    [Alias("OutFile", "FileName")]
    public string? FilePath { get; set; }

    /// <summary>The file encoding of the exported script.</summary>
    [Parameter(Position = 9)]
    [PsStringCast]
    [ValidateSet("ASCII", "BigEndianUnicode", "Byte", "String", "Unicode", "UTF7", "UTF8", "Unknown")]
    public string Encoding { get; set; } = "UTF8";

    /// <summary>The batch separator placed between statements.</summary>
    [Parameter(Position = 10)]
    public string? BatchSeparator { get; set; }

    /// <summary>The destination SQL Server version to target the generated script at.</summary>
    [Parameter(Position = 11)]
    [PsStringCast]
    [ValidateSet("SQLServer2000", "SQLServer2005", "SQLServer2008/2008R2", "SQLServer2012", "SQLServer2014", "SQLServer2016", "SQLServer2017", "SQLServer2019", "SQLServer2022")]
    public string? DestinationVersion { get; set; }

    /// <summary>Excludes SQL Agent job ownership from the export.</summary>
    [Parameter]
    public SwitchParameter ExcludeJobs { get; set; }

    /// <summary>Excludes database-level mappings from the export.</summary>
    [Parameter]
    [Alias("ExcludeDatabases")]
    public SwitchParameter ExcludeDatabase { get; set; }

    /// <summary>Excludes the password hash from exported SQL logins.</summary>
    [Parameter]
    public SwitchParameter ExcludePassword { get; set; }

    /// <summary>Prevents overwriting an existing output file.</summary>
    [Parameter]
    [Alias("NoOverwrite")]
    public SwitchParameter NoClobber { get; set; }

    /// <summary>Appends to the output file instead of replacing it.</summary>
    [Parameter]
    public SwitchParameter Append { get; set; }

    /// <summary>Omits the descriptive comment prefix from the script.</summary>
    [Parameter]
    public SwitchParameter NoPrefix { get; set; }

    /// <summary>Returns the generated SQL to the pipeline instead of writing a file.</summary>
    [Parameter]
    public SwitchParameter Passthru { get; set; }

    /// <summary>Scripts object-level permissions for each login.</summary>
    [Parameter]
    public SwitchParameter ObjectLevel { get; set; }

    /// <summary>Includes role permissions in the export.</summary>
    [Parameter]
    public SwitchParameter IncludeRolePermissions { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private readonly List<object?[]?> _batches = new List<object?[]?>();

    /// <summary>Records each pipeline record's input as a batch; the work runs once in EndProcessing.</summary>
    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // One batch per ProcessRecord call, preserving the boundaries the script's process block saw
        // (an empty pipeline never calls ProcessRecord, so there are no batches and process never runs).
        _batches.Add(InputObject);
    }

    /// <summary>Runs the begin, process, and end logic in one hop against the collected input.</summary>
    protected override void EndProcessing()
    {
        if (Interrupted)
            return;

        // [DEF-001] streamed via InvokeScopedStreaming: the hop body loops emitting per-item and
        // carries reachable terminating throws (-Continue Stop-Function under -EnableException), so a
        // buffered InvokeScoped would lose an earlier item's emit when a later item throws. Streaming
        // yields each record as produced; no state carry on this row.
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
            SqlInstance, SqlCredential, _batches.ToArray(), Login, ExcludeLogin, Database,
            DefaultDatabase, Path, FilePath, Encoding, BatchSeparator, DestinationVersion,
            ExcludeJobs.ToBool(), ExcludeDatabase.ToBool(), ExcludePassword.ToBool(), NoClobber.ToBool(),
            Append.ToBool(), NoPrefix.ToBool(), Passthru.ToBool(), ObjectLevel.ToBool(),
            IncludeRolePermissions.ToBool(), EnableException.ToBool(), this,
            TestBound(nameof(Path)), TestBound(nameof(BatchSeparator)), BoundValue("Path"), BoundValue("FilePath"),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private object? BoundValue(string name)
    {
        return MyInvocation.BoundParameters.TryGetValue(name, out object? value) ? value : null;
    }

    // PS: the begin body, the process body (dot-sourced, run only when a record was processed), and
    // the end body VERBATIM. Substitutions only: $Pscmdlet -> $__realCmdlet; -FunctionName on every
    // direct Stop-Function/Write-Message; $PSBoundParameters.Path/.FilePath -> the carried bound
    // values; and $MyInvocation.MyCommand.Name -> the literal command name (a hop scriptblock cannot
    // resolve the public command identity). The two config-value defaults and the process/end split
    // are hop adaptations described in the class remarks.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $__batches, $Login, $ExcludeLogin, $Database, $DefaultDatabase, $Path, $FilePath, $Encoding, $BatchSeparator, $DestinationVersion, $ExcludeJobs, $ExcludeDatabase, $ExcludePassword, $NoClobber, $Append, $NoPrefix, $Passthru, $ObjectLevel, $IncludeRolePermissions, $EnableException, $__realCmdlet, $__pathBound, $__batchSepBound, $__boundPathValue, $__boundFilePathValue, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, $__batches, [object[]]$Login, [object[]]$ExcludeLogin, [object[]]$Database, [string]$DefaultDatabase, [string]$Path, [string]$FilePath, [string]$Encoding, [string]$BatchSeparator, [string]$DestinationVersion, $ExcludeJobs, $ExcludeDatabase, $ExcludePassword, $NoClobber, $Append, $NoPrefix, $Passthru, $ObjectLevel, $IncludeRolePermissions, $EnableException, $__realCmdlet, $__pathBound, $__batchSepBound, $__boundPathValue, $__boundFilePathValue, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not $__pathBound) { $Path = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport' }
    if (-not $__batchSepBound) { $BatchSeparator = Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator' }

            $null = Test-ExportDirectory -Path $Path
            $outsql = @()
            $instanceArray = @()
            $logonCollection = New-Object System.Collections.ArrayList
            if ($IsLinux -or $IsMacOs) {
                $executingUser = $env:USER
            } else {
                $executingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            }
            $commandName = "Export-DbaLogin"
    
            $eol = [System.Environment]::NewLine

    # One process invocation per collected pipeline record (batch), matching the function's
    # per-record process block; the body is dot-sourced so an early return leaves only the
    # current batch and the remaining batches plus the end block still run.
    foreach ($__batch in $__batches) {
        $InputObject = $__batch
        . {
                if (Test-FunctionInterrupt) { return }
        
                if (-not $InputObject -and -not $SqlInstance) {
                    Stop-Function -Message "You must pipe in a login, database, or server or specify a SqlInstance" -FunctionName Export-DbaLogin
                    return
                }
        
                if ($SqlInstance) {
                    $InputObject = $SqlInstance
                }
        
                foreach ($input in $InputObject) {
                    $inputType = $input.GetType().FullName
                    switch ($inputType) {
                        'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                            Write-Message -Level Verbose -Message "Processing Server through InputObject" -FunctionName Export-DbaLogin -ModuleName "dbatools"
                            try {
                                $server = Connect-DbaInstance -SqlInstance $input -SqlCredential $SqlCredential
                            } catch {
                                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $input -Continue -FunctionName Export-DbaLogin
                            }
                        }
                        'Microsoft.SqlServer.Management.Smo.Server' {
                            Write-Message -Level Verbose -Message "Processing Server through InputObject" -FunctionName Export-DbaLogin -ModuleName "dbatools"
                            $server = Connect-DbaInstance -SqlInstance $input -SqlCredential $SqlCredential
                        }
                        'Microsoft.SqlServer.Management.Smo.Database' {
                            Write-Message -Level Verbose -Message "Processing Database through InputObject" -FunctionName Export-DbaLogin -ModuleName "dbatools"
                            $server = $input.Parent
                            $Database = $input
                        }
                        'Microsoft.SqlServer.Management.Smo.Login' {
                            Write-Message -Level Verbose -Message "Processing Login through InputObject" -FunctionName Export-DbaLogin -ModuleName "dbatools"
                            $server = $input.Parent
                            $Login = $input
                        }
                        default {
                            Stop-Function -Message "InputObject is not a server, database, or login." -FunctionName Export-DbaLogin
                            return
                        }
                    }
        
                    if ($ExcludeDatabase -eq $false -or $Database) {
                        # if we got a database or a list of databases passed
                        # and we need to enumerate mappings, login.enumdatabasemappings() takes forever
                        # the cool thing though is that database.enumloginmappings() is fast. A lot.
                        # if we get a list of databases passed (or even the default list of all the databases)
                        # we save ourself a call to enumloginmappings if there is no map at all
                        $DbMapping = @()
                        $DbsToMap = $server.Databases
                        if ($Database) {
                            if ($Database[0].GetType().FullName -eq 'Microsoft.SqlServer.Management.Smo.Database') {
                                $DbsToMap = $DbsToMap | Where-Object Name -in $Database.Name
                            } else {
                                $DbsToMap = $DbsToMap | Where-Object Name -in $Database
                            }
                        }
                        foreach ($db in $DbsToMap) {
                            if ($db.IsAccessible -eq $false) {
                                continue
                            }
                            $dbmap = $db.EnumLoginMappings()
                            foreach ($el in $dbmap) {
                                $DbMapping += [PSCustomObject]@{
                                    Database  = $db.Name
                                    UserName  = $el.Username
                                    LoginName = $el.LoginName
                                }
                            }
                        }
                    }
        
                    $serverLogins = $server.Logins
        
                    if ($Login) {
                        if ($Login[0].GetType().FullName -eq 'Microsoft.SqlServer.Management.Smo.Login') {
                            $serverLogins = $serverLogins | Where-Object { $_.Name -in $Login.Name }
                        } else {
                            $serverLogins = $serverLogins | Where-Object { $_.Name -in $Login }
                        }
                    }
        
                    if ($Database) {
                        $serverLogins = $serverLogins | Where-Object { $_.Name -in $DbMapping.LoginName }
                    }
        
                    foreach ($sourceLogin in $serverLogins) {
                        Write-Message -Level Verbose -Message "Processing login $sourceLogin" -FunctionName Export-DbaLogin -ModuleName "dbatools"
                        $userName = $sourceLogin.name
        
                        if ($ExcludeLogin -contains $userName) {
                            Write-Message -Level Warning -Message "Skipping $userName" -FunctionName Export-DbaLogin -ModuleName "dbatools"
                            continue
                        }
        
                        if ($userName.StartsWith("##") -or $userName -eq 'sa') {
                            Write-Message -Level Warning -Message "Skipping $userName" -FunctionName Export-DbaLogin -ModuleName "dbatools"
                            continue
                        }
        
                        $serverName = $server
        
                        $userBase = ($userName.Split("\")[0]).ToLowerInvariant()
                        if ($serverName -eq $userBase -or $userName.StartsWith("NT ")) {
                            if ($__realCmdlet.ShouldProcess("console", "Stating $userName is skipped because it is a local machine name")) {
                                Write-Message -Level Warning -Message "$userName is skipped because it is a local machine name" -FunctionName Export-DbaLogin -ModuleName "dbatools"
                                continue
                            }
                        }
        
                        if ($__realCmdlet.ShouldProcess("Outfile", "Adding T-SQL for login $userName")) {
                            if ($Path -or $FilePath) {
                                Write-Message -Level Verbose -Message "Exporting $userName" -FunctionName Export-DbaLogin -ModuleName "dbatools"
                            }
        
                            $outsql += "$($eol)USE master$eol"
                            # Getting some attributes
                            if ($DefaultDatabase) {
                                $defaultDb = $DefaultDatabase
                            } else {
                                $defaultDb = $sourceLogin.DefaultDatabase
                            }
                            $language = $sourceLogin.Language
        
                            if ($sourceLogin.PasswordPolicyEnforced -eq $false) {
                                $checkPolicy = "OFF"
                            } else {
                                $checkPolicy = "ON"
                            }
        
                            if (!$sourceLogin.PasswordExpirationEnabled) {
                                $checkExpiration = "OFF"
                            } else {
                                $checkExpiration = "ON"
                            }
        
                            # Attempt to script out SQL Login
                            if ($sourceLogin.LoginType -eq "SqlLogin") {
                                if (!$ExcludePassword) {
                                    $sourceLoginName = $sourceLogin.name
        
                                    switch ($server.versionMajor) {
                                        0 {
                                            $sql = "SELECT CONVERT(VARBINARY(256),password) AS hashedpass FROM master.dbo.syslogins WHERE loginname='$sourceLoginName'"
                                        }
                                        8 {
                                            $sql = "SELECT CONVERT(VARBINARY(256),password) AS hashedpass FROM dbo.syslogins WHERE name='$sourceLoginName'"
                                        }
                                        9 {
                                            $sql = "SELECT CONVERT(VARBINARY(256),password_hash) AS hashedpass FROM sys.sql_logins WHERE name='$sourceLoginName'"
                                        }
                                        default {
                                            $sql = "SELECT CAST(CONVERT(VARCHAR(256), CAST(LOGINPROPERTY(name,'PasswordHash') AS VARBINARY(256)), 1) AS NVARCHAR(MAX)) AS hashedpass FROM sys.server_principals WHERE principal_id = $($sourceLogin.id)"
                                        }
                                    }
        
                                    try {
                                        $hashedPass = $server.ConnectionContext.ExecuteScalar($sql)
                                    } catch {
                                        $hashedPassDt = $server.Databases['master'].ExecuteWithResults($sql)
                                        $hashedPass = $hashedPassDt.Tables[0].Rows[0].Item(0)
                                    }
        
                                    if ($hashedPass.GetType().Name -ne "String") {
                                        $passString = "0x"; $hashedPass | ForEach-Object {
                                            $passString += ("{0:X}" -f $_).PadLeft(2, "0")
                                        }
                                        $hashedPass = $passString
                                    }
                                } else {
                                    $hashedPass = '#######'
                                }
        
                                $sid = "0x"; $sourceLogin.sid | ForEach-Object {
                                    $sid += ("{0:X}" -f $_).PadLeft(2, "0")
                                }
                                $outsql += "IF NOT EXISTS (SELECT loginname FROM master.dbo.syslogins WHERE name = '$userName') CREATE LOGIN [$userName] WITH PASSWORD = $hashedPass HASHED, SID = $sid, DEFAULT_DATABASE = [$defaultDb], CHECK_POLICY = $checkPolicy, CHECK_EXPIRATION = $checkExpiration, DEFAULT_LANGUAGE = [$language]"
                            }
                            # Attempt to script out Windows User
                            elseif ($sourceLogin.LoginType -eq "WindowsUser" -or $sourceLogin.LoginType -eq "WindowsGroup") {
                                $outsql += "IF NOT EXISTS (SELECT loginname FROM master.dbo.syslogins WHERE name = '$userName') CREATE LOGIN [$userName] FROM WINDOWS WITH DEFAULT_DATABASE = [$defaultDb], DEFAULT_LANGUAGE = [$language]"
                            }
                            # This script does not currently support certificate mapped or asymmetric key users.
                            else {
                                Write-Message -Level Warning -Message "$($sourceLogin.LoginType) logins not supported. $($sourceLogin.Name) skipped" -FunctionName Export-DbaLogin -ModuleName "dbatools"
                                continue
                            }
        
                            if ($sourceLogin.IsDisabled) {
                                $outsql += "ALTER LOGIN [$userName] DISABLE"
                            }
        
                            if ($sourceLogin.DenyWindowsLogin) {
                                $outsql += "DENY CONNECT SQL TO [$userName]"
                            }
                        }
        
                        # Server Roles: sysadmin, bulklogin, etc
                        foreach ($role in $server.Roles) {
                            $roleName = $role.Name
        
                            # SMO changed over time
                            try {
                                $roleMembers = $role.EnumMemberNames()
                            } catch {
                                $roleMembers = $role.EnumServerRoleMembers()
                            }
        
                            if ($roleMembers -contains $userName) {
                                if (($server.VersionMajor -lt 11 -and [string]::IsNullOrEmpty($destinationVersion)) -or ($DestinationVersion -in "SQLServer2000", "SQLServer2005", "SQLServer2008/2008R2")) {
                                    $outsql += "EXEC sp_addsrvrolemember @rolename=N'$roleName', @loginame=N'$userName'"
                                } else {
                                    $outsql += "ALTER SERVER ROLE [$roleName] ADD MEMBER [$userName]"
                                }
                            }
                        }
        
                        if ($ExcludeJobs -eq $false) {
                            $ownedJobs = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -eq $userName }
        
                            foreach ($ownedJob in $ownedJobs) {
                                $ownedJob = $ownedJob -replace ("'", "''")
                                $outsql += "$($eol)USE msdb$eol"
                                $outsql += "EXEC msdb.dbo.sp_update_job @job_name=N'$ownedJob', @owner_login_name=N'$userName'"
                            }
                        }
        
                        if ($server.VersionMajor -ge 9) {
                            # These operations are only supported by SQL Server 2005 and above.
                            # Securables: Connect SQL, View any database, Administer Bulk Operations, etc.
        
                            $perms = $server.EnumServerPermissions($userName)
                            $outsql += "$($eol)USE master$eol"
                            foreach ($perm in $perms) {
                                $permState = $perm.permissionstate
                                $permType = $perm.PermissionType
                                $grantor = $perm.grantor
        
                                if ($permState -eq "GrantWithGrant") {
                                    $grantWithGrant = "WITH GRANT OPTION"
                                    $permState = "GRANT"
                                } else {
                                    $grantWithGrant = $null
                                }
        
                                $outsql += "$permState $permType TO [$userName] $grantWithGrant AS [$grantor]"
                            }
        
                            # Credential mapping. Credential removal not currently supported for Syncs.
                            $loginCredentials = $server.Credentials | Where-Object { $_.Identity -eq $sourceLogin.Name }
                            foreach ($credential in $loginCredentials) {
                                $credentialName = $credential.Name
                                $outsql += "PRINT '$userName is associated with the $credentialName credential'"
                            }
                        }
        
                        if ($ExcludeDatabase -eq $false) {
                            $dbs = $sourceLogin.EnumDatabaseMappings() | Sort-Object DBName
        
                            if ($Database) {
                                if ($Database[0].GetType().FullName -eq 'Microsoft.SqlServer.Management.Smo.Database') {
                                    $dbs = $dbs | Where-Object { $_.DBName -in $Database.Name }
                                } else {
                                    $dbs = $dbs | Where-Object { $_.DBName -in $Database }
                                }
                            }
        
                            # Adding database mappings and securables
                            foreach ($db in $dbs) {
                                $dbName = $db.dbname
                                $sourceDb = $server.Databases[$dbName]
                                $dbUserName = $db.username
        
                                $outsql += "$($eol)USE [$dbName]$eol"
        
                                $scriptOptions = New-DbaScriptingOption
                                $scriptVersion = $sourceDb.CompatibilityLevel
                                $scriptOptions.TargetServerVersion = [Microsoft.SqlServer.Management.Smo.SqlServerVersion]::$scriptVersion
                                $scriptOptions.ContinueScriptingOnError = $false
                                $scriptOptions.IncludeDatabaseContext = $false
                                $scriptOptions.IncludeIfNotExists = $true
        
                                $userRoles = foreach ($role in $sourceDb.Roles) {
                                    if ($role.EnumMembers() -contains $dbUserName) {
                                        $role
                                    }
                                }
        
                                $roleDefinitionScripts = @()
                                $rolePermissionScripts = @()
                                if ($IncludeRolePermissions) {
                                    $roleScriptingOptions = New-DbaScriptingOption
                                    $roleScriptingOptions.ContinueScriptingOnError = $false
                                    $roleScriptingOptions.IncludeDatabaseContext = $false
                                    $roleScriptingOptions.IncludeIfNotExists = $true
        
                                    foreach ($role in ($userRoles | Where-Object { $_.IsFixedRole -eq $false })) {
                                        $roleDefinitionScript = @($role.Script($roleScriptingOptions))
                                        $splatExportRole = @{
                                            SqlInstance            = $server
                                            Database               = $dbName
                                            Role                   = $role.Name
                                            ScriptingOptionsObject = $roleScriptingOptions
                                            Passthru               = $true
                                            NoPrefix               = $true
                                            BatchSeparator         = ""
                                        }
                                        try {
                                            $roleScript = @(Export-DbaDbRole @splatExportRole)
                                            if ($roleScript) {
                                                $roleDefinitionScripts += $roleDefinitionScript
                                                $rolePermissionScripts += $roleScript | Select-Object -Skip $roleDefinitionScript.Count
                                            }
                                        } catch {
                                            Write-Message -Level Warning -Message "Failed to export permissions for role $($role.Name) in database $dbName : $($_.Exception.Message)" -FunctionName Export-DbaLogin -ModuleName "dbatools"
                                        }
                                    }
                                }
        
                                if ($ObjectLevel) {
                                    # Exporting all permissions
                                    $scriptOptions.AllowSystemObjects = $true
                                    $scriptOptions.IncludeDatabaseRoleMemberships = $true
        
                                    $exportSplat = @{
                                        SqlInstance            = $server
                                        Database               = $dbName
                                        User                   = $dbUsername
                                        ScriptingOptionsObject = $scriptOptions
                                    }
                                    # remove batch separator if the $BatchSeparator string is empty
                                    if (-Not $BatchSeparator) {
                                        $scriptOptions.NoCommandTerminator = $true
                                        $exportSplat.ExcludeGoBatchSeparator = $true
                                    }
                                    if ($rolePermissionScripts) {
                                        $outsql += $rolePermissionScripts
                                    }
                                    try {
                                        $userScript = Export-DbaUser @exportSplat -Passthru -EnableException
                                        $outsql += $userScript
                                    } catch {
                                        Stop-Function -Message "Failed to extract permissions for user $dbUserName in database $dbName" -Continue -ErrorRecord $_ -FunctionName Export-DbaLogin
                                    }
                                } else {
                                    try {
                                        $sql = $server.Databases[$dbName].Users[$dbUserName].Script($scriptOptions)
                                        $outsql += $sql
                                    } catch {
                                        Write-Message -Level Warning -Message "User cannot be found in selected database" -FunctionName Export-DbaLogin -ModuleName "dbatools"
                                    }
        
                                    if ($roleDefinitionScripts) {
                                        $outsql += $roleDefinitionScripts
                                    }
                                    if ($rolePermissionScripts) {
                                        $outsql += $rolePermissionScripts
                                    }
        
                                    # Skipping updating dbowner
        
                                    # Database Roles: db_owner, db_datareader, etc
                                    foreach ($role in $userRoles) {
                                        $roleName = $role.Name
                                        if (($server.VersionMajor -lt 11 -and [string]::IsNullOrEmpty($destinationVersion)) -or ($DestinationVersion -in "SQLServer2000", "SQLServer2005", "SQLServer2008/2008R2")) {
                                            $outsql += "EXEC sp_addrolemember @rolename=N'$roleName', @membername=N'$dbUserName'"
                                        } else {
                                            $outsql += "ALTER ROLE [$roleName] ADD MEMBER [$dbUserName]"
                                        }
                                    }
        
                                    # Connect, Alter Any Assembly, etc
                                    $perms = $sourceDb.EnumDatabasePermissions($dbUserName)
                                    foreach ($perm in $perms) {
                                        $permState = $perm.PermissionState
                                        $permType = $perm.PermissionType
                                        $grantor = $perm.Grantor
        
                                        if ($permState -eq "GrantWithGrant") {
                                            $grantWithGrant = "WITH GRANT OPTION"
                                            $permState = "GRANT"
                                        } else {
                                            $grantWithGrant = $null
                                        }
        
                                        $outsql += "$permState $permType TO [$userName] $grantWithGrant AS [$grantor]"
                                    }
                                }
                            }
                        }
                        $loginObject = [PSCustomObject]@{
                            Name     = $userName
                            Instance = $server.Name
                            Sql      = $outsql
                        }
                        $logonCollection.Add($loginObject) | Out-Null
                        $outsql = @()
                    }
                }
        }
    }

            foreach ($login in $logonCollection) {
                if ($NoPrefix) {
                    $prefix = $null
                } else {
                    $prefix = "/*$eol`tCreated by $executingUser using dbatools $commandName for objects on $($login.Instance) at $(Get-Date -Format (Get-DbatoolsConfigValue -FullName 'Formatting.DateTime'))$eol`tSee https://dbatools.io/$commandName for more information$eol*/"
                }
    
                if ($BatchSeparator) {
                    $sql = $login.SQL -join "$eol$BatchSeparator$eol"
                    #add the final GO
                    $sql += "$eol$BatchSeparator"
                } else {
                    $sql = $login.SQL
                }
    
    
    
                if ($Passthru) {
                    if ($null -ne $prefix) {
                        $sql = $prefix + $sql
                    }
                    $sql
                } elseif ($Path -Or $FilePath) {
                    if ($instanceArray -notcontains $($login.Instance)) {
                        if ($null -ne $prefix) {
                            $sql = $prefix + $sql
                        }
                        $scriptPath = Get-ExportFilePath -Path $__boundPathValue -FilePath $__boundFilePathValue -Type sql -ServerName $login.Instance
                        $sql | Out-File -Encoding $Encoding -FilePath $scriptPath -Append:$Append -NoClobber:$NoClobber
                        $instanceArray += $login.Instance
                        Get-ChildItem $scriptPath
                    } else {
                        $sql | Out-File -Encoding $Encoding -FilePath $scriptPath -Append
                    }
                } else {
                    $sql
                }
            }
} $SqlInstance $SqlCredential $__batches $Login $ExcludeLogin $Database $DefaultDatabase $Path $FilePath $Encoding $BatchSeparator $DestinationVersion $ExcludeJobs $ExcludeDatabase $ExcludePassword $NoClobber $Append $NoPrefix $Passthru $ObjectLevel $IncludeRolePermissions $EnableException $__realCmdlet $__pathBound $__batchSepBound $__boundPathValue $__boundFilePathValue $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
