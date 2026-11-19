#nullable enable

namespace Dataplat.Dbatools.Commands;

public sealed partial class AddDbaAgDatabaseCommand
{
    // PS: the process block VERBATIM, first half (composed as ProcessScript = head +
    // newline + tail; the composition is re-parsed at build verification). Whole-record
    // hop: the per-record test loops and the per-result orchestration share record
    // scope exactly like the source's process block. Substitutions across both halves:
    // 62 -FunctionName appends on the hop-frame Stop-Function/Write-Message sites and 7
    // ShouldProcess routes to the real cmdlet; stripping both reproduces the source
    // bytes (verified mechanically). The carried SkipReuseSourceFolderStructure seeds
    // from state at hop top and writes back at the tail - the source mutates that
    // parameter in function scope, which persists across records.
    private const string ProcessScriptHead = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $Database, $Secondary, $SecondarySqlCredential, $InputObject, $SeedingMode, $SharedPath, $UseLastBackup, $AdvancedBackupParams, $NoWait, $MasterKeySecurePassword, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug, $__boundProgressAction)
$__commonParameters = @{}
if ($null -ne $__boundProgressAction) { $__commonParameters.ProgressAction = $__boundProgressAction }
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [PSCredential]$SqlCredential, [string]$AvailabilityGroup, [string[]]$Database, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Secondary, [PSCredential]$SecondarySqlCredential, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, [string]$SeedingMode, [string]$SharedPath, $UseLastBackup, [hashtable]$AdvancedBackupParams, $NoWait, [Security.SecureString]$MasterKeySecurePassword, $EnableException, $__state, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug, $__boundProgressAction)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $timeoutExisting = $__state.timeoutExisting
    $timeoutSynchronization = $__state.timeoutSynchronization
    $waitWhile = $__state.waitWhile
    $reportSeeding = $__state.reportSeeding
    $SkipReuseSourceFolderStructure = [bool]$__state.skipReuse

        # We store information for the progress bar in a hashtable suitable for splatting.
        $progress = @{ }
        $progress['Id'] = Get-Random
        $progress['Activity'] = "Adding database(s) to Availability Group $AvailabilityGroup"

        $testResult = @( )

        foreach ($dbName in $Database) {
            try {
                $progress['Status'] = "Test prerequisites for joining database $dbName"
                Write-Progress @progress
                $testSplat = @{
                    SqlInstance            = $SqlInstance
                    SqlCredential          = $SqlCredential
                    Secondary              = $Secondary
                    SecondarySqlCredential = $SecondarySqlCredential
                    AvailabilityGroup      = $AvailabilityGroup
                    AddDatabase            = $dbName
                    UseLastBackup          = $UseLastBackup
                    EnableException        = $true
                }
                if ($SeedingMode) { $testSplat['SeedingMode'] = $SeedingMode }
                if ($SharedPath) { $testSplat['SharedPath'] = $SharedPath }
                $testResult += Test-DbaAvailabilityGroup @testSplat
            } catch {
                Stop-Function -Message "Testing prerequisites for joining database $dbName to Availability Group $AvailabilityGroup failed." -ErrorRecord $_ -Continue -FunctionName Add-DbaAgDatabase
            }
        }

        foreach ($db in $InputObject) {
            try {
                $progress['Status'] = "Test prerequisites for joining database $($db.Name)"
                Write-Progress @progress
                $testSplat = @{
                    SqlInstance            = $db.Parent
                    Secondary              = $Secondary
                    SecondarySqlCredential = $SecondarySqlCredential
                    AvailabilityGroup      = $AvailabilityGroup
                    AddDatabase            = $db.Name
                    UseLastBackup          = $UseLastBackup
                    EnableException        = $true
                }
                if ($SeedingMode) { $testSplat['SeedingMode'] = $SeedingMode }
                if ($SharedPath) { $testSplat['SharedPath'] = $SharedPath }
                $testResult += Test-DbaAvailabilityGroup @testSplat
            } catch {
                Stop-Function -Message "Testing prerequisites for joining database $($db.Name) to Availability Group $AvailabilityGroup failed." -ErrorRecord $_ -Continue -FunctionName Add-DbaAgDatabase
            }
        }

        Write-Message -Level Verbose -Message "Test for prerequisites returned $($testResult.Count) databases that will be joined to the Availability Group $AvailabilityGroup." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"

        foreach ($result in $testResult) {
            $server = $result.PrimaryServerSMO
            $ag = $result.AvailabilityGroupSMO
            $db = $result.DatabaseSMO
            $replicaServerSMO = $result.ReplicaServerSMO
            $restoreNeeded = $result.RestoreNeeded
            $backups = $result.Backups
            $replicaAgDbSMO = @{ }
            $targetSynchronizationState = @{ }
            $output = @( )

            $progress['Activity'] = "Adding database $($db.Name) to Availability Group $AvailabilityGroup"

            $progress['Status'] = "Step 1/5: Setting seeding mode if needed"
            Write-Message -Level Verbose -Message $progress['Status'] -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
            Write-Progress @progress

            if ($SeedingMode) {
                Write-Message -Level Verbose -Message "Setting seeding mode to $SeedingMode." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                $failure = $false
                foreach ($replicaName in $replicaServerSMO.Keys) {
                    $replica = $ag.AvailabilityReplicas[$replicaName]
                    if ($replica.SeedingMode -ne $SeedingMode) {
                        if ($__realCmdlet.ShouldProcess($server, "Setting seeding mode for replica $replica to $SeedingMode")) {
                            try {
                                Write-Message -Level Verbose -Message "Setting seeding mode for replica $replica to $SeedingMode." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                                $replica.SeedingMode = $SeedingMode
                                $replica.Alter()
                                if ($SeedingMode -eq 'Automatic') {
                                    Write-Message -Level Verbose -Message "Setting GrantAvailabilityGroupCreateDatabasePrivilege on server $($replicaServerSMO[$replicaName]) for Availability Group $AvailabilityGroup." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                                    $null = Grant-DbaAgPermission -SqlInstance $replicaServerSMO[$replicaName] -Type AvailabilityGroup -AvailabilityGroup $AvailabilityGroup -Permission CreateAnyDatabase
                                }
                            } catch {
                                $failure = $true
                                Stop-Function -Message "Failed setting seeding mode for replica $replica to $SeedingMode." -ErrorRecord $_ -Continue -FunctionName Add-DbaAgDatabase
                            }
                        }
                    }
                }
                if ($failure) {
                    Stop-Function -Message "Failed setting seeding mode to $SeedingMode." -Continue -FunctionName Add-DbaAgDatabase
                }
            }

            # For TDE-encrypted databases, the master certificate must exist on every secondary replica
            # before a backup can be restored or automatic seeding can succeed.
            if ($db.EncryptionEnabled -and $db.HasDatabaseEncryptionKey -and $db.DatabaseEncryptionKey.EncryptorType -eq "ServerCertificate") {
                $encryptorName = $db.DatabaseEncryptionKey.EncryptorName
                Write-Message -Level Verbose -Message "Database $($db.Name) is TDE-encrypted using certificate '$encryptorName'. Checking secondary replicas." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"

                try {
                    $sourceTdeCert = Get-DbaDbCertificate -SqlInstance $server -Database "master" -Certificate $encryptorName -EnableException | Select-Object -First 1
                } catch {
                    Stop-Function -Message "Failed to validate TDE certificate '$encryptorName' on primary instance $($server.Name)." -ErrorRecord $_ -Continue -FunctionName Add-DbaAgDatabase
                }

                if (-not $sourceTdeCert) {
                    Stop-Function -Message "Database $($db.Name) is encrypted by certificate '$encryptorName', but that certificate was not found in master on $($server.Name)." -Continue -FunctionName Add-DbaAgDatabase
                }

                if (-not $sourceTdeCert.PrivateKeyExists) {
                    Stop-Function -Message "Database $($db.Name) is encrypted by certificate '$encryptorName', but the certificate on $($server.Name) does not have an accessible private key." -Continue -FunctionName Add-DbaAgDatabase
                }

                $failure = $false
                foreach ($replicaName in $replicaServerSMO.Keys) {
                    $replicaServer = $replicaServerSMO[$replicaName]
                    try {
                        $existingCert = Get-DbaDbCertificate -SqlInstance $replicaServer -Database "master" -Certificate $encryptorName -EnableException | Select-Object -First 1
                    } catch {
                        $failure = $true
                        Stop-Function -Message "Failed to validate TDE certificate '$encryptorName' on replica $replicaName." -ErrorRecord $_ -Continue -FunctionName Add-DbaAgDatabase
                    }

                    if (-not $existingCert) {
                        if (-not $SharedPath) {
                            $failure = $true
                            Stop-Function -Message "Replica $replicaName is missing TDE certificate '$encryptorName'. Provide -SharedPath and optionally -MasterKeySecurePassword to copy it automatically, or pre-stage the matching certificate before adding the database." -Continue -FunctionName Add-DbaAgDatabase
                        }

                        if ($__realCmdlet.ShouldProcess($replicaServer, "Copy TDE certificate '$encryptorName' from primary to replica $replicaName")) {
                            try {
                                Write-Message -Level Verbose -Message "TDE certificate '$encryptorName' not found on $replicaName. Copying from primary." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                                $splatTdeCert = @{
                                    Source          = $server
                                    Destination     = $replicaServer
                                    Database        = "master"
                                    Certificate     = $encryptorName
                                    SharedPath      = $SharedPath
                                    EnableException = $true
                                }
                                if ($MasterKeySecurePassword) {
                                    $splatTdeCert.MasterKeyPassword = $MasterKeySecurePassword
                                }
                                $null = Copy-DbaDbCertificate @splatTdeCert
                            } catch {
                                $failure = $true
                                Stop-Function -Message "Failed to copy TDE certificate '$encryptorName' to replica $replicaName." -ErrorRecord $_ -Continue -FunctionName Add-DbaAgDatabase
                            }
                        }
                        continue
                    }

                    if (-not $existingCert.PrivateKeyExists) {
                        $failure = $true
                        Stop-Function -Message "TDE certificate '$encryptorName' exists on replica $replicaName but does not include a private key. Restore or automatic seeding cannot use it." -Continue -FunctionName Add-DbaAgDatabase
                    }

                    if ($existingCert.Thumbprint -ne $sourceTdeCert.Thumbprint) {
                        $failure = $true
                        Stop-Function -Message "TDE certificate '$encryptorName' on replica $replicaName does not match the primary certificate on $($server.Name)." -Continue -FunctionName Add-DbaAgDatabase
                    }

                    Write-Message -Level Verbose -Message "TDE certificate '$encryptorName' already exists on replica $replicaName and matches the primary certificate." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                }

                if ($failure) {
                    Stop-Function -Message "Failed to validate or copy TDE certificate '$encryptorName' for all replicas of database $($db.Name)." -Continue -FunctionName Add-DbaAgDatabase
                }
            }

            $progress['Status'] = "Step 2/5: Running backup and restore if needed"
            Write-Message -Level Verbose -Message $progress['Status'] -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
            Write-Progress @progress

            if ($restoreNeeded.Count -gt 0) {
                if (-not $backups) {
                    if ($__realCmdlet.ShouldProcess($server, "Taking full and log backup of database $($db.Name)")) {
                        try {
                            Write-Message -Level Verbose -Message "Taking full and log backup of database $($db.Name)." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                            if ($AdvancedBackupParams) {
                                $fullbackup = $db | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Full -EnableException @AdvancedBackupParams
                                $logbackup = $db | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Log -EnableException @AdvancedBackupParams
                            } else {
                                $fullbackup = $db | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Full -EnableException
                                $logbackup = $db | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Log -EnableException
                            }
                            $backups = $fullbackup, $logbackup
                        } catch {
                            Stop-Function -Message "Failed to take full and log backup of database $($db.Name)." -ErrorRecord $_ -Continue -FunctionName Add-DbaAgDatabase
                        }
                    }
                }
                $failure = $false
                foreach ($replicaName in $restoreNeeded.Keys) {
                    if ($__realCmdlet.ShouldProcess($replicaServerSMO[$replicaName], "Restore database $($db.Name) to replica $replicaName")) {
                        try {
                            Write-Message -Level Verbose -Message "Restore database $($db.Name) to replica $replicaName." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                            $restoreParams = @{
                                SqlInstance          = $replicaServerSMO[$replicaName]
                                NoRecovery           = $true
                                TrustDbBackupHistory = $true
                                EnableException      = $true
                            }

                            # Check if we should skip ReuseSourceFolderStructure
                            if (-not $SkipReuseSourceFolderStructure) {
                                # Check if primary and replica are on the same platform
                                $primaryPlatform = $server.HostPlatform
                                $replicaPlatform = $replicaServerSMO[$replicaName].HostPlatform
                                if ($primaryPlatform -ne $replicaPlatform) {
                                    Write-Message -Level Verbose -Message "Primary platform ($primaryPlatform) does not match replica platform ($replicaPlatform). Setting SkipReuseSourceFolderStructure." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                                    $SkipReuseSourceFolderStructure = $true
                                }
                            }

                            # Only use ReuseSourceFolderStructure if not skipped
                            if (-not $SkipReuseSourceFolderStructure) {
                                Write-Message -Level Verbose -Message "Using ReuseSourceFolderStructure to maintain consistent folder layout." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                                $restoreParams['ReuseSourceFolderStructure'] = $true
                            } else {
                                Write-Message -Level Verbose -Message "Using replica's default paths for database files." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
                            }

                            $sourceOwner = $db.Owner
                            $replicaOwner = $replicaServerSMO[$replicaName].ConnectedAs
                            if ($sourceOwner -ne $replicaOwner) {
                                Write-Message -Level Verbose -Message "Source database owner is $sourceOwner, replica database owner would be $replicaOwner." -FunctionName Add-DbaAgDatabase -ModuleName "dbatools"
""";
}
