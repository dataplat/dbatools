#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports Transact-SQL to recreate the database users, their permissions, and role memberships from one
/// or more SQL Server databases.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the database-user scripting,
/// the per-database and per-user file layout, the output shape, and dbatools stream and error handling stay
/// observable-identical to the script implementation.
/// </para>
/// <para>
/// The script keeps rich cross-record state in its single function scope: $instanceArray (which instances
/// have already opened their single output file, so a later record appends rather than clobbers),
/// $ScriptingOptionsObject (created once from the first record's server version and reused), and $Append
/// (set true when a user recurs and then retained). DEF-014: the source is begin/process with NO end
/// block, so this port STREAMS - BeginProcessing runs the begin block once and ProcessRecord runs the
/// process body for THAT record and emits immediately. The cross-record state that made buffering
/// attractive rides a state bag of 35 variables instead: restored at hop entry, captured in finally so an
/// early interrupt return cannot skip the handoff. Buffering to EndProcessing lost every record's work
/// outright when the upstream producer threw, because PowerShell never calls EndProcessing in that case.
/// </para>
/// <para>
/// An early Test-FunctionInterrupt return ends only the current record and later records still run,
/// matching the per-record process block. The begin block (including Test-ExportDirectory, which CREATES
/// the export directory) runs in BeginProcessing, which fires even for an empty pipeline, so the directory
/// side effect and the begin-set interrupt keep the script's begin/process ordering. The -Path config default (Path.DbatoolsExport)
/// is resolved in module scope as the script's parameter default does; Get-ExportFilePath still consumes
/// the bound $PSBoundParameters.Path/.FilePath, carried as $__boundPathValue/$__boundFilePathValue.
/// The process body runs inside a NAMED-WRAPPER SHIM (a function literally named Export-DbaUser, invoked
/// dot-sourced per record): Get-ExportFilePath derives the export filename from (Get-PSCallStack)[1].Command,
/// and an anonymous scriptblock frame produced invalid filenames carrying a scriptblock marker.
/// Switches are carried as plain (untyped) values, because a switch in the inner CmdletBinding scriptblock
/// is excluded from positional binding. Only the three DIRECT process Stop-Function/Write-Message calls take
/// -FunctionName; Test-ExportDirectory's own nested Stop-Function attributes to that helper in both worlds
/// and is left unedited. There is no ShouldProcess in the source.
/// </para>
/// </remarks>
[Cmdlet(VerbsData.Export, "DbaUser", DefaultParameterSetName = "Default")]
[OutputType(typeof(string))]
public sealed class ExportDbaUserCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>The database SMO objects to export users from, typically piped from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 1)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 2)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The databases to include.</summary>
    [Parameter(Position = 3)]
    public string[]? Database { get; set; }

    /// <summary>The databases to exclude.</summary>
    [Parameter(Position = 4)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>The specific users to export.</summary>
    [Parameter(Position = 5)]
    public string[]? User { get; set; }

    /// <summary>The destination SQL Server version to target the generated script at.</summary>
    [Parameter(Position = 6)]
    [PsStringCast]
    [ValidateSet("SQLServer2000", "SQLServer2005", "SQLServer2008/2008R2", "SQLServer2012", "SQLServer2014", "SQLServer2016", "SQLServer2017", "SQLServer2019", "SQLServer2022")]
    public string? DestinationVersion { get; set; }

    /// <summary>The directory to write per-user or per-instance files to.</summary>
    [Parameter(Position = 7)]
    public string? Path { get; set; }

    /// <summary>The single file to write the exported script to.</summary>
    [Parameter(Position = 8)]
    [Alias("OutFile", "FileName")]
    public string? FilePath { get; set; }

    /// <summary>The file encoding of the exported script.</summary>
    [Parameter(Position = 9)]
    [PsStringCast]
    [ValidateSet("ASCII", "BigEndianUnicode", "Byte", "String", "Unicode", "UTF7", "UTF8", "Unknown")]
    public string Encoding { get; set; } = "UTF8";

    /// <summary>Prevents overwriting an existing output file.</summary>
    [Parameter]
    [Alias("NoOverwrite")]
    public SwitchParameter NoClobber { get; set; }

    /// <summary>Appends to an existing output file instead of replacing it.</summary>
    [Parameter]
    public SwitchParameter Append { get; set; }

    /// <summary>Emits the generated script to the pipeline instead of writing a file.</summary>
    [Parameter]
    public SwitchParameter Passthru { get; set; }

    /// <summary>Generates a reusable template with parameterized names instead of concrete values.</summary>
    [Parameter]
    public SwitchParameter Template { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>A custom ScriptingOptions object to control T-SQL generation.</summary>
    [Parameter(Position = 10)]
    public Microsoft.SqlServer.Management.Smo.ScriptingOptions? ScriptingOptionsObject { get; set; }

    /// <summary>Omits the GO batch separator between statements.</summary>
    [Parameter]
    public SwitchParameter ExcludeGoBatchSeparator { get; set; }

    /// <summary>The begin block's state, then the process block's, carried across records.</summary>
    private Hashtable? _carryState;
    private bool _beginInterrupted;
    private bool _processInterrupted;
    private object? _inputObjectState;
    private bool _inputObjectByName;
    private bool _inputObjectEverPipelineBound;

    /// <summary>
    /// Parameters the BODY mutates and the script keeps across records: -Append flips true when a user
    /// recurs, -FilePath and -Path are computed, and the ScriptingOptions object is built once and reused.
    /// </summary>
    /// <remarks>
    /// These ride their OWN carries, never the state bag. The bag is restored inside the hop AFTER the
    /// engine has bound this record's parameters, so putting a parameter in it overwrites the freshly
    /// bound value - which is exactly how an explicit -Append got dropped and an existing file overwritten.
    /// The begin hop never receives most of these, so its capture of them is meaningless and is ignored.
    /// </remarks>
    private object? _appendState;
    private object? _filePathState;
    private object? _pathState;
    private object? _scriptingState;

    /// <summary>Runs the begin block once, before any record.</summary>
    protected override void BeginProcessing()
    {
        // InputObject is bimodal: bound BY NAME (a fixed value the body accumulates ON TOP of via +=
        // across records) or bound from the PIPELINE (databases piped, rebinds each record). ContainsKey
        // captured before pipeline binding distinguishes the fixed by-name value from per-record input.
        _inputObjectByName = MyInvocation.BoundParameters.ContainsKey("InputObject");
        _inputObjectState = InputObject;
        _appendState = Append.ToBool();
        _filePathState = FilePath;
        _pathState = Path;
        _scriptingState = ScriptingOptionsObject;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Path, DestinationVersion, ScriptingOptionsObject, EnableException.ToBool(),
            TestBound(nameof(Path)), TestBound(nameof(ScriptingOptionsObject)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && item.BaseObject is PSCustomObject && LanguagePrimitives.IsTrue(
                item.Properties["__ExportDbaUserBeginComplete"]?.Value))
            {
                _carryState = UnwrapHopValue(item.Properties["State"]?.Value) as Hashtable;
                // ONLY the two the begin hop actually receives; its view of the others is meaningless.
                _pathState = UnwrapHopValue(item.Properties["MutPath"]?.Value);
                _scriptingState = UnwrapHopValue(item.Properties["MutScripting"]?.Value);
                _beginInterrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }
    }

    /// <summary>
    /// Runs the process body for THIS record and emits immediately.
    /// </summary>
    /// <remarks>
    /// DEF-014: the source is begin/process with NO end block, so it streams. This port previously buffered
    /// every record and did the work in EndProcessing, which PowerShell never calls when the upstream
    /// producer terminates - so a throwing producer discarded everything the source would already have
    /// written. InputObject is ValueFromPipeline and the body MUTATES it ($InputObject += Get-DbaDatabase);
    /// when a record does not rebind it the script RETAINS and accumulates across records, so a genuine
    /// rebind (reference change) resets it and otherwise the carried accumulation stands.
    /// </remarks>
    protected override void ProcessRecord()
    {
        if (_beginInterrupted || _processInterrupted || Interrupted)
            return;

        // The complete bimodal model, matching PowerShell's ValueFromPipeline rebind rule (measured):
        //  - by-name InputObject: a fixed value the body accumulates on top of; never reset here.
        //  - pipeline-bound InputObject THIS record (non-null): a genuine new record (identical instance
        //    or not) - reset to it, and remember it has been pipeline-bound.
        //  - null InputObject AFTER it was ever pipeline-bound: the binder reset it because this record
        //    bound SqlInstance instead - reset to null too (source emits A,B not A,A,B for @(db; instance)).
        //  - null InputObject that was NEVER pipeline-bound: pure SqlInstance mode - keep the += accumulation.
        if (!_inputObjectByName)
        {
            if (InputObject != null)
            {
                _inputObjectState = InputObject;
                _inputObjectEverPipelineBound = true;
            }
            else if (_inputObjectEverPipelineBound)
            {
                _inputObjectState = null;
            }
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && item.BaseObject is PSCustomObject && LanguagePrimitives.IsTrue(
                item.Properties["__ExportDbaUserProcessComplete"]?.Value))
            {
                _carryState = UnwrapHopValue(item.Properties["State"]?.Value) as Hashtable;
                // The body accumulates \$InputObject with += when SqlInstance is piped (InputObject is
                // NOT the bound param that record), and the source keeps that across records. Capture it
                // so it feeds the next record; a genuine pipeline rebind still resets it in ProcessRecord.
                _inputObjectState = UnwrapHopValue(item.Properties["MutInputObject"]?.Value);
                _appendState = UnwrapHopValue(item.Properties["MutAppend"]?.Value);
                _filePathState = UnwrapHopValue(item.Properties["MutFilePath"]?.Value);
                _pathState = UnwrapHopValue(item.Properties["MutPath"]?.Value);
                _scriptingState = UnwrapHopValue(item.Properties["MutScripting"]?.Value);
                _processInterrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, _inputObjectState, SqlCredential, Database, ExcludeDatabase, User, DestinationVersion,
            _pathState, _filePathState, Encoding, NoClobber.ToBool(), _appendState, Passthru.ToBool(), Template.ToBool(),
            EnableException.ToBool(), _scriptingState, ExcludeGoBatchSeparator.ToBool(),
            TestBound(nameof(Path)), TestBound(nameof(FilePath)), TestBound(nameof(ScriptingOptionsObject)),
            BoundValue("Path"), BoundValue("FilePath"), _carryState,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    /// <summary>Unwraps a value the hop carried out through its sentinel.</summary>
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

    private object? BoundValue(string name)
    {
        return MyInvocation.BoundParameters.TryGetValue(name, out object? value) ? value : null;
    }

    // PS: the begin block VERBATIM (its -Path default resolved in module scope), then a per-batch replay of
    // the process body VERBATIM except the 7 reverse-diff-verified edits (-FunctionName on the 3 direct
    // Stop-Function/Write-Message calls; Test-Bound FilePath/ScriptingOptionsObject -> carried flags;
    // Get-ExportFilePath $PSBoundParameters.Path/.FilePath -> carried bound values). The process body is
    // dot-sourced so an early Test-FunctionInterrupt return skips only the current batch. $SqlInstance and
    // $InputObject are set from each batch; all other cross-record state persists across batches in this
    // one shared scope.
    private const string BeginScript = """
param($Path, $DestinationVersion, $ScriptingOptionsObject, $EnableException, $__pathBound, $__scriptingBound, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$Path, [string]$DestinationVersion, $ScriptingOptionsObject, $EnableException, $__pathBound, $__scriptingBound, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if (-not $__pathBound) { $Path = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport' }
        $null = Test-ExportDirectory -Path $Path

        $outsql = $script:pathcollection = $instanceArray = @()
        $GenerateFilePerUser = $false

        $versions = @{
            'SQLServer2000'        = 'Version80'
            'SQLServer2005'        = 'Version90'
            'SQLServer2008/2008R2' = 'Version100'
            'SQLServer2012'        = 'Version110'
            'SQLServer2014'        = 'Version120'
            'SQLServer2016'        = 'Version130'
            'SQLServer2017'        = 'Version140'
            'SQLServer2019'        = 'Version150'
            'SQLServer2022'        = 'Version160'
        }

        $versionName = @{
            'Version80'  = 'SQLServer2000'
            'Version90'  = 'SQLServer2005'
            'Version100' = 'SQLServer2008/2008R2'
            'Version110' = 'SQLServer2012'
            'Version120' = 'SQLServer2014'
            'Version130' = 'SQLServer2016'
            'Version140' = 'SQLServer2017'
            'Version150' = 'SQLServer2019'
            'Version160' = 'SQLServer2022'
        }

        # Maps SQL Server major version number to SMO scripting version string.
        # Used to resolve the actual server version when no DestinationVersion is specified,
        # since the database compatibility level may be lower than the server version.
        $serverVersionMap = @{
            8  = 'Version80'
            9  = 'Version90'
            10 = 'Version100'
            11 = 'Version110'
            12 = 'Version120'
            13 = 'Version130'
            14 = 'Version140'
            15 = 'Version150'
            16 = 'Version160'
        }

        $eol = [System.Environment]::NewLine
        $InputObject = $null
    }

    [pscustomobject]@{ __ExportDbaUserBeginComplete = $true; Interrupted = (Test-FunctionInterrupt); MutAppend = $Append; MutFilePath = $FilePath; MutPath = $Path; MutScripting = $ScriptingOptionsObject; State = @{ dbUserInstance = $dbUserInstance; eol = $eol; escapedLogin = $escapedLogin; escapedUsername = $escapedUsername; execute = $execute; GenerateFilePerUser = $GenerateFilePerUser; grantDatabasePermission = $grantDatabasePermission; grantee = $grantee; grantObjectPermission = $grantObjectPermission; instanceArray = $instanceArray; isUserMember = $isUserMember; object = $object; outsql = $outsql; ownedSchemas = $ownedSchemas; ownerName = $ownerName; permissionScript = $permissionScript; perms = $perms; progressMessage = $progressMessage; scriptVersion = $scriptVersion; serverMajorVersion = $serverMajorVersion; serverVersionMap = $serverVersionMap; sql = $sql; stepCounter = $stepCounter; useDatabase = $useDatabase; users = $users; usersProcessed = $usersProcessed; versionName = $versionName; versionNameDesc = $versionNameDesc; versions = $versions; withGrant = $withGrant } }
} $Path $DestinationVersion $ScriptingOptionsObject $EnableException $__pathBound $__scriptingBound $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process body VERBATIM inside the named-wrapper shim, now STREAMED per record (DEF-014).
    private const string ProcessScript = """
param($SqlInstance, $InputObject, $SqlCredential, $Database, $ExcludeDatabase, $User, $DestinationVersion, $Path, $FilePath, $Encoding, $NoClobber, $Append, $Passthru, $Template, $EnableException, $ScriptingOptionsObject, $ExcludeGoBatchSeparator, $__pathBound, $__filePathBound, $__scriptingBound, $__boundPathValue, $__boundFilePathValue, $__carryState, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, [string[]]$User, [string]$DestinationVersion, [string]$Path, [string]$FilePath, [string]$Encoding, $NoClobber, $Append, $Passthru, $Template, $EnableException, $ScriptingOptionsObject, $ExcludeGoBatchSeparator, $__pathBound, $__filePathBound, $__scriptingBound, $__boundPathValue, $__boundFilePathValue, $__carryState, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # DEF-014: this port STREAMS per record (source is begin/process). The shared scope the single
    # end-hop provided is reconstructed by restoring the carried state here and capturing it in finally.
    if ($__carryState) { foreach ($__k in $__carryState.Keys) { Set-Variable -Name $__k -Value $__carryState[$__k] } }
    try {
        # Named-wrapper shim: the process body runs inside a function carrying the command's name,
        # so call-stack-deriving helpers see Export-DbaUser exactly as in the function world -
        # Get-ExportFilePath builds export filenames from (Get-PSCallStack)[1].Command, and the
        # anonymous scriptblock frame put a literal scriptblock marker in every per-user filename.
        # The dot-sourced invocation keeps the body in the hop scope, so the cross-record
        # accumulation and the interrupt latch behave unchanged.
        function Export-DbaUser {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        # To keep the filenames generated and re-use (append) if needed
        $usersProcessed = @{ }

        foreach ($db in $InputObject) {

            if ([string]::IsNullOrEmpty($destinationVersion)) {
                # Use the actual server version rather than the database compatibility level.
                # The compatibility level may be lower than the server version (e.g., a SQL 2022
                # instance hosting a database at compat level 120/SQL2014). Scripting against
                # the lower compat level causes errors for features like External users that are
                # supported by the server but not recognised by older scripting targets.
                $serverMajorVersion = $db.Parent.VersionMajor
                if ($serverVersionMap.ContainsKey($serverMajorVersion)) {
                    $scriptVersion = $serverVersionMap[$serverMajorVersion]
                } else {
                    $scriptVersion = $db.CompatibilityLevel
                }
            } else {
                $scriptVersion = $versions[$destinationVersion]
            }
            $versionNameDesc = $versionName[$scriptVersion.ToString()]

            #If not passed create new ScriptingOption. Otherwise use the one that was passed
            if ($null -eq $ScriptingOptionsObject) {
                $ScriptingOptionsObject = New-DbaScriptingOption
                $ScriptingOptionsObject.TargetServerVersion = [Microsoft.SqlServer.Management.Smo.SqlServerVersion]::$scriptVersion
                $ScriptingOptionsObject.AllowSystemObjects = $false
                $ScriptingOptionsObject.IncludeDatabaseRoleMemberships = $true
                $ScriptingOptionsObject.ContinueScriptingOnError = $false
                $ScriptingOptionsObject.IncludeDatabaseContext = $false
                $ScriptingOptionsObject.IncludeIfNotExists = $true
            }

            Write-Message -Level Verbose -Message "Validating users on database $db" -FunctionName Export-DbaUser -ModuleName "dbatools"

            if ($User) {
                $users = $db.Users | Where-Object { $User -contains $_.Name -and $_.IsSystemObject -eq $false -and $_.Name -notlike "##*" }
            } else {
                $users = $db.Users
            }

            # Generate the file path
            if (-not $__filePathBound) {
                $GenerateFilePerUser = $true
            } else {
                # Generate a new file name with passed/default path
                $FilePath = Get-ExportFilePath -Path $__boundPathValue -FilePath $__boundFilePathValue -Type sql -ServerName $db.Parent.Name -Unique
            }

            $stepCounter = 0
            foreach ($dbuser in $users) {
                # Clear output for each user
                $outsql = @()
                $sql = ""

                if ($GenerateFilePerUser) {
                    if ($null -eq $usersProcessed[$dbuser.Name]) {
                        # If user and not specific output file, create file name without database name.
                        $FilePath = Get-ExportFilePath -Path $__boundPathValue -FilePath $__boundFilePathValue -Type sql -ServerName $("$($db.Parent.Name)-$($dbuser.Name)") -Unique
                        $usersProcessed[$dbuser.Name] = $FilePath
                    } else {
                        $Append = $true
                        $FilePath = $usersProcessed[$dbuser.Name]
                    }
                }

                if ($Passthru) {
                    $progressMessage = "Generating script for user $dbuser"
                } else {
                    $progressMessage = "Generating script ($FilePath) for user $dbuser"
                }
                Write-ProgressHelper -TotalSteps $users.Count -Activity "Exporting from $($db.Name)" -StepNumber ($stepCounter++) -Message $progressMessage

                #setting database
                if ((($__scriptingBound) -and $ScriptingOptionsObject.IncludeDatabaseContext) -or - (-not $__scriptingBound)) {
                    $useDatabase = "USE [" + $db.Name + "]"
                }

                try {
                    <#
                    In this approach, we do not maintain a variable to track the roles that have been scripted. Our method involves a
                    consistent verification process for each user against the complete list of roles. This ensures that we dynamically
                    include only the roles to which a user belongs. For example, consider two users: user1 is associated with role1 and
                    role2, while user2 is associated with role1 and role3.

                    Attempting to memorize the scripted roles could result in Transact-SQL (T-SQL) statements such as:

                    IF NOT EXISTS (role1)
                      CREATE ROLE role1
                    IF NOT EXISTS (role2)
                      CREATE ROLE role2
                    IF NOT EXISTS (user1)
                      CREATE USER user1
                    ADD user1 TO role1
                    ADD user1 TO role2

                    -- And for another user:

                    IF NOT EXISTS (role3)
                      CREATE ROLE role3
                    IF NOT EXISTS (user2)
                      CREATE USER user2
                    ADD user2 TO role1
                    ADD user2 TO role3

                    However, this script inadvertently introduces a dependency issue. To ensure user2 is properly configured, the script
                    segment for user1 must be executed first due to the shared role1. To circumvent this issue and remove interdependencies,
                    we opt to match each user against all potential roles. Consequently, roles are scripted per user membership, resulting
                    in T-SQL like:

                    IF NOT EXISTS (role1)
                      CREATE ROLE role1
                    IF NOT EXISTS (role2)
                      CREATE ROLE role2
                    IF NOT EXISTS (user1)
                      CREATE USER user1
                    ADD user1 TO role1
                    ADD user1 TO role2

                    -- And for another user:

                    IF NOT EXISTS (role1)
                      CREATE ROLE role1
                    IF NOT EXISTS (role3)
                      CREATE ROLE role3
                    IF NOT EXISTS (user2)
                      CREATE USER user2
                    ADD user2 TO role1
                    ADD user2 TO role3

                    While this method may produce some redundant code (e.g., checking and creating role1 twice), it guarantees that each
                    portion of the script is self-sufficient and can be executed independently of others. Therefore, users can selectively
                    execute any segment of the script without concern for execution order or dependencies.
                    #>
                    #Fixed Roles #Dependency Issue. Create Role, before add to role.
                    foreach ($role in ($db.Roles | Where-Object { $_.IsFixedRole -eq $false })) {
                        # Check if the user is a member of the role
                        $isUserMember = $role.EnumMembers() | Where-Object { $_ -eq $dbuser.Name }
                        if ($isUserMember) {
                            foreach ($rolePermissionScript in $role.Script($ScriptingOptionsObject)) {
                                $outsql += "$($rolePermissionScript.ToString())"
                            }
                        }
                    }

                    #Database Create User(s) and add to Role(s)
                    foreach ($dbUserPermissionScript in $dbuser.Script($ScriptingOptionsObject)) {
                        if ($dbuserPermissionScript.Contains("sp_addrolemember")) {
                            $execute = "EXEC "
                        } else {
                            $execute = ""
                        }
                        $permissionScript = $dbUserPermissionScript.ToString()
                        if ($Template) {
                            $escapedUsername = [regex]::Escape($dbuser.Name)
                            $permissionScript = $permissionScript -replace "\`[$escapedUsername\`]", '[{templateUser}]'
                            $permissionScript = $permissionScript -replace "'$escapedUsername'", "'{templateUser}'"
                            if ($dbuser.Login) {
                                $escapedLogin = [regex]::Escape($dbuser.Login)
                                $permissionScript = $permissionScript -replace "\`[$escapedLogin\`]", '[{templateLogin}]'
                                $permissionScript = $permissionScript -replace "'$escapedLogin'", "'{templateLogin}'"
                            }

                        }
                        $outsql += "$execute$($permissionScript)"
                    }

                    #Database Permissions
                    foreach ($databasePermission in $db.EnumDatabasePermissions() | Where-Object { @("sa", "dbo", "information_schema", "sys") -notcontains $_.Grantee -and $_.Grantee -notlike "##*" -and ($dbuser.Name -contains $_.Grantee) }) {
                        if ($databasePermission.PermissionState -eq "GrantWithGrant") {
                            $withGrant = " WITH GRANT OPTION"
                            $grantDatabasePermission = 'GRANT'
                        } else {
                            $withGrant = ""
                            $grantDatabasePermission = $databasePermission.PermissionState.ToString().ToUpper()
                        }
                        if ($Template) {
                            $grantee = "{templateUser}"
                        } else {
                            $grantee = $databasePermission.Grantee
                        }

                        $outsql += "$($grantDatabasePermission) $($databasePermission.PermissionType) TO [$grantee]$withGrant AS [$($databasePermission.Grantor)];"
                    }

                    #Database Object Permissions
                    # NB: This is a bit of a mess for a couple of reasons
                    # 1. $db.EnumObjectPermissions() doesn't enumerate all object types
                    # 2. Some (x)Collection types can have EnumObjectPermissions() called
                    #    on them directly (e.g. AssemblyCollection); others can't (e.g.
                    #    ApplicationRoleCollection). Those that can't we iterate the
                    #    collection explicitly and add each object's permission.

                    $perms = New-Object System.Collections.ArrayList

                    $null = $perms.AddRange($db.EnumObjectPermissions($dbuser.Name))

                    foreach ($item in $db.ApplicationRoles) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.Assemblies) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.Certificates) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.DatabaseRoles) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.FullTextCatalogs) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.FullTextStopLists) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.SearchPropertyLists) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.MessageTypes) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.RemoteServiceBindings) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.Routes) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.ServiceContracts) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.ServiceBroker.Services) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    if ($scriptVersion -ne "Version80") {
                        foreach ($item in $db.AsymmetricKeys) {
                            $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                        }
                    }

                    foreach ($item in $db.SymmetricKeys) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($item in $db.XmlSchemaCollections) {
                        $null = $perms.AddRange($item.EnumObjectPermissions($dbuser.Name))
                    }

                    foreach ($objectPermission in $perms | Where-Object { @("sa", "dbo", "information_schema", "sys") -notcontains $_.Grantee -and $_.Grantee -notlike "##*" -and $_.Grantee -eq $dbuser.Name }) {
                        switch ($objectPermission.ObjectClass) {
                            'ApplicationRole' {
                                $object = 'APPLICATION ROLE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'AsymmetricKey' {
                                $object = 'ASYMMETRIC KEY::[{0}]' -f $objectPermission.ObjectName
                            }
                            'Certificate' {
                                $object = 'CERTIFICATE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'DatabaseRole' {
                                $object = 'ROLE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'FullTextCatalog' {
                                $object = 'FULLTEXT CATALOG::[{0}]' -f $objectPermission.ObjectName
                            }
                            'FullTextStopList' {
                                $object = 'FULLTEXT STOPLIST::[{0}]' -f $objectPermission.ObjectName
                            }
                            'MessageType' {
                                $object = 'Message Type::[{0}]' -f $objectPermission.ObjectName
                            }
                            'ObjectOrColumn' {
                                if ($scriptVersion -ne "Version80") {
                                    $object = 'OBJECT::[{0}].[{1}]' -f $objectPermission.ObjectSchema, $objectPermission.ObjectName
                                    if ($null -ne $objectPermission.ColumnName) {
                                        $object += '([{0}])' -f $objectPermission.ColumnName
                                    }
                                }
                                #At SQL Server 2000 OBJECT did not exists
                                else {
                                    $object = '[{0}].[{1}]' -f $objectPermission.ObjectSchema, $objectPermission.ObjectName
                                }
                            }
                            'RemoteServiceBinding' {
                                $object = 'REMOTE SERVICE BINDING::[{0}]' -f $objectPermission.ObjectName
                            }
                            'Schema' {
                                $object = 'SCHEMA::[{0}]' -f $objectPermission.ObjectName
                            }
                            'SearchPropertyList' {
                                $object = 'SEARCH PROPERTY LIST::[{0}]' -f $objectPermission.ObjectName
                            }
                            'Service' {
                                $object = 'SERVICE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'ServiceContract' {
                                $object = 'CONTRACT::[{0}]' -f $objectPermission.ObjectName
                            }
                            'ServiceRoute' {
                                $object = 'ROUTE::[{0}]' -f $objectPermission.ObjectName
                            }
                            'SqlAssembly' {
                                $object = 'ASSEMBLY::[{0}]' -f $objectPermission.ObjectName
                            }
                            'SymmetricKey' {
                                $object = 'SYMMETRIC KEY::[{0}]' -f $objectPermission.ObjectName
                            }
                            'User' {
                                $object = 'USER::[{0}]' -f $objectPermission.ObjectName
                            }
                            'UserDefinedType' {
                                $object = 'TYPE::[{0}].[{1}]' -f $objectPermission.ObjectSchema, $objectPermission.ObjectName
                            }
                            'XmlNamespace' {
                                $object = 'XML SCHEMA COLLECTION::[{0}]' -f $objectPermission.ObjectName
                            }
                        }

                        if ($objectPermission.PermissionState -eq "GrantWithGrant") {
                            $withGrant = " WITH GRANT OPTION"
                            $grantObjectPermission = 'GRANT'
                        } else {
                            $withGrant = ""
                            $grantObjectPermission = $objectPermission.PermissionState.ToString().ToUpper()
                        }
                        if ($Template) {
                            $grantee = "{templateUser}"
                        } else {
                            $grantee = $objectPermission.Grantee
                        }

                        $outsql += "$grantObjectPermission $($objectPermission.PermissionType) ON $object TO [$grantee]$withGrant AS [$($objectPermission.Grantor)];"
                    }

                    #Schema Ownership
                    $ownedSchemas = @()
                    if ($db.Parent.VersionMajor -gt 8) {
                        $ownedSchemas = $db.Schemas | Where-Object { $_.Owner -eq $dbuser.Name -and @("sa", "dbo", "information_schema", "sys", "guest") -notcontains $_.Name }
                    }

                    if ($scriptVersion -eq "Version80" -and @($ownedSchemas).Count -gt 0) {
                        Stop-Function -Message "This user may be using functionality from $($versionName[$db.CompatibilityLevel.ToString()]) that does not exist on the destination version ($versionNameDesc)." -Continue -Target $db -FunctionName Export-DbaUser
                        $ownedSchemas = @()
                    }

                    foreach ($schema in $ownedSchemas) {
                        if ($Template) {
                            $ownerName = "{templateUser}"
                        } else {
                            $ownerName = $schema.Owner
                        }
                        $outsql += "ALTER AUTHORIZATION ON SCHEMA::[{0}] TO [{1}];" -f $schema.Name, $ownerName
                    }

                } catch {
                    Stop-Function -Message "This user may be using functionality from $($versionName[$db.CompatibilityLevel.ToString()]) that does not exist on the destination version ($versionNameDesc)." -Continue -InnerErrorRecord $_ -Target $db -FunctionName Export-DbaUser
                }

                if (@($outsql.Count) -gt 0) {
                    if ($ExcludeGoBatchSeparator) {
                        $sql = "$useDatabase $outsql"
                    } else {
                        if ($useDatabase) {
                            $sql = "$useDatabase$($eol)GO$eol" + ($outsql -join "$($eol)GO$eol")
                        } else {
                            $sql = $outsql -join "$($eol)GO$eol"
                        }
                        #add the final GO
                        $sql += "$($eol)GO"
                    }
                }

                if (-not $Passthru) {
                    # If generate a file per user, clean the collection to populate with next one
                    if ($GenerateFilePerUser) {
                        if (-not [string]::IsNullOrEmpty($sql)) {
                            $sql | Out-File -Encoding:$Encoding -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
                            Get-ChildItem -Path $FilePath
                        }
                    } else {
                        $dbUserInstance = $dbuser.Parent.Parent.Name

                        if ($instanceArray -notcontains $($dbUserInstance)) {
                            $sql | Out-File -Encoding:$Encoding -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
                            $instanceArray += $dbUserInstance
                        } else {
                            $sql | Out-File -Encoding:$Encoding -FilePath $FilePath -Append
                        }
                    }
                } else {
                    $sql
                }
            }
        }
        # Just a single file, output path once here
        if (-Not $GenerateFilePerUser -and $FilePath) {
            Get-ChildItem -Path $FilePath
        }
        }
        . Export-DbaUser
    } finally {
    [pscustomobject]@{ __ExportDbaUserProcessComplete = $true; Interrupted = (Test-FunctionInterrupt); MutInputObject = $InputObject; MutAppend = $Append; MutFilePath = $FilePath; MutPath = $Path; MutScripting = $ScriptingOptionsObject; State = @{ dbUserInstance = $dbUserInstance; eol = $eol; escapedLogin = $escapedLogin; escapedUsername = $escapedUsername; execute = $execute; GenerateFilePerUser = $GenerateFilePerUser; grantDatabasePermission = $grantDatabasePermission; grantee = $grantee; grantObjectPermission = $grantObjectPermission; instanceArray = $instanceArray; isUserMember = $isUserMember; object = $object; outsql = $outsql; ownedSchemas = $ownedSchemas; ownerName = $ownerName; permissionScript = $permissionScript; perms = $perms; progressMessage = $progressMessage; scriptVersion = $scriptVersion; serverMajorVersion = $serverMajorVersion; serverVersionMap = $serverVersionMap; sql = $sql; stepCounter = $stepCounter; useDatabase = $useDatabase; users = $users; usersProcessed = $usersProcessed; versionName = $versionName; versionNameDesc = $versionNameDesc; versions = $versions; withGrant = $withGrant } }
    }
} $SqlInstance $InputObject $SqlCredential $Database $ExcludeDatabase $User $DestinationVersion $Path $FilePath $Encoding $NoClobber $Append $Passthru $Template $EnableException $ScriptingOptionsObject $ExcludeGoBatchSeparator $__pathBound $__filePathBound $__scriptingBound $__boundPathValue $__boundFilePathValue $__carryState $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
