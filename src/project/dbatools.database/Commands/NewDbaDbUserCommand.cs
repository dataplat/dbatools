#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using System.Security;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a database user. Port of public/New-DbaDbUser.ps1; the workflow remains a module-scoped
/// PowerShell compatibility hop.
///
/// THIS IS THE CANONICAL dbatools TEMPLATE COMMAND - its source comments are instructional ("All
/// commands that change objects must use SupportsShouldProcess", "Changing parameter values is only
/// allowed in the begin block, so that every execution of the process block ... has the same set of
/// parameter values"). Later ports get pattern-matched against whatever shape this one takes, which
/// is why the classes below are handled explicitly rather than incidentally.
///
/// FOUR NAMED PARAMETER SETS AND NO DEFAULT: ContainedAADUser, ContainedSQLUser, Login, NoLogin. The
/// baseline records no DefaultParameterSetName, so the binder resolves the set purely from which
/// parameters are supplied and the port must not invent one. Per-set facts were read with the
/// CORRECTED per-set baseline reader - the __AllParameterSets lookup that silently returns empty on
/// a named-set command is what shipped a breaking surface one row earlier on W2-152:
///   SqlInstance      Mandatory in ALL FOUR sets, and the ONLY positional parameter, at POSITION 1
///                    (not 0 - every other row in this satellite starts at 0, so this is exactly the
///                    value pattern-matching would have got wrong).
///   User             Mandatory in ContainedAADUser / ContainedSQLUser / NoLogin, NOT in Login.
///   Login            Mandatory, exists ONLY in the Login set.
///   SecurePassword   Mandatory, exists ONLY in ContainedSQLUser.
///   ExternalProvider Mandatory, exists ONLY in ContainedAADUser.
/// Everything else is in all four sets, non-mandatory and unpositioned.
///
/// $PSCmdlet.ParameterSetName CANNOT RIDE A HOP (new class, found on this row). Source :189 does
/// "Write-Message ... "Using parameter set $($PSCmdlet.ParameterSetName)."". Inside a hop $PSCmdlet
/// is the HOP SCRIPTBLOCK's own cmdlet, so that reports the hop's set rather than the set the CALLER
/// bound - on a four-set command with no default, a materially wrong value. Same family as the
/// $PSBoundParameters projection (W2-151): the automatic variable resolves happily and returns a
/// confident wrong answer. The real cmdlet's ParameterSetName is therefore passed in and the hop uses
/// the carried value. On this row the only consumer is a Verbose message, so the blast radius here is
/// cosmetic - but the class is not, and three other commands in public/ read the same member.
///
/// TWO begin -> process CARRIES, and the source says outright that they are deliberate. Begin is the
/// only place parameter values may change, so that every process execution sees the same set:
///   $User     - defaulted from $Login at :196-198 when the caller supplied a login but no user name.
///   $userType - the SMO UserType enum derived at :200-209 from ExternalProvider / SecurePassword /
///               Login. Process consumes it when creating the user.
/// Both die with begin's hop scope, so both ride the begin sentinel.
///
/// NO INTERRUPT BRIDGE: this source contains no Test-FunctionInterrupt, so its guards re-evaluate.
/// NO CROSS-RECORD CARRY AND NO RECORD AXIS AT ALL: no parameter is ValueFromPipeline, so process
/// fires exactly ONCE per invocation - stated rather than skipped, and both carry detectors
/// (Find-AccumulatorCarry, Find-ConditionalCarry) return zero candidates.
/// NO Test-Bound SITES, so no caller-boundness flags. No .IsPresent, no $PSBoundParameters
/// iteration, no preference-variable assignment.
///
/// ONLY THE PARAMETERS EACH BLOCK ACTUALLY READS CROSS ITS HOP, verified by AST rather than by
/// reading: begin uses User, Login, SecurePassword, ExternalProvider; process uses SqlInstance,
/// SqlCredential, Database, ExcludeDatabase, IncludeSystem, User, Login, SecurePassword,
/// DefaultSchema, Force. EnableException rides both because Stop-Function's -EnableException default
/// reads it from the CALLER's scope, which the AST does not show.
///
/// The two $Pscmdlet.ShouldProcess gates (:253 dropping an existing user under -Force, :265 creating)
/// route to the real cmdlet via $__realCmdlet - which matters at ConfirmImpact Medium, where the
/// prompt is reachable at the default $ConfirmPreference. The SIX in-loop Stop-Function calls all
/// carry -Continue. In-hop Stop-Function/Write-Message calls carry -FunctionName. The two switches
/// (IncludeSystem, Force) and the inherited EnableException cross as SwitchParameter OBJECTS received
/// untyped, per B's combined rule. Surface pinned by migration/baselines/New-DbaDbUser.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaDbUser", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class NewDbaDbUserCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 1, ParameterSetName = "Login")]
    [Parameter(Mandatory = true, Position = 1, ParameterSetName = "NoLogin")]
    [Parameter(Mandatory = true, Position = 1, ParameterSetName = "ContainedSQLUser")]
    [Parameter(Mandatory = true, Position = 1, ParameterSetName = "ContainedAADUser")]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(ParameterSetName = "Login")]
    [Parameter(ParameterSetName = "NoLogin")]
    [Parameter(ParameterSetName = "ContainedSQLUser")]
    [Parameter(ParameterSetName = "ContainedAADUser")]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) the user is created in.</summary>
    [Parameter(ParameterSetName = "Login")]
    [Parameter(ParameterSetName = "NoLogin")]
    [Parameter(ParameterSetName = "ContainedSQLUser")]
    [Parameter(ParameterSetName = "ContainedAADUser")]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Databases to exclude.</summary>
    [Parameter(ParameterSetName = "Login")]
    [Parameter(ParameterSetName = "NoLogin")]
    [Parameter(ParameterSetName = "ContainedSQLUser")]
    [Parameter(ParameterSetName = "ContainedAADUser")]
    [PsStringArrayCast]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Include system databases.</summary>
    [Parameter(ParameterSetName = "Login")]
    [Parameter(ParameterSetName = "NoLogin")]
    [Parameter(ParameterSetName = "ContainedSQLUser")]
    [Parameter(ParameterSetName = "ContainedAADUser")]
    public SwitchParameter IncludeSystem { get; set; }

    /// <summary>The user name; defaults to the login name when only -Login is supplied.</summary>
    [Parameter(ParameterSetName = "Login")]
    [Parameter(Mandatory = true, ParameterSetName = "NoLogin")]
    [Parameter(Mandatory = true, ParameterSetName = "ContainedSQLUser")]
    [Parameter(Mandatory = true, ParameterSetName = "ContainedAADUser")]
    [Alias("Username")]
    [PsStringCast]
    public string? User { get; set; }

    /// <summary>The login to map the user to.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Login")]
    [PsStringCast]
    public string? Login { get; set; }

    /// <summary>Password for a contained SQL user.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "ContainedSQLUser")]
    [Alias("Password")]
    public SecureString? SecurePassword { get; set; }

    /// <summary>Create a contained user from an external (Entra/AAD) provider.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "ContainedAADUser")]
    public SwitchParameter ExternalProvider { get; set; }

    /// <summary>The user's default schema.</summary>
    [Parameter(ParameterSetName = "Login")]
    [Parameter(ParameterSetName = "NoLogin")]
    [Parameter(ParameterSetName = "ContainedSQLUser")]
    [Parameter(ParameterSetName = "ContainedAADUser")]
    [PsStringCast]
    public string DefaultSchema { get; set; } = "dbo";

    /// <summary>Drop and recreate the user if it already exists.</summary>
    [Parameter(ParameterSetName = "Login")]
    [Parameter(ParameterSetName = "NoLogin")]
    [Parameter(ParameterSetName = "ContainedSQLUser")]
    [Parameter(ParameterSetName = "ContainedAADUser")]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // begin's $User default and $userType enum; opaque to C#.
    private Hashtable? _beginState;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            User, Login, SecurePassword, ExternalProvider, EnableException,
            // the CALLER's parameter set - $PSCmdlet inside the hop would report the hop's own
            ParameterSetName,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaDbUserBegin"))
            {
                _beginState = sentinel["__newDbaDbUserBegin"] as Hashtable;
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // Streaming, not buffered (DEF-001): users are created database by database and each result
        // is emitted, so a buffered hop would discard the record of users already created when a
        // later database's failure terminated the hop under -EnableException.
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
            SqlInstance, SqlCredential, Database, ExcludeDatabase, IncludeSystem, User, Login,
            SecurePassword, DefaultSchema, Force, EnableException, _beginState, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM. Edits: $PSCmdlet.ParameterSetName becomes the CARRIED
    // $__parameterSetName (inside a hop, $PSCmdlet is the hop's own cmdlet and would report the
    // hop's set rather than the caller's), plus -FunctionName stamps. The sentinel carries the two
    // values begin establishes for process: the $User defaulted from $Login, and the $userType enum.
    private const string BeginScript = """
param($User, $Login, $SecurePassword, $ExternalProvider, $EnableException, $__parameterSetName, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$User, [string]$Login, [securestring]$SecurePassword, $ExternalProvider, $EnableException, [string]$__parameterSetName, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        ### To help analyzing bugs in commands using parameter sets, we write the used parameter set to verbose output.
        Write-Message -Level Verbose -Message "Using parameter set $__parameterSetName." -FunctionName New-DbaDbUser -ModuleName "dbatools"

        ### To help analyzing bugs, we write at least one line to verbose output per code path. This can also be used as a kind of comment.
        ### Changing parameter values is only allowed in the begin block, so that every execution of the process block or the instance loop in the process block has the same set of parameter values.
        if ($Login -and -not $User) {
            Write-Message -Level Verbose -Message "No user name provided, so login name [$Login] will be used as user name." -FunctionName New-DbaDbUser -ModuleName "dbatools"
            $User = $Login
        }

        # Set appropriate user type based on provided parameters.
        # See https://learn.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.usertype for details.
        if ($ExternalProvider) {
            Write-Message -Level Verbose -Message "Using UserType [External]." -FunctionName New-DbaDbUser -ModuleName "dbatools"
            $userType = [Microsoft.SqlServer.Management.Smo.UserType]::External
        } elseif ($SecurePassword -or $Login) {
            Write-Message -Level Verbose -Message "Using UserType [SqlUser]." -FunctionName New-DbaDbUser -ModuleName "dbatools"
            $userType = [Microsoft.SqlServer.Management.Smo.UserType]::SqlUser
        } else {
            Write-Message -Level Verbose -Message "Using UserType [NoLogin]." -FunctionName New-DbaDbUser -ModuleName "dbatools"
            $userType = [Microsoft.SqlServer.Management.Smo.UserType]::NoLogin
        }
    }

    $__u  = Get-Variable -Name User -Scope 0 -ErrorAction Ignore
    $__ut = Get-Variable -Name userType -Scope 0 -ErrorAction Ignore
    @{ __newDbaDbUserBegin = @{
        User         = $(if ($__u)  { $__u.Value }  else { $null })
        UserTypeSet  = [bool]$__ut
        UserType     = $(if ($__ut) { $__ut.Value } else { $null })
    } }
} $User $Login $SecurePassword $ExternalProvider $EnableException $__parameterSetName $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM. Edits: the two $Pscmdlet gates route to $__realCmdlet, plus
    // -FunctionName stamps. Begin's two established values are restored first - the source states
    // outright that parameter values may only change in begin, so process must see what begin left.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $IncludeSystem, $User, $Login, $SecurePassword, $DefaultSchema, $Force, $EnableException, $__beginState, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, $IncludeSystem, [string]$User, [string]$Login, [securestring]$SecurePassword, [string]$DefaultSchema, $Force, $EnableException, $__beginState, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # begin is the only place parameter values may change (source comment at :192); restore what it left
    $User = $__beginState.User
    if ($__beginState.UserTypeSet) { $userType = $__beginState.UserType }

    . {
        ### Every process block starts with a loop through the parameter SqlInstance.
        ### Inside of the loop the current instance is named "instance".
        ### The first thing we do is to connect to the instance and save the returned server SMO in a variable called server.
        ### If this fails, we notify the user and continue with the next instance.
        ### The next six lines are (nearly) always the same for every command that connects to one or more instances.
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaDbUser
            }

            ### Run checks as early as possible.
            ### After connecting to the instance, run checks that need a connected instance.
            ### As the check might be successful on the next instance in the loop, use -Continue.
            ### In the messages, all strings should be surrounded by "[]", but all SMO variables will get "[]" automaticaly by their .ToString() method.
            if ($Login -and -not $server.Logins[$Login]) {
                Stop-Function -Message "Login [$Login] not found on instance $server" -Continue -FunctionName New-DbaDbUser
            }

            ### As we need the database object(s) to be able to add a new users to it, we have to filter the databases of the instance based on the provided parameters.
            ### We use Get-DbaDatabase here, because that command does all we need.
            ### We generally avoid to use other commands as they add more load and prefer to use the SMO directly. But in this case there is not much extra work.
            ### The following lines are always the same for all commands that work on a set of databases.
            $databases = Get-DbaDatabase -SqlInstance $server -Database $Database -ExcludeDatabase $ExcludeDatabase -ExcludeSystem:$(-not $IncludeSystem)
            ### Commands that need to change the database test for IsUpdateable, other commands test for IsAccessible.
            $databases = $databases | Where-Object IsUpdateable
            foreach ($db in $databases) {
                ### Where should be a verbose message at the start of each loop to help analyzing issues.
                Write-Message -Level Verbose -Message "Processing database $db on instance $server." -FunctionName New-DbaDbUser -ModuleName "dbatools"

                ### Run checks that need a database object. The same rules as for the instance checks apply.
                if (-not $db.Schemas[$DefaultSchema]) {
                    Stop-Function -Message "Schema [$DefaultSchema] does not exist in database $db on instance $server" -Continue -FunctionName New-DbaDbUser
                }

                ### As a last check, check for existance of the object that should be created.
                ### Depending on the usage of -Force, drop the object or continue with the next database.
                if ($db.Users[$User]) {
                    if ($Force) {
                        if ($__realCmdlet.ShouldProcess("User [$User] in database $db on instance $server", "Dropping user")) {
                            try {
                                $db.Users[$User].Drop()
                            } catch {
                                Stop-Function -Message "Dropping user [$User] in database $db on instance $server failed" -ErrorRecord $_ -Continue -FunctionName New-DbaDbUser
                            }
                        }
                    } else {
                        Stop-Function -Message "User [$User] already exists in database $db on instance $server and -Force was not specified" -Continue -FunctionName New-DbaDbUser
                    }
                }

                if ($__realCmdlet.ShouldProcess("User [$User] in database $db on instance $server", "Creating user")) {
                    try {
                        $newUser = New-Object Microsoft.SqlServer.Management.Smo.User
                        $newUser.Parent = $db
                        $newUser.Name = $User
                        if ($Login) {
                            $newUser.Login = $Login
                        }
                        $newUser.UserType = $userType
                        $newUser.DefaultSchema = $DefaultSchema
                        if ($SecurePassword) {
                            $newUser.Create($SecurePassword)
                        } else {
                            $newUser.Create()
                        }

                        ### Add the common dbatools properties to the new object
                        Add-Member -Force -InputObject $newUser -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                        Add-Member -Force -InputObject $newUser -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                        Add-Member -Force -InputObject $newUser -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                        Add-Member -Force -InputObject $newUser -MemberType NoteProperty -Name Database -value $db.Name

                        ### Output the new object
                        Select-DefaultView -InputObject $newUser -Property ComputerName, InstanceName, SqlInstance, Database, Name, LoginType, Login, AuthenticationType, DefaultSchema
                    } catch {
                        Stop-Function -Message "Creating user [$User] in database $db on instance $server failed" -ErrorRecord $_ -Continue -FunctionName New-DbaDbUser
                    }
                }
            }
        }
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $IncludeSystem $User $Login $SecurePassword $DefaultSchema $Force $EnableException $__beginState $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
