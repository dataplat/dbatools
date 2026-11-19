#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports the user-created objects in the system databases (master, model, msdb) as T-SQL scripts.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the connection, the
/// sysadmin check, the object enumeration, the generated T-SQL, the file output, and dbatools stream
/// and error handling stay observable-identical to the script implementation.
/// </para>
/// <para>
/// The command is process-only, so it ships as a single hop per record. It emits per system database
/// via Export-DbaScript and can raise a terminating -EnableException failure on a later system database
/// after an earlier one has already emitted, so output is streamed through InvokeScopedStreaming - each
/// object reaches the pipeline as produced, surviving a later throw; a buffered collection would be
/// discarded on that throw and lose the earlier output.
/// </para>
/// <para>
/// The Path config-value default is reproduced inside the hop, applied only when the caller did not bind
/// it; BatchSeparator ('GO') and IncludeDependencies (false) are plain defaults carried on the compiled
/// parameters. The Get-ExportFilePath call reads the caller's bound Path and FilePath, which a hop cannot
/// see, so those bound values are carried in explicitly, and the default ScriptingOptions is created only
/// when ScriptingOptionsObject was not bound. Every switch parameter is carried as a plain (untyped) bool,
/// because a switch in the inner CmdletBinding scriptblock is excluded from positional binding.
/// </para>
/// </remarks>
[Cmdlet(VerbsData.Export, "DbaSysDbUserObject")]
public sealed class ExportDbaSysDbUserObjectCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Includes dependent objects in the generated scripts.</summary>
    [Parameter]
    public SwitchParameter IncludeDependencies { get; set; }

    /// <summary>The batch separator placed between statements.</summary>
    [Parameter(Position = 2)]
    public string BatchSeparator { get; set; } = "GO";

    /// <summary>The directory the exported script is written to.</summary>
    [Parameter(Position = 3)]
    public string? Path { get; set; }

    /// <summary>An explicit output file path.</summary>
    [Parameter(Position = 4)]
    public string? FilePath { get; set; }

    /// <summary>Omits the descriptive comment prefix from the script.</summary>
    [Parameter]
    public SwitchParameter NoPrefix { get; set; }

    /// <summary>Scripting options applied when generating the object definitions.</summary>
    [Parameter(Position = 5)]
    public Microsoft.SqlServer.Management.Smo.ScriptingOptions? ScriptingOptionsObject { get; set; }

    /// <summary>Prevents overwriting an existing output file.</summary>
    [Parameter]
    public SwitchParameter NoClobber { get; set; }

    /// <summary>Returns the generated SQL to the pipeline instead of writing a file.</summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Exports system database user objects for one pipeline record.</summary>
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
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, IncludeDependencies.ToBool(), BatchSeparator, Path, FilePath,
            NoPrefix.ToBool(), ScriptingOptionsObject, NoClobber.ToBool(), PassThru.ToBool(), EnableException.ToBool(),
            TestBound(nameof(Path)), TestBound(nameof(ScriptingOptionsObject)),
            BoundValue("Path"), BoundValue("FilePath"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private object? BoundValue(string name)
    {
        return MyInvocation.BoundParameters.TryGetValue(name, out object? value) ? value : null;
    }

    // PS: the process body VERBATIM. Substitutions only: -FunctionName on every direct Stop-Function and
    // Write-Message; Test-Bound on ScriptingOptionsObject -> the carried flag; $PSBoundParameters.Path/.FilePath
    // -> the carried bound values. No ShouldProcess. The Path config default is applied in-hop when unbound.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $IncludeDependencies, $BatchSeparator, $Path, $FilePath, $NoPrefix, $ScriptingOptionsObject, $NoClobber, $PassThru, $EnableException, $__pathBound, $__scriptingBound, $__boundPathValue, $__boundFilePathValue, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, $IncludeDependencies, [string]$BatchSeparator, [string]$Path, [string]$FilePath, $NoPrefix, [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOptionsObject, $NoClobber, $PassThru, $EnableException, $__pathBound, $__scriptingBound, $__boundPathValue, $__boundFilePathValue, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not $__pathBound) { $Path = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport' }

        # Named-wrapper shim (W2-208): the process body runs inside a function carrying the command's
        # name so Get-ExportFilePath's (Get-PSCallStack)[1].Command default-filename (unbound-FilePath leg)
        # resolves to Export-DbaSysDbUserObject, not <ScriptBlock>. Dot-sourced, so scope is unchanged.
        function Export-DbaSysDbUserObject {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Attempting to connect to $instance" -FunctionName Export-DbaSysDbUserObject -ModuleName "dbatools"
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Export-DbaSysDbUserObject
                }

                if (!(Test-SqlSa -SqlInstance $server -SqlCredential $SqlCredential)) {
                    Stop-Function -Message "Not a sysadmin on $instance. Quitting." -FunctionName Export-DbaSysDbUserObject
                    return
                }
                $scriptPath = Get-ExportFilePath -Path $__boundPathValue -FilePath $__boundFilePathValue -Type sql -ServerName $SessionObject.Instance

                $systemDbs = "master", "model", "msdb"

                foreach ($systemDb in $systemDbs) {
                    $smoDb = $server.databases[$systemDb]
                    $userObjects = @()
                    $userObjects += $smoDb.Tables | Where-Object IsSystemObject -ne $true | Select-Object Name, @{l = 'SchemaName'; e = { $_.Schema } } , @{l = 'Type'; e = { 'TABLE' } }, @{l = 'Database'; e = { $systemDb } }
                    $userObjects += $smoDb.Triggers | Where-Object IsSystemObject -ne $true | Select-Object Name, @{l = 'SchemaName'; e = { $null } } , @{l = 'Type'; e = { 'SQL_TRIGGER' } }, @{l = 'Database'; e = { $systemDb } }
                    $params = @{
                        SqlInstance          = $server
                        Database             = $systemDb
                        ExcludeSystemObjects = $true
                        Type                 = 'View', 'TableValuedFunction', 'DefaultConstraint', 'StoredProcedure', 'Rule', 'InlineTableValuedFunction', 'ScalarFunction'
                    }
                    $userObjects += Get-DbaModule @params | Sort-Object Type | Select-Object Name, SchemaName, Type, Database

                    if ($userObjects) {
                        $results = @()
                        foreach ($userObject in $userObjects) {
                            $smObject = switch ($userObject.Type) {
                                "TABLE" { $smoDb.Tables.Item($userObject.Name, $userObject.SchemaName) }
                                "VIEW" { $smoDb.Views.Item($userObject.Name, $userObject.SchemaName) }
                                "SQL_STORED_PROCEDURE" { $smoDb.StoredProcedures.Item($userObject.Name, $userObject.SchemaName) }
                                "RULE" { $smoDb.Rules.Item($userObject.Name, $userObject.SchemaName) }
                                "SQL_TRIGGER" { $smoDb.Triggers.Item($userObject.Name) }
                                "SQL_TABLE_VALUED_FUNCTION" { $smoDb.UserDefinedFunctions.Item($userObject.Name, $userObject.SchemaName) }
                                "SQL_INLINE_TABLE_VALUED_FUNCTION" { $smoDb.UserDefinedFunctions.Item($userObject.Name, $userObject.SchemaName) }
                                "SQL_SCALAR_FUNCTION" { $smoDb.UserDefinedFunctions.Item($userObject.Name, $userObject.SchemaName) }
                            }
                            $results += $smObject
                        }

                        if ((Test-Path -Path $scriptPath) -and $NoClobber) {
                            Stop-Function -Message "File already exists. If you want to overwrite it remove the -NoClobber parameter. If you want to append data, please Use -Append parameter." -Target $scriptPath -Continue -FunctionName Export-DbaSysDbUserObject
                        }
                        if (!$__scriptingBound) {
                            $ScriptingOptionsObject = New-DbaScriptingOption
                            $ScriptingOptionsObject.IncludeDatabaseContext = $true
                            $ScriptingOptionsObject.ScriptBatchTerminator = $true
                            $ScriptingOptionsObject.AnsiFile = $true
                            if ($IncludeDependencies) {
                                $ScriptingOptionsObject.WithDependencies = $true
                            }
                        }

                        $export = @{
                            NoPrefix         = $NoPrefix
                            ScriptingOptions = $ScriptingOptionsObject
                            BatchSeparator   = $BatchSeparator
                        }

                        if ($PassThru) {
                            $results | Export-DbaScript @export -PassThru
                        } elseif ($Path -Or $FilePath) {
                            $results | Export-DbaScript @export -FilePath $scriptPath -Append -NoClobber:$NoClobber
                        }
                    }
                }
            } catch {
                Stop-Function -Message ("Exporting system objects failed on '{0}'" -f $server.Name) -FunctionName Export-DbaSysDbUserObject
            }
        }
        }
        . Export-DbaSysDbUserObject
} $SqlInstance $SqlCredential $IncludeDependencies $BatchSeparator $Path $FilePath $NoPrefix $ScriptingOptionsObject $NoClobber $PassThru $EnableException $__pathBound $__scriptingBound $__boundPathValue $__boundFilePathValue $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
