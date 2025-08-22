function Invoke-DbaDbMirroring {
    <#
    .SYNOPSIS
        Creates and configures database mirroring between SQL Server instances with full validation and setup

    .DESCRIPTION
        Creates database mirroring configurations between SQL Server instances, handling the complete end-to-end setup process that would normally require dozens of manual T-SQL commands and careful validation steps. This function eliminates the complexity and potential errors involved in manually configuring database mirroring partnerships.

        The function performs comprehensive validation before setup and handles all the technical requirements:
        * Verifies that mirroring is possible between the specified instances and databases
        * Sets the recovery model to Full if needed (required for mirroring)
        * Creates and restores full and log backups to initialize the mirror database if it doesn't exist
        * Sets up database mirroring endpoints on all participating instances
        * Creates logins and grants CONNECT permissions to service accounts on all endpoints
        * Starts endpoints if they're not already running
        * Establishes the mirroring partnership between primary and mirror
        * Configures witness server if specified for automatic failover scenarios

        This saves DBAs significant time when setting up high availability solutions and reduces the risk of configuration errors that can cause mirroring setup failures. The function can work with existing backups or create fresh ones as needed.

        NOTE: If backup/restore is performed, the backup files will remain on the network share for your records.

    .PARAMETER Primary
        SQL Server name or SMO object representing the primary SQL Server.

    .PARAMETER PrimarySqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Mirror
        SQL Server name or SMO object representing the mirror SQL Server.

    .PARAMETER MirrorSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Witness
        SQL Server name or SMO object representing the witness SQL Server.

    .PARAMETER WitnessSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database or databases to mirror.

    .PARAMETER SharedPath
        The network share where the backups will be backed up and restored from.

        Each SQL Server service account must have access to this share.

        NOTE: If a backup / restore is performed, the backups will be left in tact on the network share.

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase.

    .PARAMETER UseLastBackup
        Use the last full backup of database.

    .PARAMETER Force
        Drop and recreate the database on remote servers using fresh backup.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER EndpointEncryption
        Used to specify the state of encryption on the endpoint. Defaults to required.
        Disabled
        Required
        Supported

    .PARAMETER EncryptionAlgorithm
        Specifies an encryption algorithm used on an endpoint. Defaults to Aes.

        Options are:
        AesRC4
        Aes
        None
        RC4
        RC4Aes

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Mirroring, Mirror, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbMirroring

    .EXAMPLE
        PS C:\> $params = @{
        >> Primary = 'sql2017a'
        >> Mirror = 'sql2017b'
        >> MirrorSqlCredential = 'sqladmin'
        >> Witness = 'sql2019'
        >> Database = 'pubs'
        >> SharedPath = '\\nas\sql\share'
        >> }
        >>
        PS C:\> Invoke-DbaDbMirroring @params

        Performs a bunch of checks to ensure the pubs database on sql2017a
        can be mirrored from sql2017a to sql2017b. Logs in to sql2019 and sql2017a
        using Windows credentials and sql2017b using a SQL credential.

        Prompts for confirmation for most changes. To avoid confirmation, use -Confirm:$false or
        use the syntax in the second example.

    .EXAMPLE
        PS C:\> $params = @{
        >> Primary = 'sql2017a'
        >> Mirror = 'sql2017b'
        >> MirrorSqlCredential = 'sqladmin'
        >> Witness = 'sql2019'
        >> Database = 'pubs'
        >> SharedPath = '\\nas\sql\share'
        >> Force = $true
        >> Confirm = $false
        >> }
        >>
        PS C:\> Invoke-DbaDbMirroring @params

        Performs a bunch of checks to ensure the pubs database on sql2017a
        can be mirrored from sql2017a to sql2017b. Logs in to sql2019 and sql2017a
        using Windows credentials and sql2017b using a SQL credential.

        Drops existing pubs database on Mirror and restores it with
        a fresh backup.

        Does all the things in the description, does not prompt for confirmation.

    .EXAMPLE
        PS C:\> $map = @{ 'database_data' = 'M:\Data\database_data.mdf' 'database_log' = 'L:\Log\database_log.ldf' }
        PS C:\> Get-ChildItem \\nas\seed | Restore-DbaDatabase -SqlInstance sql2017b -FileMapping $map -NoRecovery
        PS C:\> Get-DbaDatabase -SqlInstance sql2017a -Database pubs | Invoke-DbaDbMirroring -Mirror sql2017b -Confirm:$false

        Restores backups from sql2017a to a specific file structure on sql2017b then creates mirror with no prompts for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017a -Database pubs |
        >> Invoke-DbaDbMirroring -Mirror sql2017b -UseLastBackup -Confirm:$false

        Mirrors pubs on sql2017a to sql2017b and uses the last full and logs from sql2017a to seed. Doesn't prompt for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter]$Primary,
        [PSCredential]$PrimarySqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Mirror,
        [PSCredential]$MirrorSqlCredential,
        [DbaInstanceParameter]$Witness,
        [PSCredential]$WitnessSqlCredential,
        [string[]]$Database,
        [ValidateSet('Disabled', 'Required', 'Supported')]
        [string]$EndpointEncryption = 'Required',
        [ValidateSet('Aes', 'AesRC4', 'None', 'RC4', 'RC4Aes')]
        [string]$EncryptionAlgorithm = 'Aes',
        [string]$SharedPath,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$UseLastBackup,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        $params = $PSBoundParameters
        $null = $params.Remove('UseLastBackup')
        $null = $params.Remove('Force')
        $null = $params.Remove('Confirm')
        $null = $params.Remove('Whatif')
    }
    process {
        if ((Test-Bound -ParameterName Primary) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when Primary is specified"
            return
        }

        if ($Force -and (-not $SharedPath -and -not $UseLastBackup)) {
            Stop-Function -Message "SharedPath or UseLastBackup is required when Force is used"
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
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $currentmirror -Continue
                }

                if ($Witness) {
                    try {
                        $witserver = Connect-DbaInstance -SqlInstance $Witness -SqlCredential $WitnessSqlCredential
                    } catch {
                        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Witness -Continue
                    }
                }

                $dbName = $primarydb.Name

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Validating mirror setup"
                # Thanks to https://github.com/mmessano/PowerShell/blob/master/SQL-ConfigureDatabaseMirroring.ps1 for the tips

                $params.Database = $dbName
                $validation = Invoke-DbMirrorValidation @params

                if ((Test-Bound -ParameterName SharedPath) -and -not $validation.AccessibleShare) {
                    Stop-Function -Continue -Message "Cannot access $SharedPath from $($dest.Name)"
                }

                if (-not $validation.EditionMatch) {
                    Stop-Function -Continue -Message "This mirroring configuration is not supported. Because the principal server instance, $source, is $($source.EngineEdition) Edition, the mirror server instance must also be $($source.EngineEdition) Edition."
                }

                $badstate = $validation | Where-Object MirroringStatus -ne "none"
                if ($badstate) {
                    Stop-Function -Message "Cannot setup mirroring on database ($dbName) due to its current mirroring state on primary: $($badstate.MirroringStatus)" -Continue
                }

                if ($primarydb.Status -ne "Normal") {
                    Stop-Function -Message "Cannot setup mirroring on database ($dbName) due to its current state: $($primarydb.Status)" -Continue
                }

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Setting recovery model for $dbName on $($source.Name) to Full"

                if ($primarydb.RecoveryModel -ne "Full") {
                    if ((Test-Bound -ParameterName UseLastBackup)) {
                        Stop-Function -Message "$dbName not set to full recovery. UseLastBackup cannot be used."
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
                                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $primarydb -Continue
                            }
                        }
                    }

                    if ($Pscmdlet.ShouldProcess("$currentmirror", "Restoring full and log backups of $primarydb from $Primary")) {
                        foreach ($currentmirrorinstance in $currentmirror) {
                            try {
                                $null = $allbackups | Restore-DbaDatabase -SqlInstance $currentmirrorinstance -SqlCredential $MirrorSqlCredential -WithReplace -NoRecovery -TrustDbBackupHistory -EnableException
                            } catch {
                                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $dest -Continue
                            }
                        }
                    }

                    if ($SharedPath) {
                        Write-Message -Level Verbose -Message "Backups still exist on $SharedPath"
                    }
                }

                $currentmirrordb = Get-DbaDatabase -SqlInstance $dest -Database $dbName
                $primaryendpoint = Get-DbaEndpoint -SqlInstance $source | Where-Object EndpointType -eq DatabaseMirroring
                $currentmirrorendpoint = Get-DbaEndpoint -SqlInstance $dest | Where-Object EndpointType -eq DatabaseMirroring

                if (-not $primaryendpoint) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Setting up endpoint for primary"
                    $primaryendpoint = New-DbaEndpoint -SqlInstance $source -Type DatabaseMirroring -Role Partner -Name Mirroring -EncryptionAlgorithm $EncryptionAlgorithm -EndpointEncryption $EndpointEncryption
                    $null = $primaryendpoint | Stop-DbaEndpoint
                    $null = $primaryendpoint | Start-DbaEndpoint
                }

                if (-not $currentmirrorendpoint) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Setting up endpoint for mirror"
                    $currentmirrorendpoint = New-DbaEndpoint -SqlInstance $dest -Type DatabaseMirroring -Role Partner -Name Mirroring -EncryptionAlgorithm $EncryptionAlgorithm -EndpointEncryption $EndpointEncryption
                    $null = $currentmirrorendpoint | Stop-DbaEndpoint
                    $null = $currentmirrorendpoint | Start-DbaEndpoint
                }

                if ($witserver) {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Setting up endpoint for witness"
                    $witnessendpoint = Get-DbaEndpoint -SqlInstance $witserver | Where-Object EndpointType -eq DatabaseMirroring
                    if (-not $witnessendpoint) {
                        $witnessendpoint = New-DbaEndpoint -SqlInstance $witserver -Type DatabaseMirroring -Role Witness -Name Mirroring -EncryptionAlgorithm $EncryptionAlgorithm -EndpointEncryption $EndpointEncryption
                        $null = $witnessendpoint | Stop-DbaEndpoint
                        $null = $witnessendpoint | Start-DbaEndpoint
                    }
                }

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Granting permissions to service account"

                $serviceAccounts = $source.ServiceAccount, $dest.ServiceAccount, $witserver.ServiceAccount | Select-Object -Unique

                foreach ($account in $serviceAccounts) {
                    if ($account) {
                        if ($account -eq "LocalSystem" -and $source.HostPlatform -eq "Linux") {
                            $account = "NT AUTHORITY\SYSTEM"
                        }
                        if ($Pscmdlet.ShouldProcess("primary, mirror and witness (if specified)", "Creating login $account and granting CONNECT ON ENDPOINT")) {
                            if (-not (Get-DbaLogin -SqlInstance $source -Login $account)) {
                                $null = New-DbaLogin -SqlInstance $source -Login $account
                            }
                            if (-not (Get-DbaLogin -SqlInstance $dest -Login $account)) {
                                $null = New-DbaLogin -SqlInstance $dest -Login $account
                            }
                            try {
                                $null = $source.Query("GRANT CONNECT ON ENDPOINT::$primaryendpoint TO [$account]")
                                $null = $dest.Query("GRANT CONNECT ON ENDPOINT::$currentmirrorendpoint TO [$account]")
                                if ($witserver) {
                                    if (-not (Get-DbaLogin -SqlInstance $source -Login $account)) {
                                        $null = New-DbaLogin -SqlInstance $witserver -Login $account
                                    }
                                    $witserver.Query("GRANT CONNECT ON ENDPOINT::$witnessendpoint TO [$account]")
                                }
                            } catch {
                                Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                            }
                        }
                    }
                }

                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Starting endpoints if necessary"
                try {
                    $null = $primaryendpoint, $currentmirrorendpoint, $witnessendpoint | Start-DbaEndpoint -EnableException
                } catch {
                    Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                }

                try {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Setting up partner for mirror"
                    $null = $currentmirrordb | Set-DbaDbMirror -Partner $primaryendpoint.Fqdn -EnableException
                } catch {
                    Stop-Function -Message "Failure on mirror" -ErrorRecord $_ -Continue
                }

                try {
                    Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Setting up partner for primary"
                    $null = $primarydb | Set-DbaDbMirror -Partner $currentmirrorendpoint.Fqdn -EnableException
                } catch {
                    Stop-Function -Continue -Message "Failure on primary" -ErrorRecord $_
                }

                try {
                    if ($witnessendpoint) {
                        $null = $primarydb | Set-DbaDbMirror -Witness $witnessendpoint.Fqdn -EnableException
                    }
                } catch {
                    Stop-Function -Continue -Message "Failure with the new last part" -ErrorRecord $_
                }


                if ($Pscmdlet.ShouldProcess("console", "Showing results")) {
                    $results = [PSCustomObject]@{
                        Primary        = $Primary
                        Mirror         = $currentmirror
                        Witness        = $Witness
                        Database       = $primarydb.Name
                        ServiceAccount = $serviceAccounts
                        Status         = "Success"
                    }
                    if ($Witness) {
                        $results | Select-DefaultView -Property Primary, Mirror, Witness, Database, Status
                    } else {
                        $results | Select-DefaultView -Property Primary, Mirror, Database, Status
                    }
                }
            }
        }
    }
}