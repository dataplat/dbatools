#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Synchronizes SQL Server login passwords from a source instance to one or more destination instances.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that the password-hash sync, the
/// ShouldProcess gate, the output shape, and dbatools stream and error handling stay observable-identical to the
/// script implementation.
/// </para>
/// <para>
/// The command is process-only and mutating, and it streams its output through InvokeScopedStreaming: it emits
/// one object per login synced per destination. InputObject is the only ValueFromPipeline parameter (Source and
/// Destination are Mandatory non-pipeline parameters), and the body never mutates $InputObject across records
/// (it only reads it), so there is no cross-record accumulation - a per-record hop is faithful. The password hash
/// is retrieved from the source via Get-LoginPasswordHash and handed to the nested Set-DbaLogin -PasswordHash
/// exactly as the script does; it is never logged or emitted, so nothing is leaked. The callback dispatches
/// ErrorRecords to WriteError, else WriteObject. EnableException is carried as a plain (untyped) value, because a
/// switch in the inner CmdletBinding scriptblock is excluded from positional binding. The eight edits are the
/// ShouldProcess redirect to $__realCmdlet and -FunctionName on the seven DIRECT Stop-Function/Write-Message
/// calls; Connect-DbaInstance, Get-DbaLogin, Get-LoginPasswordHash, and Set-DbaLogin are left unedited.
/// </para>
/// </remarks>
[Cmdlet(VerbsData.Sync, "DbaLoginPassword", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class SyncDbaLoginPasswordCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance to copy passwords from.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter? Source { get; set; }

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The destination SQL Server instance or instances to sync passwords to.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[]? Destination { get; set; }

    /// <summary>Alternative credential for the destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Login objects from Get-DbaLogin for pipeline operations.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public object[]? InputObject { get; set; }

    /// <summary>The specific logins to sync.</summary>
    [Parameter(Position = 5)]
    public string[]? Login { get; set; }

    /// <summary>The logins to exclude from the sync.</summary>
    [Parameter(Position = 6)]
    public string[]? ExcludeLogin { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Syncs login passwords for one pipeline record.</summary>
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
            Source, SourceSqlCredential, Destination, DestinationSqlCredential, InputObject, Login, ExcludeLogin, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM. Substitutions only: $PSCmdlet -> $__realCmdlet (the ShouldProcess gate);
    // -FunctionName on the seven DIRECT Stop-Function/Write-Message calls. EnableException received untyped.
    private const string ProcessScript = """
param($Source, $SourceSqlCredential, $Destination, $DestinationSqlCredential, $InputObject, $Login, $ExcludeLogin, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, [System.Management.Automation.PSCredential]$SourceSqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, [System.Management.Automation.PSCredential]$DestinationSqlCredential, [object[]]$InputObject, [string[]]$Login, [string[]]$ExcludeLogin, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if (Test-FunctionInterrupt) { return }

        try {
            $splatSource = @{
                SqlInstance    = $Source
                SqlCredential  = $SourceSqlCredential
                MinimumVersion = 8
            }
            $sourceServer = Connect-DbaInstance @splatSource
        } catch {
            Stop-Function -Message "Failed to connect to source instance $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Sync-DbaLoginPassword
            return
        }

        # Determine which logins to process
        if ($InputObject) {
            # Use logins from pipeline
            $sourceLogins = $InputObject | Where-Object LoginType -eq "SqlLogin"
        } else {
            # Get logins from source server
            $splatLogin = @{
                SqlInstance  = $sourceServer
                Login        = $Login
                ExcludeLogin = $ExcludeLogin
            }
            $sourceLogins = Get-DbaLogin @splatLogin | Where-Object LoginType -eq "SqlLogin"
        }

        if (-not $sourceLogins) {
            Write-Message -Level Verbose -Message "No SQL Server authentication logins found on source instance $Source" -FunctionName Sync-DbaLoginPassword -ModuleName "dbatools"
            return
        }

        foreach ($dest in $Destination) {
            try {
                $splatDestination = @{
                    SqlInstance    = $dest
                    SqlCredential  = $DestinationSqlCredential
                    MinimumVersion = 9
                }
                $destServer = Connect-DbaInstance @splatDestination
            } catch {
                Stop-Function -Message "Failed to connect to destination instance $dest" -Category ConnectionError -ErrorRecord $_ -Target $dest -Continue -FunctionName Sync-DbaLoginPassword
            }

            foreach ($sourceLogin in $sourceLogins) {
                $loginName = $sourceLogin.Name

                # Check if login exists on destination
                $destLogin = $destServer.Logins[$loginName]
                if (-not $destLogin) {
                    Write-Message -Level Verbose -Message "Login '$loginName' not found on destination $dest. Skipping." -FunctionName Sync-DbaLoginPassword -ModuleName "dbatools"
                    continue
                }

                # Verify destination login is SQL authentication
                if ($destLogin.LoginType -ne "SqlLogin") {
                    Write-Message -Level Verbose -Message "Login '$loginName' on destination $dest is not a SQL Server login. Skipping." -FunctionName Sync-DbaLoginPassword -ModuleName "dbatools"
                    continue
                }

                if ($__realCmdlet.ShouldProcess($dest, "Syncing password for login $loginName")) {
                    try {
                        # Get the password hash from source
                        $passwordHash = Get-LoginPasswordHash -Login $sourceLogin

                        if (-not $passwordHash) {
                            Write-Message -Level Warning -Message "Failed to retrieve password hash for login $loginName from source. Skipping." -FunctionName Sync-DbaLoginPassword -ModuleName "dbatools"
                            continue
                        }

                        # Apply the password hash to destination
                        $splatSetLogin = @{
                            SqlInstance     = $destServer
                            Login           = $loginName
                            PasswordHash    = $passwordHash
                            EnableException = $true
                        }
                        $result = Set-DbaLogin @splatSetLogin

                        [PSCustomObject]@{
                            SourceServer      = $sourceServer.Name
                            DestinationServer = $destServer.Name
                            Login             = $loginName
                            Status            = "Success"
                            Notes             = $null
                        }
                    } catch {
                        $errorMessage = $_.Exception.Message
                        Stop-Function -Message "Failed to sync password for login $loginName on $dest : $errorMessage" -ErrorRecord $_ -Target $loginName -Continue -FunctionName Sync-DbaLoginPassword

                        [PSCustomObject]@{
                            SourceServer      = $sourceServer.Name
                            DestinationServer = $destServer.Name
                            Login             = $loginName
                            Status            = "Failed"
                            Notes             = $errorMessage
                        }
                    }
                }
            }
        }
} $Source $SourceSqlCredential $Destination $DestinationSqlCredential $InputObject $Login $ExcludeLogin $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
