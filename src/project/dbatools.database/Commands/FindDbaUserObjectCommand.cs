#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Finds SQL Server objects (databases, agent proxies, credentials, endpoints, server/database roles,
/// schemas, assemblies, synonyms, etc.) owned by non-system users, optionally filtered by an owner
/// pattern. Port of public/Find-DbaUserObject.ps1; the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// A begin+process port (SqlInstance is ValueFromPipeline, so process fires per record); there is no end
/// block and no accumulator. The begin block conditionally mutates $Pattern ONCE: when $Pattern looks like
/// a single-backslash "domain\name" it doubles the backslash (Replace('\','\\')) for the downstream regex
/// and emits a one-time "Too few slashes" verbose message. That mutation must happen once (running the
/// Replace per record could over-escape, and the message would repeat), so it stays in begin and the
/// resulting $Pattern is carried one-way to the process hop via a sentinel (process reads $Pattern
/// read-only and never reassigns it). Body edits: -FunctionName Find-DbaUserObject on begin's one
/// Write-Message and process's Stop-Function and seven Write-Message. No ShouldProcess, no early return, no
/// interrupt (the one Stop-Function is -Continue). Surface pinned by
/// migration/baselines/Find-DbaUserObject.json (positions 0-2, no sets, no ShouldProcess).
/// </summary>
[Cmdlet(VerbsCommon.Find, "DbaUserObject")]
public sealed class FindDbaUserObjectCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The owner pattern (regex) to match against.</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    public string? Pattern { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The (possibly-mutated) $Pattern, carried one-way begin->process.
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__findDbaUserObjectBegin"))
            {
                _state = sentinel["__findDbaUserObjectBegin"] as Hashtable;
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
            Pattern, EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

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
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, EnableException.ToBool(), _state,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
    // PS: the begin block VERBATIM (the one-time $Pattern mutation) plus a sentinel carrying the
    // resulting $Pattern to the process hop. Edit: -FunctionName on the one Write-Message.
    private const string BeginScript = """
param($Pattern, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$Pattern, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if ($Pattern -match '^[\w\d\.-]+\\[\w\d\.-]+$') {
            Write-Message -Level Verbose -Message "Too few slashes, adding extra as required by regex" -FunctionName Find-DbaUserObject -ModuleName "dbatools"
            $Pattern = $Pattern.Replace('\', '\\')
        }

    @{ __findDbaUserObjectBegin = @{ Pattern = $Pattern } }
} $Pattern $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM. Edits: -FunctionName on the Stop-Function and seven Write-Message.
    // $Pattern is restored read-only from the carried state (process never reassigns it).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $EnableException, $__state, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, $EnableException, $__state, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $Pattern = $__state.Pattern

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Find-DbaUserObject
            }

            $saname = Get-SaLoginName $server

            ## Credentials
            if (-not $pattern) {
                Write-Message -Level Verbose -Message "Gathering data on instance objects" -FunctionName Find-DbaUserObject -ModuleName "dbatools"
                $creds = $server.Credentials
                $proxies = $server.JobServer.ProxyAccounts
                $endPoints = $server.Endpoints | Where-Object { $_.Owner -ne $saname }

                Write-Message -Level Verbose -Message "Gather data on Agent Jobs ownership" -FunctionName Find-DbaUserObject -ModuleName "dbatools"
                #Variable marked as unused by PSScriptAnalyzer
                #$jobs = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -ne $saname }
            } else {
                Write-Message -Level Verbose -Message "Gathering data on instance objects" -FunctionName Find-DbaUserObject -ModuleName "dbatools"
                $creds = $server.Credentials | Where-Object { $_.Identity -match $pattern }
                $proxies = $server.JobServer.ProxyAccounts | Where-Object { $_.CredentialIdentity -match $pattern }
                $endPoints = $server.Endpoints | Where-Object { $_.Owner -match $pattern }

                Write-Message -Level Verbose -Message "Gather data on Agent Jobs ownership" -FunctionName Find-DbaUserObject -ModuleName "dbatools"
                #Variable marked as unused by PSScriptAnalyzer
                #$jobs = $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -match $pattern }
            }

            ## dbs
            if (-not $pattern) {
                foreach ($db in $server.Databases | Where-Object { $_.Owner -ne $saname }) {
                    Write-Message -Level Verbose -Message "checking if $db is owned " -FunctionName Find-DbaUserObject -ModuleName "dbatools"

                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Database"
                        Owner        = $db.Owner
                        Name         = $db.Name
                        Parent       = $db.Parent.Name
                    }
                }
            } else {
                foreach ($db in $server.Databases | Where-Object { $_.Owner -match $pattern }) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Database"
                        Owner        = $db.Owner
                        Name         = $db.Name
                        Parent       = $db.Parent.Name
                    }
                }
            }

            ## agent jobs
            if (-not $pattern) {
                foreach ($job in $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -ne $saname }) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Agent Job"
                        Owner        = $job.OwnerLoginName
                        Name         = $job.Name
                        Parent       = $job.Parent.Name
                    }
                }
            } else {
                foreach ($job in $server.JobServer.Jobs | Where-Object { $_.OwnerLoginName -match $pattern }) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Agent Job"
                        Owner        = $job.OwnerLoginName
                        Name         = $job.Name
                        Parent       = $job.Parent.Name
                    }
                }
            }

            ## credentials
            foreach ($cred in $creds) {
                ## list credentials using the account

                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Type         = "Credential"
                    Owner        = $cred.Identity
                    Name         = $cred.Name
                    Parent       = $cred.Parent.Name
                }
            }

            ## proxies
            foreach ($proxy in $proxies) {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Type         = "Proxy"
                    Owner        = $proxy.CredentialIdentity
                    Name         = $proxy.Name
                    Parent       = $proxy.Parent.Name
                }

                ## list agent jobs steps using proxy
                foreach ($job in $server.JobServer.Jobs) {
                    foreach ($step in $job.JobSteps | Where-Object { $_.ProxyName -eq $proxy.Name }) {
                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Type         = "Agent Step"
                            Owner        = $step.ProxyName
                            Name         = $step.Name
                            Parent       = $step.Parent.Name #$step.Name
                        }
                    }
                }
            }


            ## endpoints
            foreach ($endPoint in $endPoints) {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Type         = "Endpoint"
                    Owner        = $endpoint.Owner
                    Name         = $endPoint.Name
                    Parent       = $endPoint.Parent.Name
                }
            }

            ## Server Roles
            if (-not $pattern) {
                foreach ($role in $server.Roles | Where-Object { $_.Owner -ne $saname }) {
                    Write-Message -Level Verbose -Message "checking if $db is owned " -FunctionName Find-DbaUserObject -ModuleName "dbatools"
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Server Role"
                        Owner        = $role.Owner
                        Name         = $role.Name
                        Parent       = $role.Parent.Name
                    }
                }
            } else {
                foreach ($role in $server.Roles | Where-Object { $_.Owner -match $pattern }) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Server Role"
                        Owner        = $role.Owner
                        Name         = $role.Name
                        Parent       = $role.Parent.Name
                    }
                }
            }

            ## Loop internal database
            foreach ($db in $server.Databases | Where-Object IsAccessible) {
                Write-Message -Level Verbose -Message "Gather user owned object in database: $db" -FunctionName Find-DbaUserObject -ModuleName "dbatools"
                ##schemas
                $sysSchemas = "DatabaseMailUserRole", "db_ssisadmin", "db_ssisltduser", "db_ssisoperator", "SQLAgentOperatorRole", "SQLAgentReaderRole", "SQLAgentUserRole", "TargetServersRole", "RSExecRole"

                if (-not $pattern) {
                    $schemas = $db.Schemas | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -ne "dbo" -and $sysSchemas -notcontains $_.Owner }
                } else {
                    $schemas = $db.Schemas | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -match $pattern -and $sysSchemas -notcontains $_.Owner }
                }
                foreach ($schema in $schemas) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Schema"
                        Owner        = $schema.Owner
                        Name         = $schema.Name
                        Parent       = $schema.Parent.Name
                    }
                }

                ## database roles
                if (-not $pattern) {
                    $roles = $db.Roles | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -ne "dbo" }
                } else {
                    $roles = $db.Roles | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -match $pattern }
                }
                foreach ($role in $roles) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Database Role"
                        Owner        = $role.Owner
                        Name         = $role.Name
                        Parent       = $role.Parent.Name
                    }
                }

                ## assembly
                if (-not $pattern) {
                    $assemblies = $db.Assemblies | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -ne "dbo" }
                } else {
                    $assemblies = $db.Assemblies | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -match $pattern }
                }

                foreach ($assembly in $assemblies) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Database Assembly"
                        Owner        = $assembly.Owner
                        Name         = $assembly.Name
                        Parent       = $assembly.Parent.Name
                    }
                }

                ## synonyms
                if (-not $pattern) {
                    $synonyms = $db.Synonyms | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -ne "dbo" }
                } else {
                    $synonyms = $db.Synonyms | Where-Object { $_.IsSystemObject -eq 0 -and $_.Owner -match $pattern }
                }

                foreach ($synonym in $synonyms) {
                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Type         = "Database Synonyms"
                        Owner        = $synonym.Owner
                        Name         = $synonym.Name
                        Parent       = $synonym.Parent.Name
                    }
                }
            }
        }
} $SqlInstance $SqlCredential $EnableException $__state $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
