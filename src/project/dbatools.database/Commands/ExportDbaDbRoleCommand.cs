#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports database roles (and optionally their members) as T-SQL. Port of
/// public/Export-DbaDbRole.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A collect-across-pipeline / emit-at-end command (InputObject is ValueFromPipeline), shipped as
/// THREE hops mapping to BeginProcessing / ProcessRecord / EndProcessing. Begin sets six constants -
/// the two permission/member T-SQL templates, the scripting-options object, the command terminator,
/// the executing user, and the command name - plus the empty accumulator collection; process
/// accumulates a role object per role across records; end writes the collected scripts to files (or
/// passes them through). All of that state rides one sentinel Hashtable (_state) carried
/// begin-to-process-to-end: the ArrayList of role objects (each with an Object[] Sql property), the
/// scripting-options SMO object, and the scalar constants were all verified to survive the sentinel
/// round-trip intact. The process block's top validations are Stop-Function+return with no -Continue,
/// so a failure on one record silences later records and end; that interrupt rides the sentinel and
/// C# gates ProcessRecord and EndProcessing on it (the process body is dot-sourced so its returns do
/// not skip the sentinel).
///
/// Get-ExportFilePath is called in the END block to build the output path; it derives its token from
/// (Get-PSCallStack)[1].Command, so the call is routed through a named wrapper function
/// Export-DbaDbRole in the end hop (the RestartDbaService shim pattern). Path and BatchSeparator both
/// have config defaults reproduced when unbound; $PSBoundParameters.Path/.FilePath are bound-value
/// reads carried to the end hop; the one Test-Bound (ScriptingOptionsObject) rides a carried flag.
/// No ShouldProcess. Surface pinned by migration/baselines/Export-DbaDbRole.json.
/// </summary>
[Cmdlet(VerbsData.Export, "DbaDbRole")]
public sealed class ExportDbaDbRoleCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Server, database, or database-role object(s) to script.</summary>
    [Parameter(ValueFromPipeline = true, Position = 2)]
    public object[]? InputObject { get; set; }

    /// <summary>A scripting-options object controlling the generated T-SQL.</summary>
    [Parameter(Position = 3)]
    public Microsoft.SqlServer.Management.Smo.ScriptingOptions? ScriptingOptionsObject { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 4)]
    public object[]? Database { get; set; }

    /// <summary>The role(s) to export.</summary>
    [Parameter(Position = 5)]
    public object[]? Role { get; set; }

    /// <summary>The role(s) to exclude.</summary>
    [Parameter(Position = 6)]
    public object[]? ExcludeRole { get; set; }

    /// <summary>Exclude fixed database roles.</summary>
    [Parameter]
    public SwitchParameter ExcludeFixedRole { get; set; }

    /// <summary>Include role membership statements.</summary>
    [Parameter]
    public SwitchParameter IncludeRoleMember { get; set; }

    /// <summary>The output directory; defaults to the DbatoolsExport config path.</summary>
    [Parameter(Position = 7)]
    [PsStringCast]
    public string? Path { get; set; }

    /// <summary>The output file path.</summary>
    [Parameter(Position = 8)]
    [Alias("OutFile", "FileName")]
    [PsStringCast]
    public string? FilePath { get; set; }

    /// <summary>Emit the T-SQL to the pipeline instead of writing files.</summary>
    [Parameter]
    public SwitchParameter Passthru { get; set; }

    /// <summary>The batch separator between statements; defaults to the config value.</summary>
    [Parameter(Position = 9)]
    [PsStringCast]
    public string? BatchSeparator { get; set; }

    /// <summary>Do not overwrite an existing file.</summary>
    [Parameter]
    public SwitchParameter NoClobber { get; set; }

    /// <summary>Append to an existing file.</summary>
    [Parameter]
    public SwitchParameter Append { get; set; }

    /// <summary>Omit the header prefix.</summary>
    [Parameter]
    public SwitchParameter NoPrefix { get; set; }

    /// <summary>The output file encoding.</summary>
    [Parameter(Position = 10)]
    [ValidateSet("ASCII", "BigEndianUnicode", "Byte", "String", "Unicode", "UTF7", "UTF8", "Unknown")]
    [PsStringCast]
    public string Encoding { get; set; } = "UTF8";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The begin-set constants + the accumulator role collection, carried begin->process->end. And
    // whether a process top-validation Stop-Function+return set the interrupt, which silences later
    // records and end.
    private Hashtable? _state;
    private bool _processInterrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__exportDbaDbRoleBegin"))
            {
                _state = sentinel["__exportDbaDbRoleBegin"] as Hashtable;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BeginScript,
            Path, TestBound(nameof(Path)), TestBound(nameof(ScriptingOptionsObject)), ScriptingOptionsObject,
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _processInterrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__exportDbaDbRoleProcess"))
            {
                if (sentinel["__exportDbaDbRoleProcess"] is Hashtable state)
                {
                    _state = state["State"] as Hashtable ?? _state;
                    _processInterrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                }
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
            SqlInstance, SqlCredential, InputObject, Database, Role, ExcludeRole,
            ExcludeFixedRole.ToBool(), IncludeRoleMember.ToBool(), EnableException.ToBool(), _state,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void EndProcessing()
    {
        if (Interrupted || _processInterrupted)
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
            Passthru.ToBool(), Path, TestBound(nameof(Path)), FilePath, BatchSeparator, TestBound(nameof(BatchSeparator)),
            NoPrefix.ToBool(), Encoding, NoClobber.ToBool(), Append.ToBool(), _state,
            TestBound(nameof(Path)) ? (object?)Path : null, TestBound(nameof(FilePath)) ? (object?)FilePath : null,
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM (Test-Bound ScriptingOptionsObject -> carried flag; the config
    // default Path is reproduced when unbound). The sentinel emits the six constants and the empty
    // accumulator ArrayList for the process/end hops to carry.
    private const string BeginScript = """
param($Path, $__boundPath, $__boundScriptingOptionsObject, $ScriptingOptionsObject, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$Path, $__boundPath, $__boundScriptingOptionsObject, [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOptionsObject, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not $__boundPath) {
        $Path = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'
    }

        $null = Test-ExportDirectory -Path $Path
        $outsql = @()
        $outputFileArray = @()
        $roleCollection = New-Object System.Collections.ArrayList
        if ($IsLinux -or $IsMacOs) {
            $executingUser = $env:USER
        } else {
            $executingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        }
        $commandName = "Export-DbaDbRole"

        $roleSQL = "SELECT
                        N'/*RoleName*/' AS RoleName,
                        CASE dp.state
                            WHEN 'D' THEN 'DENY'
                            WHEN 'G' THEN 'GRANT'
                            WHEN 'R' THEN 'REVOKE'
                            WHEN 'W' THEN 'GRANT'
                        END AS GrantState,
                        dp.permission_name AS Permission,
                        CASE dp.class
                            WHEN 0 THEN ''
                            WHEN 1 THEN --table or column subset on the table
                                CASE WHEN dp.major_id < 0 THEN COALESCE('[sys].[' + OBJECT_NAME(dp.major_id) + ']', '')
                                    ELSE '[' + (SELECT SCHEMA_NAME(schema_id) + '].[' + name FROM sys.objects WHERE object_id = dp.major_id) + ']'
                                END + -- optionally concatenate column names
                                    CASE WHEN MAX(dp.minor_id) > 0 THEN ' (['
                                        + REPLACE((SELECT name + '], [' FROM sys.columns
                                                WHERE object_id = dp.major_id
                                                AND column_id IN (SELECT minor_id FROM sys.database_permissions WHERE major_id = dp.major_id AND USER_NAME(grantee_principal_id) = N'/*RoleName*/')
                                        FOR XML PATH('')) + '])', ', []', '')
                                        ELSE ''
                                    END
                            WHEN 3 THEN 'SCHEMA::[' + SCHEMA_NAME(dp.major_id) + ']'
                            WHEN 4 THEN '' + (SELECT RIGHT(type_desc, 4) + '::[' + name FROM sys.database_principals WHERE principal_id = dp.major_id) + ']'
                            WHEN 5 THEN 'ASSEMBLY::[' + (SELECT name FROM sys.assemblies WHERE assembly_id = dp.major_id) + ']'
                            WHEN 6 THEN 'TYPE::[' + (SELECT name FROM sys.types WHERE user_type_id = dp.major_id) + ']'
                            WHEN 10 THEN 'XML SCHEMA COLLECTION::[' + (SELECT SCHEMA_NAME(schema_id) + '.' + name FROM sys.xml_schema_collections WHERE xml_collection_id = dp.major_id) + ']'
                            WHEN 15 THEN 'MESSAGE TYPE::[' + (SELECT name FROM sys.service_message_types WHERE message_type_id = dp.major_id) + ']'
                            WHEN 16 THEN 'CONTRACT::[' + (SELECT name FROM sys.service_contracts WHERE service_contract_id = dp.major_id) + ']'
                            WHEN 17 THEN 'SERVICE::[' + (SELECT name FROM sys.services WHERE service_id = dp.major_id) + ']'
                            WHEN 18 THEN 'REMOTE SERVICE BINDING::[' + (SELECT name FROM sys.remote_service_bindings WHERE remote_service_binding_id = dp.major_id) + ']'
                            WHEN 19 THEN 'ROUTE::[' + (SELECT name FROM sys.routes WHERE route_id = dp.major_id) + ']'
                            WHEN 23 THEN 'FULLTEXT CATALOG::[' + (SELECT name FROM sys.fulltext_catalogs WHERE fulltext_catalog_id = dp.major_id) + ']'
                            WHEN 24 THEN 'SYMMETRIC KEY::[' + (SELECT name FROM sys.symmetric_keys WHERE symmetric_key_id = dp.major_id) + ']'
                            WHEN 25 THEN 'CERTIFICATE::[' + (SELECT name FROM sys.certificates WHERE certificate_id = dp.major_id) + ']'
                            WHEN 26 THEN 'ASYMMETRIC KEY::[' + (SELECT name FROM sys.asymmetric_keys WHERE asymmetric_key_id = dp.major_id) + ']'
                        END COLLATE DATABASE_DEFAULT AS Type,
                        CASE dp.state WHEN 'W' THEN ' WITH GRANT OPTION' ELSE '' END AS GrantType
                    FROM sys.database_permissions dp
                    WHERE USER_NAME(dp.grantee_principal_id) = N'/*RoleName*/'
                    GROUP BY dp.state, dp.major_id, dp.permission_name, dp.class
                    UNION ALL
                    SELECT
                        N'/*RoleName*/' AS RoleName,
                        'ALTER' AS GrantState,
                        'AUTHORIZATION' AS permission_name,
                        'SCHEMA::['+s.[name]+']' AS Type,
                        '' AS GrantType
                    FROM sys.schemas s
                    JOIN sys.sysusers u ON s.principal_id = u.[uid]
                    WHERE u.[name] = N'/*RoleName*/'"

        $userSQL = "SELECT roles.name AS RoleName, users.name AS Member
                    FROM sys.database_principals users
                    INNER JOIN sys.database_role_members link
                        ON link.member_principal_id = users.principal_id
                    INNER JOIN sys.database_principals roles
                        ON roles.principal_id = link.role_principal_id
                    WHERE roles.name = N'/*RoleName*/'
                    AND users.name != N'dbo'"

        if (-not $__boundScriptingOptionsObject) {
            $ScriptingOptionsObject = New-DbaScriptingOption
            $ScriptingOptionsObject.AllowSystemObjects = $false
            $ScriptingOptionsObject.IncludeDatabaseRoleMemberships = $true
            $ScriptingOptionsObject.ContinueScriptingOnError = $false
            $ScriptingOptionsObject.IncludeDatabaseContext = $true
            $ScriptingOptionsObject.IncludeIfNotExists = $false
        }

        if ($ScriptingOptionsObject.NoCommandTerminator) {
            $commandTerminator = ''
        } else {
            $commandTerminator = ';'
        }
        $outsql = @()

    @{ __exportDbaDbRoleBegin = @{ RoleSQL = $roleSQL; UserSQL = $userSQL; ScriptingOptionsObject = $ScriptingOptionsObject; CommandTerminator = $commandTerminator; ExecutingUser = $executingUser; CommandName = $commandName; RoleCollection = $roleCollection; OutputFileArray = $outputFileArray } }
} $Path $__boundPath $__boundScriptingOptionsObject $ScriptingOptionsObject $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM, dot-sourced so its early returns do not skip the sentinel.
    // Edits: -FunctionName on direct Stop-Function/Write-Message. The six constants and the
    // accumulator are restored from the carried state; the body's $roleCollection.Add mutates the
    // carried ArrayList, and the sentinel re-emits the (grown) state plus the interrupt flag.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $InputObject, $Database, $Role, $ExcludeRole, $ExcludeFixedRole, $IncludeRoleMember, $EnableException, $__state, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$InputObject, [object[]]$Database, [object[]]$Role, [object[]]$ExcludeRole, $ExcludeFixedRole, $IncludeRoleMember, $EnableException, $__state, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $roleSQL = $__state.RoleSQL
    $userSQL = $__state.UserSQL
    $ScriptingOptionsObject = $__state.ScriptingOptionsObject
    $commandTerminator = $__state.CommandTerminator
    $roleCollection = $__state.RoleCollection

    . {
        if (Test-FunctionInterrupt) {
            return
        }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a role, database, or server or specify a SqlInstance" -FunctionName Export-DbaDbRole
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            switch ($inputType) {
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject" -FunctionName Export-DbaDbRole -ModuleName "dbatools"
                    $databaseRoles = Get-DbaDbRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$ExcludeFixedRole
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject" -FunctionName Export-DbaDbRole -ModuleName "dbatools"
                    $databaseRoles = Get-DbaDbRole -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$ExcludeFixedRole
                }
                'Microsoft.SqlServer.Management.Smo.Database' {
                    Write-Message -Level Verbose -Message "Processing Database through InputObject" -FunctionName Export-DbaDbRole -ModuleName "dbatools"
                    $databaseRoles = $input | Get-DbaDbRole -ExcludeDatabase $ExcludeDatabase -Role $Role -ExcludeRole $ExcludeRole -ExcludeFixedRole:$ExcludeFixedRole
                }
                'Microsoft.SqlServer.Management.Smo.DatabaseRole' {
                    Write-Message -Level Verbose -Message "Processing DatabaseRole through InputObject" -FunctionName Export-DbaDbRole -ModuleName "dbatools"
                    $databaseRoles = $input
                }
                default {
                    Stop-Function -Message "InputObject is not a server, database, or login." -FunctionName Export-DbaDbRole
                    return
                }
            }
            foreach ($dbRole in $databaseRoles) {
                try {
                    $server = $dbRole.Parent.Parent
                    $db = $dbRole.Parent
                    if ($server.VersionMajor -lt 9) {
                        Stop-Function -Message "SQL Server version 9 or higher required - $server not supported." -Continue -FunctionName Export-DbaDbRole
                    }
                    $dbCompatibilityLevel = [int]($db.CompatibilityLevel.ToString().Replace('Version', ''))
                    if ($dbCompatibilityLevel -lt 90) {
                        Stop-Function -Message "$db has a compatibility level lower than Version90 and will be skipped." -Target $db -Continue -FunctionName Export-DbaDbRole
                    }

                    $outsql += $dbRole.Script($ScriptingOptionsObject)

                    $query = $roleSQL.Replace('/*RoleName*/', "$($dbRole.Name)")
                    $rolePermissions = $($dbRole.Parent).Query($query)

                    foreach ($rolePermission in $rolePermissions) {
                        $script = $rolePermission.GrantState + " " + $rolePermission.Permission
                        if ($rolePermission.Type) {
                            $script += " ON " + $rolePermission.Type
                        }
                        if ($rolePermission.RoleName) {
                            $script += " TO [" + $rolePermission.RoleName + "]"
                        }
                        if ($rolePermission.GrantType) {
                            $script += " WITH GRANT OPTION" + $commandTerminator
                        } else {
                            $script += $commandTerminator
                        }
                        $outsql += "$script"
                    }

                    if ($IncludeRoleMember) {
                        $query = $userSQL.Replace('/*RoleName*/', "$($dbRole.Name)")
                        $roleUsers = $($dbRole.Parent).Query($query)

                        foreach ($roleUser in $roleUsers) {
                            if ($server.VersionMajor -lt 11) {
                                $script = "EXEC sys.sp_addrolemember @rolename=N'$($roleUser.RoleName)', @membername=N'$($roleUser.Member)'"
                            } else {
                                $script = 'ALTER ROLE [' + $roleUser.RoleName + "] ADD MEMBER [" + $roleUser.Member + "]" + $commandTerminator
                            }
                            $outsql += "$script"
                        }
                    }
                    $roleObject = [PSCustomObject]@{
                        Name     = $dbRole.Name
                        Instance = $dbRole.SqlInstance
                        Database = $dbRole.Database
                        Sql      = $outsql
                    }
                    $roleCollection.Add($roleObject) | Out-Null
                    $outsql = @()
                } catch {
                    $outsql = @()
                    Stop-Function -Message "Error occurred processing role $dbRole" -Category ConnectionError -ErrorRecord $_ -Target $server -Continue -FunctionName Export-DbaDbRole
                }
            }
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __exportDbaDbRoleProcess = @{ State = $__state; Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SqlInstance $SqlCredential $InputObject $Database $Role $ExcludeRole $ExcludeFixedRole $IncludeRoleMember $EnableException $__state $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the end block VERBATIM. Edits: Get-ExportFilePath routed through the named wrapper
    // Export-DbaDbRole; $PSBoundParameters.Path/.FilePath -> carried bound values; -FunctionName on
    // direct Stop-Function/Write-Message. The accumulator and the executingUser/commandName/
    // outputFileArray constants are restored from the carried state; the Path and BatchSeparator
    // config defaults are reproduced when unbound (Path drives the file-vs-pipeline branch, which the
    // source's param-level default makes always-file).
    private const string EndScript = """
param($Passthru, $Path, $__boundPath, $FilePath, $BatchSeparator, $__boundBatchSeparator, $NoPrefix, $Encoding, $NoClobber, $Append, $__state, $__boundPathValue, $__boundFilePathValue, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($Passthru, [string]$Path, $__boundPath, [string]$FilePath, [string]$BatchSeparator, $__boundBatchSeparator, $NoPrefix, [string]$Encoding, $NoClobber, $Append, $__state, $__boundPathValue, $__boundFilePathValue, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not $__boundPath) {
        $Path = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'
    }

    if (-not $__boundBatchSeparator) {
        $BatchSeparator = Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator'
    }

    $executingUser = $__state.ExecutingUser
    $commandName = $__state.CommandName
    $roleCollection = $__state.RoleCollection
    $outputFileArray = $__state.OutputFileArray

    # ATTRIBUTION SHIM (the Get-PSCallStack class): Get-ExportFilePath derives its export-file token
    # from (Get-PSCallStack)[1].Command; this named wrapper puts "Export-DbaDbRole" in frame 1.
    function Export-DbaDbRole {
        param($Path, $FilePath, $Type, $ServerName)
        Get-ExportFilePath -Path $Path -FilePath $FilePath -Type $Type -ServerName $ServerName
    }

        if (Test-FunctionInterrupt) { return }

        $eol = [System.Environment]::NewLine

        $timeNow = $(Get-Date -Format (Get-DbatoolsConfigValue -FullName 'Formatting.DateTime'))
        foreach ($dbRole in $roleCollection) {
            $instanceName = $dbRole.Instance
            $databaseName = $dbRole.Database

            $outputFileName = $instanceName.Replace('\', '$') + '-' + $databaseName.Replace('\', '$')

            if ($NoPrefix) {
                $prefix = $null
            } else {
                $prefix = "/*$eol`tCreated by $executingUser using dbatools $commandName for objects on $instanceName.$databaseName at $timeNow$eol`tSee https://dbatools.io/$commandName for more information$eol*/"
            }

            if ($BatchSeparator) {
                $sql = $dbRole.SQL -join "$eol$BatchSeparator$eol"
                #add the final GO
                $sql += "$eol$BatchSeparator"
            } else {
                $sql = $dbRole.SQL
            }

            if ($Passthru) {
                if ($null -ne $prefix) {
                    $sql = "$prefix$eol$sql"
                }
                $sql
            } elseif ($Path -Or $FilePath) {
                if ($outputFileArray -notcontains $outputFileName) {
                    $scriptPath = Export-DbaDbRole -Path $__boundPathValue -FilePath $__boundFilePathValue -Type sql -ServerName $outputFileName
                    Write-Message -Level Verbose -Message "New File $scriptPath" -FunctionName Export-DbaDbRole -ModuleName "dbatools"
                    if ($null -ne $prefix) {
                        $sql = "$prefix$eol$sql"
                    }
                    $sql | Out-File -Encoding $Encoding -LiteralPath $scriptPath -Append:$Append -NoClobber:$NoClobber
                    $outputFileArray += $outputFileName
                    Get-ChildItem $scriptPath
                } else {
                    Write-Message -Level Verbose -Message "Adding to $scriptPath" -FunctionName Export-DbaDbRole -ModuleName "dbatools"
                    $sql | Out-File -Encoding $Encoding -LiteralPath $scriptPath -Append
                }
            } else {
                $sql
            }
        }

} $Passthru $Path $__boundPath $FilePath $BatchSeparator $__boundBatchSeparator $NoPrefix $Encoding $NoClobber $Append $__state $__boundPathValue $__boundFilePathValue $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
