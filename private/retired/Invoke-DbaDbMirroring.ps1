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
        Specifies the SQL Server instance that will serve as the primary (principal) server in the mirroring partnership.
        Use this when setting up mirroring from scratch rather than piping database objects from Get-DbaDatabase.
        Must be paired with the Database parameter to identify which databases to mirror.

    .PARAMETER PrimarySqlCredential
        Alternative credentials for connecting to the primary SQL Server instance.
        Required when the current user context doesn't have sufficient permissions on the primary server.
        Accepts PowerShell credential objects created with Get-Credential for SQL Authentication or domain accounts.

    .PARAMETER Mirror
        Specifies the SQL Server instance(s) that will serve as the mirror server(s) in the mirroring partnership.
        This is where the mirrored database copies will be created and maintained.
        Supports multiple mirror instances for creating mirror partnerships with different servers.

    .PARAMETER MirrorSqlCredential
        Alternative credentials for connecting to the mirror SQL Server instance(s).
        Required when the current user context doesn't have sufficient permissions on the mirror server.
        Accepts PowerShell credential objects created with Get-Credential for SQL Authentication or domain accounts.

    .PARAMETER Witness
        Specifies the SQL Server instance that will serve as the witness server for automatic failover scenarios.
        Optional parameter that enables high safety mode with automatic failover when all three servers can communicate.
        Leave empty if you only need high safety mode without automatic failover or high performance mode.

    .PARAMETER WitnessSqlCredential
        Alternative credentials for connecting to the witness SQL Server instance.
        Required when the current user context doesn't have sufficient permissions on the witness server.
        Accepts PowerShell credential objects created with Get-Credential for SQL Authentication or domain accounts.

    .PARAMETER Database
        Specifies which database(s) on the primary server to set up for mirroring.
        Required when using the Primary parameter instead of piping from Get-DbaDatabase.
        Supports multiple database names to set up mirroring for several databases in a single operation.

    .PARAMETER SharedPath
        Network share path accessible by all SQL Server service accounts for backup and restore operations.
        Required when the mirror database doesn't exist and needs to be initialized from backups.
        Must have read/write permissions for the service accounts running SQL Server on primary and mirror instances.

    .PARAMETER InputObject
        Accepts database objects piped from Get-DbaDatabase to set up mirroring for specific databases.
        Use this approach when you want to filter databases first or work with existing database objects.
        Alternative to using the Primary and Database parameters.

    .PARAMETER UseLastBackup
        Uses the most recent full and log backups from the primary server to initialize the mirror database.
        Avoids creating new backups when recent ones already exist and are sufficient for mirroring setup.
        Requires the primary database to be in Full recovery model with existing backup history.

    .PARAMETER Force
        Drops and recreates the mirror database even if it already exists, using fresh backups from the primary.
        Use this when you need to completely reinitialize mirroring or when the existing mirror database is corrupted.
        Requires either SharedPath for new backups or UseLastBackup to use existing ones.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER EndpointEncryption
        Controls the encryption requirement for database mirroring endpoints created during setup.
        Default is 'Required' which enforces encrypted communication between all mirroring partners.
        Use 'Supported' to allow both encrypted and unencrypted connections, or 'Disabled' to prevent encryption.

    .PARAMETER EncryptionAlgorithm
        Specifies the encryption algorithm used by database mirroring endpoints for secure communication.
        Default is 'Aes' which provides strong encryption with good performance.
        Consider 'AesRC4' or 'RC4Aes' for compatibility with older SQL Server versions in mixed environments.

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

    .OUTPUTS
        PSCustomObject

        Returns one object per database successfully configured for mirroring, containing configuration summary information for the mirroring partnership.

        Default display properties (via Select-DefaultView):

        Without witness server:
        - Primary: The SQL Server instance serving as the primary (principal) server
        - Mirror: The SQL Server instance serving as the mirror server
        - Database: The name of the database configured for mirroring
        - Status: Status of the mirroring setup (Success indicates successful configuration)

        With witness server:
        - Primary: The SQL Server instance serving as the primary (principal) server
        - Mirror: The SQL Server instance serving as the mirror server
        - Witness: The SQL Server instance configured as the witness server for automatic failover
        - Database: The name of the database configured for mirroring
        - Status: Status of the mirroring setup (Success indicates successful configuration)

        Additional properties available (from PSCustomObject):
        - ServiceAccount: String array of SQL Server service accounts that were granted CONNECT permissions on the mirroring endpoints

        Output occurs only when the ShouldProcess block executes successfully. Multiple objects are returned when mirroring is configured for multiple databases or to multiple mirror instances.

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