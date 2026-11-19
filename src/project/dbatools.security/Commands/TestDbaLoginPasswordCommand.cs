#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests SQL Server logins for weak passwords (null, same as the username, or matching a supplied dictionary).
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the weak-password query, the
/// batching, the output shape, and dbatools stream and error handling stay observable-identical to the script
/// implementation.
/// </para>
/// <para>
/// The script keeps state across its begin/process/end blocks in one function scope: begin defines the nested
/// Split-ArrayInChunks helper and the SQL templates, process accumulates the logins to test into $logins, and
/// END does the actual per-server work. A per-record hop would give each record a fresh scope and drop all of
/// that, so the port collects one batch per ProcessRecord (each captures that record's SqlInstance and
/// InputObject bindings) and runs ONE hop in EndProcessing that executes begin once, replays the process body
/// per batch, and then runs end - all in the single shared scope, so $logins accumulates and the helper and
/// templates are visible to end exactly as in the script. SqlInstance is not ValueFromPipeline (only
/// InputObject is), so InputObject rebinds each record and the per-batch assignment is unconditional (no
/// cross-record accumulation of $InputObject; only $logins accumulates, in the process body). Each batch's
/// process body is dot-sourced so an early return would skip only that batch. There is no ShouldProcess in the
/// source. EnableException is carried as a plain (untyped) value, because a switch in the inner CmdletBinding
/// scriptblock is excluded from positional binding. The five DIRECT Stop-Function/Write-Message calls take
/// -FunctionName. The callback dispatches ErrorRecords to WriteError, else WriteObject.
/// </para>
/// </remarks>
[Cmdlet(VerbsDiagnostic.Test, "DbaLoginPassword")]
public sealed class TestDbaLoginPasswordCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The specific logins to test.</summary>
    [Parameter(Position = 2)]
    public string[]? Login { get; set; }

    /// <summary>Additional weak passwords to test for.</summary>
    [Parameter(Position = 3)]
    public string[]? Dictionary { get; set; }

    /// <summary>Login objects from Get-DbaLogin for pipeline operations.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public Microsoft.SqlServer.Management.Smo.Login[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>One batch per pipeline record, capturing that record's SqlInstance and InputObject bindings.</summary>
    private readonly List<object?[]?> _batches = new List<object?[]?>();

    /// <summary>Records each pipeline record's input as a batch; the work runs once in EndProcessing.</summary>
    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        _batches.Add(new object?[] { SqlInstance, InputObject });
    }

    /// <summary>Runs begin once, replays the process body per batch, then runs end - in one shared scope.</summary>
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
            if (item is not null)
                WriteObject(item);
        }, ProcessScript,
            _batches.ToArray(), SqlCredential, Login, Dictionary, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM (Split-ArrayInChunks helper + SQL templates), then a per-batch replay of the
    // process body, then the end block VERBATIM - all in one scope. Substitutions only: -FunctionName on the
    // five DIRECT Stop-Function/Write-Message calls. EnableException received untyped. No ShouldProcess.
    private const string ProcessScript = """
param($__batches, $SqlCredential, $Login, $Dictionary, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__batches, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Login, [string[]]$Dictionary, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }


        function Split-ArrayInChunks {
            param(
                [object[]] $source,
                [int] $size = 1
            )
            $chunkCount = [Math]::Ceiling($source.Count / $size)
            0 .. ($chunkCount - 1) | ForEach-Object {
                $startIndex = $_ * $size
                $endIndex = [Math]::Min(($_ + 1) * $size, $source.Count)
                , $source[$startIndex .. ($endIndex - 1)]
            }
        }

        $maxBatch = 200

        $CheckPasses = "", "@@Name"
        if ($Dictionary) {
            $Dictionary | ForEach-Object { $CheckPasses += $PSItem }
        }

        $sqlStart = "DECLARE @WeakPwdList TABLE(WeakPwd NVARCHAR(255))
                --Define weak password list
                --Use @@Name if users password contain their name
                INSERT INTO @WeakPwdList(WeakPwd)
                VALUES (NULL)"

        $sqlEnd = "
                SELECT SERVERPROPERTY('MachineName') AS [ComputerName],
                    ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                    SERVERPROPERTY('ServerName') AS [SqlInstance],
                    SysLogins.name AS SqlLogin,
                    WeakPassword = 'True',
                    REPLACE(WeakPassword.WeakPwd,'@@Name',SysLogins.name) AS [Password],
                    SysLogins.is_disabled AS Disabled,
                    SysLogins.create_date AS CreatedDate,
                    SysLogins.modify_date AS ModifiedDate,
                    SysLogins.default_database_name AS DefaultDatabase
                FROM sys.sql_logins SysLogins
                INNER JOIN @WeakPwdList WeakPassword
                ON PWDCOMPARE(REPLACE(WeakPassword.WeakPwd,'@@Name',SysLogins.name),password_hash) = 1
                "
        foreach ($__batch in $__batches) {
            $SqlInstance = $__batch[0]
            $InputObject = $__batch[1]
            . {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Test-DbaLoginPassword
            }
            $InputObject += Get-DbaLogin -SqlInstance $server -Login $Login
        }

        $logins += $InputObject
            }
        }
        $servers = $logins | Select-Object -Unique -ExpandProperty Parent

        foreach ($serverinstance in $servers) {
            Write-Message -Level Verbose -Message "Testing: same username as Password" -FunctionName Test-DbaLoginPassword -ModuleName "dbatools"
            Write-Message -Level Verbose -Message "Testing: the following Passwords $CheckPasses" -FunctionName Test-DbaLoginPassword -ModuleName "dbatools"
            try {
                $checkParts = , (Split-ArrayInChunks -source $CheckPasses -size $maxBatch)

                $loopIndex = 0

                foreach ($batch in $checkParts) {
                    $thisBatch = $sqlStart
                    $sqlParams = @{ }
                    foreach ($piece in $batch) {
                        $loopIndex += 1
                        $paramKey = "@p_$loopIndex"
                        $sqlParams[$paramKey] = $piece
                        $thisBatch += ", ($paramKey)"
                    }
                    $thisBatch += $sqlEnd
                    Write-Message -Level Debug -Message "sql: $thisBatch" -FunctionName Test-DbaLoginPassword -ModuleName "dbatools"
                    Invoke-DbaQuery -SqlInstance $serverinstance -Query $thisBatch -SqlParameter $sqlParams
                }

            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $serverinstance -Continue -FunctionName Test-DbaLoginPassword
            }
        }
} $__batches $SqlCredential $Login $Dictionary $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
