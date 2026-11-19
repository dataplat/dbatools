#nullable enable

namespace Dataplat.Dbatools.Commands;

public sealed partial class InvokeDbaDbMirroringCommand
{
    // PS: the begin block's Force -> ConfirmPreference suppression and $params
    // construction ride verbatim at the hop top ($params reads the CARRIED
    // case-insensitive clone of the real bound parameters), then the source process block
    // VERBATIM, first half (composed as ProcessScript = head + newline + tail; re-parsed at
    // build verification), CRLF-preserved. Bracketing the body: the carried cross-record
    // parameter state ($Primary, $UseLastBackup) is seeded BEFORE the body so it observes
    // what the source's function-scope parameters would hold on a later piped record, and
    // the W3-082 prompt-state transplant is injected before any gate. Substitutions across
    // both halves: 17 -FunctionName appends (16 Stop-Function + 1 Write-Message) and three
    // Test-Bound flag rewrites (SOURCE comments); stripping reproduces the source bytes.
    private const string ProcessScriptHead = """
param($Primary, $PrimarySqlCredential, $Mirror, $MirrorSqlCredential, $Witness, $WitnessSqlCredential, $Database, $EndpointEncryption, $EncryptionAlgorithm, $SharedPath, $InputObject, $UseLastBackup, $Force, $EnableException, $__allParams, $__boundPrimary, $__boundDatabase, $__boundSharedPath, $__boundUseLastBackup, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Primary, [PSCredential]$PrimarySqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Mirror, [PSCredential]$MirrorSqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Witness, [PSCredential]$WitnessSqlCredential, [string[]]$Database, [string]$EndpointEncryption, [string]$EncryptionAlgorithm, [string]$SharedPath, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $UseLastBackup, $Force, $EnableException, $__allParams, $__boundPrimary, $__boundDatabase, $__boundSharedPath, $__boundUseLastBackup, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($Force) { $ConfirmPreference = 'none' }

    $params = $__allParams
    $null = $params.Remove('UseLastBackup')
    $null = $params.Remove('Force')
    $null = $params.Remove('Confirm')
    $null = $params.Remove('Whatif')

    # cross-record PARAMETER state: the source reassigns $Primary (to the resolved primary
    # server) and $UseLastBackup (after taking the seeding backups); parameters are fn-scope,
    # so a later piped record observes those values. Seed them before the body runs.
    if ($null -ne $__state) {
        if ($null -ne $__state.primary) { $Primary = $__state.primary }
        if ($null -ne $__state.useLastBackup) { $UseLastBackup = $__state.useLastBackup }
    }

    # cross-record engine-state restore: the ShouldProcess Yes/No-to-All answer spans the
    # pipeline in the source (one CommandRuntime); the transplant field name is identical
    # on PS 5.1 and PS 7 (W3-082 mechanism, empirically verified)
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Invoke-DbaDbMirroring: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state -and $null -ne $__state.shouldProcessContinueStatus) {
        $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
    }

    . {
        if ($__boundPrimary -and -not $__boundDatabase) { # SOURCE: if ((Test-Bound -ParameterName Primary) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when Primary is specified" -FunctionName Invoke-DbaDbMirroring
            return
        }

        if ($Force -and (-not $SharedPath -and -not $UseLastBackup)) {
            Stop-Function -Message "SharedPath or UseLastBackup is required when Force is used" -FunctionName Invoke-DbaDbMirroring
            return
        }

        if ($Primary) {
            $InputObject += Get-DbaDatabase -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -Database $Database
        }

        foreach ($primarydb in $InputObject) {
            $stepCounter = 0
            $Primary = $source = $primarydb.Parent
            foreach ($currentmirror in $Mirror) {
                $stepCounter = 0
                try {
                    $dest = Connect-DbaInstance -SqlInstance $currentmirror -SqlCredential $MirrorSqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $currentmirror -Continue -FunctionName Invoke-DbaDbMirroring
                }

                if ($Witness) {
                    try {
                        $witserver = Connect-DbaInstance -SqlInstance $Witness -SqlCredential $WitnessSqlCredential
                    } catch {
                        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Witness -Continue -FunctionName Invoke-DbaDbMirroring
                    }
                }

                $dbName = $primarydb.Name

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Validating mirror setup"
                # Thanks to https://github.com/mmessano/PowerShell/blob/master/SQL-ConfigureDatabaseMirroring.ps1 for the tips

                $params.Database = $dbName
                $validation = Invoke-DbMirrorValidation @params

                if ($__boundSharedPath -and -not $validation.AccessibleShare) { # SOURCE: if ((Test-Bound -ParameterName SharedPath) -and -not $validation.AccessibleShare) {
                    Stop-Function -Continue -Message "Cannot access $SharedPath from $($dest.Name)" -FunctionName Invoke-DbaDbMirroring
                }

                if (-not $validation.EditionMatch) {
                    Stop-Function -Continue -Message "This mirroring configuration is not supported. Because the principal server instance, $source, is $($source.EngineEdition) Edition, the mirror server instance must also be $($source.EngineEdition) Edition." -FunctionName Invoke-DbaDbMirroring
                }

                $badstate = $validation | Where-Object MirroringStatus -ne "none"
                if ($badstate) {
                    Stop-Function -Message "Cannot setup mirroring on database ($dbName) due to its current mirroring state on primary: $($badstate.MirroringStatus)" -Continue -FunctionName Invoke-DbaDbMirroring
                }

                if ($primarydb.Status -ne "Normal") {
                    Stop-Function -Message "Cannot setup mirroring on database ($dbName) due to its current state: $($primarydb.Status)" -Continue -FunctionName Invoke-DbaDbMirroring
                }

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Setting recovery model for $dbName on $($source.Name) to Full"

                if ($primarydb.RecoveryModel -ne "Full") {
                    if ($__boundUseLastBackup) { # SOURCE: if ((Test-Bound -ParameterName UseLastBackup)) {
                        Stop-Function -Message "$dbName not set to full recovery. UseLastBackup cannot be used." -FunctionName Invoke-DbaDbMirroring
                    } else {
                        $null = Set-DbaDbRecoveryModel -SqlInstance $source -Database $primarydb.Name -RecoveryModel Full
                    }
                }

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Copying $dbName from primary to mirror"

                if (-not $validation.DatabaseExistsOnMirror -or $Force) {
                    if ($UseLastBackup) {
                        $allbackups = Get-DbaDbBackupHistory -SqlInstance $primarydb.Parent -Database $primarydb.Name -IncludeCopyOnly -Last
                    } else {
                        if ($Force -or $Pscmdlet.ShouldProcess("$Primary", "Creating full and log backups of $primarydb on $SharedPath")) {
                            try {
                                $fullbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Full -EnableException
                                $logbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Log -EnableException
                                $allbackups = $fullbackup, $logbackup
                                $UseLastBackup = $true
                            } catch {
                                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $primarydb -Continue -FunctionName Invoke-DbaDbMirroring
                            }
                        }
                    }

                    if ($Pscmdlet.ShouldProcess("$currentmirror", "Restoring full and log backups of $primarydb from $Primary")) {
                        foreach ($currentmirrorinstance in $currentmirror) {
                            try {
                                $null = $allbackups | Restore-DbaDatabase -SqlInstance $currentmirrorinstance -SqlCredential $MirrorSqlCredential -WithReplace -NoRecovery -TrustDbBackupHistory -EnableException
                            } catch {
                                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $dest -Continue -FunctionName Invoke-DbaDbMirroring
                            }
                        }
                    }

                    if ($SharedPath) {
                        Write-Message -Level Verbose -Message "Backups still exist on $SharedPath" -FunctionName Invoke-DbaDbMirroring -ModuleName "dbatools"
                    }
                }

                $currentmirrordb = Get-DbaDatabase -SqlInstance $dest -Database $dbName
                $primaryendpoint = Get-DbaEndpoint -SqlInstance $source | Where-Object EndpointType -eq DatabaseMirroring
                $currentmirrorendpoint = Get-DbaEndpoint -SqlInstance $dest | Where-Object EndpointType -eq DatabaseMirroring

""";
}
