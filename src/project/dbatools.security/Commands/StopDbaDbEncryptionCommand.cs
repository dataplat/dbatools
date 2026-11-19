#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Disables Transparent Data Encryption on the user databases of one or more SQL Server instances.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the encryption disable, the
/// sequential and parallel-runspace processing, the output shape, and dbatools stream and error handling stay
/// observable-identical to the script implementation.
/// </para>
/// <para>
/// The command is process-only and mutating, and it streams its output through InvokeScopedStreaming: it emits
/// one object per database processed (sequentially, or as each parallel runspace completes). SqlInstance is a
/// plain (non-pipeline) Mandatory parameter, so there is one ProcessRecord and no cross-record state. Although
/// the command declares SupportsShouldProcess, the body never calls $PSCmdlet.ShouldProcess directly - the
/// sequential path delegates confirmation to the nested Disable-DbaDbEncryption -Confirm:$false, and WhatIf/Confirm
/// flow to the nested calls through the inner [CmdletBinding(SupportsShouldProcess)] preferences - so there is no
/// $__realCmdlet redirect. The -Parallel path (a RunspacePool that imports the dbatools module into each thread)
/// is ported VERBATIM; it runs as-is in module scope. The callback dispatches ErrorRecords to WriteError, else
/// WriteObject. EnableException and Parallel are carried as plain (untyped) values, because a switch in the inner
/// CmdletBinding scriptblock is excluded from positional binding. The four DIRECT Stop-Function/Write-Message
/// calls take -FunctionName; Write-ProgressHelper, Write-Progress, and the SMO/Disable-DbaDbEncryption calls are
/// left unedited.
/// </para>
/// </remarks>
[Cmdlet(VerbsLifecycle.Stop, "DbaDbEncryption", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class StopDbaDbEncryptionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Processes the databases in parallel using a runspace pool.</summary>
    [Parameter]
    public SwitchParameter Parallel { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Disables encryption for the bound instances.</summary>
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
            SqlInstance, SqlCredential, Parallel.ToBool(), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM (including the -Parallel runspace pool). Substitutions only: -FunctionName on
    // the four DIRECT Stop-Function/Write-Message calls. No ShouldProcess redirect (the body never calls it).
    // EnableException and Parallel received untyped.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Parallel, $EnableException, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, $Parallel, $EnableException, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # Named-wrapper shim: the body runs inside a function carrying the command's name so that
    # call-stack-deriving helpers see Stop-DbaDbEncryption as they do in the function world.
    # Write-ProgressHelper builds its Activity string from (Get-PSCallStack)[1].Command, which from
    # an anonymous scriptblock frame reads '<ScriptBlock>'. This row passes -TotalSteps explicitly,
    # so only the Activity label diverged - but it diverged on every progress record it emits.
    function Stop-DbaDbEncryption {
        $splatDatabase = @{
            SqlInstance   = $SqlInstance
            SqlCredential = $SqlCredential
        }
        $InputObject = Get-DbaDatabase @splatDatabase | Where-Object Name -NotIn "master", "model", "tempdb", "msdb", "resource"

        if (-not $Parallel) {
            # Sequential processing (original behavior)
            $stepCounter = 0
            foreach ($db in $InputObject) {
                $server = $db.Parent
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Disabling encryption for $($db.Name) on $($server.Name)" -TotalSteps $InputObject.Count
                try {
                    if ($db.EncryptionEnabled) {
                        $db | Disable-DbaDbEncryption -Confirm:$false
                    } else {
                        Write-Message -Level Verbose "Encryption was not enabled for $($db.Name) on $($server.Name)" -FunctionName Stop-DbaDbEncryption -ModuleName "dbatools"
                        $db | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, "Name as DatabaseName", EncryptionEnabled
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue -FunctionName Stop-DbaDbEncryption
                }
            }
        } else {
            # Parallel processing using runspaces
            $disableScript = {
                param (
                    $ServerName,
                    $DatabaseName,
                    $SqlCredential,
                    $EnableException
                )
                $server = $null
                try {
                    # Create new connection for this thread
                    $splatConnection = @{
                        SqlInstance   = $ServerName
                        SqlCredential = $SqlCredential
                    }
                    $server = Connect-DbaInstance @splatConnection
                    $db = $server.Databases[$DatabaseName]

                    if (-not $db) {
                        throw "Database $DatabaseName not found on $ServerName"
                    }

                    if ($db.EncryptionEnabled) {
                        # Disable encryption
                        $db.EncryptionEnabled = $false
                        $db.Alter()

                        # Wait for decryption to complete
                        $timeout = 120
                        $elapsed = 0
                        do {
                            Start-Sleep -Seconds 1
                            $elapsed++
                            $db.Refresh()
                        } while ($db.EncryptionEnabled -and $elapsed -lt $timeout)

                        # Drop the Database Encryption Key
                        if ($db.HasDatabaseEncryptionKey) {
                            $db.DatabaseEncryptionKey.Drop()
                        }

                        $db.Refresh()
                        [PSCustomObject]@{
                            ComputerName      = $server.ComputerName
                            InstanceName      = $server.ServiceName
                            SqlInstance       = $server.DomainInstanceName
                            DatabaseName      = $DatabaseName
                            EncryptionEnabled = $db.EncryptionEnabled
                            Status            = "Success"
                            Error             = $null
                        }
                    } else {
                        [PSCustomObject]@{
                            ComputerName      = $server.ComputerName
                            InstanceName      = $server.ServiceName
                            SqlInstance       = $server.DomainInstanceName
                            DatabaseName      = $DatabaseName
                            EncryptionEnabled = $false
                            Status            = "NotEncrypted"
                            Error             = $null
                        }
                    }
                } catch {
                    [PSCustomObject]@{
                        ComputerName      = $null
                        InstanceName      = $null
                        SqlInstance       = $ServerName
                        DatabaseName      = $DatabaseName
                        EncryptionEnabled = $null
                        Status            = "Failed"
                        Error             = $_.Exception.Message
                    }
                } finally {
                    $null = $server | Disconnect-DbaInstance -WhatIf:$false
                }
            }

            # Create runspace pool with dbatools module imported
            $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $dbatools = Get-Module -Name dbatools
            if ($dbatools) {
                $initialSessionState.ImportPSModule($dbatools.Path)
            }
            $runspacePool = [runspacefactory]::CreateRunspacePool(1, 10, $initialSessionState, $Host)
            $runspacePool.Open()

            $threads = @()

            foreach ($db in $InputObject) {
                $splatRunspace = @{
                    ServerName      = $db.Parent.Name
                    DatabaseName    = $db.Name
                    SqlCredential   = $SqlCredential
                    EnableException = $EnableException
                }

                Write-Message -Level Verbose "Queuing database $($db.Name) on $($db.Parent.Name) for decryption" -FunctionName Stop-DbaDbEncryption -ModuleName "dbatools"

                $thread = [powershell]::Create()
                $thread.RunspacePool = $runspacePool
                $null = $thread.AddScript($disableScript)
                $null = $thread.AddParameters($splatRunspace)

                $handle = $thread.BeginInvoke()
                $threads += [PSCustomObject]@{
                    Handle      = $handle
                    Thread      = $thread
                    Database    = $db.Name
                    Instance    = $db.Parent.Name
                    IsRetrieved = $false
                    Started     = Get-Date
                }
            }

            # Retrieve results from runspaces
            while ($threads | Where-Object { $_.IsRetrieved -eq $false }) {
                $totalThreads = ($threads | Measure-Object).Count
                $totalRetrievedThreads = ($threads | Where-Object { $_.IsRetrieved -eq $true } | Measure-Object).Count
                Write-Progress -Id 1 -Activity "Disabling encryption" -Status "Progress" -CurrentOperation "Processing: $totalRetrievedThreads/$totalThreads" -PercentComplete ($totalRetrievedThreads / $totalThreads * 100)

                foreach ($thread in ($threads | Where-Object { $_.IsRetrieved -eq $false })) {
                    if ($thread.Handle.IsCompleted) {
                        $result = $thread.Thread.EndInvoke($thread.Handle)
                        $thread.IsRetrieved = $true

                        if ($result) {
                            if ($result.Status -eq "Failed") {
                                Stop-Function -Message "Failed to disable encryption for $($result.DatabaseName) on $($result.SqlInstance): $($result.Error)" -Continue -FunctionName Stop-DbaDbEncryption
                            } else {
                                $result | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, DatabaseName, EncryptionEnabled
                            }
                        }

                        $thread.Thread.Dispose()
                    }
                }
                Start-Sleep -Milliseconds 500
            }

            $runspacePool.Close()
            $runspacePool.Dispose()
        }
    }
    . Stop-DbaDbEncryption
} $SqlInstance $SqlCredential $Parallel $EnableException $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
