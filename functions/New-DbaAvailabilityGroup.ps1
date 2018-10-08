#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function New-DbaAvailabilityGroup {
<#
    .SYNOPSIS
        Automates the creation of database mirrors.
        
    .DESCRIPTION
        Automates the creation of database mirrors.
        
        * Verifies that a secondary is possible
        * Sets the recovery model to Full if needed
        * If the database does not exist on secondary or witness, a backup/restore is performed
        * Sets up endpoints if necessary
        * Creates a login and grants permissions to service accounts if needed
        * Starts endpoints if needed
        * Sets up partner for secondary
        * Sets up partner for primary
        * Sets up witness if one is specified
        
        NOTE: If a backup / restore is performed, the backups will be left in tact on the network share.
        
        Thanks for this, Thomas Stringer! https://blogs.technet.microsoft.com/heyscriptingguy/2013/04/29/set-up-an-alwayson-availability-group-with-powershell/

    .PARAMETER Primary
        SQL Server name or SMO object representing the primary SQL Server.
        
    .PARAMETER PrimarySqlCredential
        Login to the primary instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)
        
    .PARAMETER Secondary
        SQL Server name or SMO object representing secondary SQL Servers.
        
    .PARAMETER SecondarySqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)
      
    .PARAMETER Name
        The Name of the Availability Group
    
    .PARAMETER Database
        The database or databases to add.
        
    .PARAMETER NetworkShare
        The network share where the backups will be backed up and restored from.
        
        Each SQL Server service account must have access to this share.
        
        NOTE: If a backup / restore is performed, the backups will be left in tact on the network share.
    
    .PARAMETER IPAddress
        Sets the IP address of the availability group listener.
    
    .PARAMETER SubnetMask
        Sets the subnet IP mask of the availability group listener.
    
    .PARAMETER Port
        Sets the number of the port used to communicate with the availability group.
    
    .PARAMETER Dhcp
        Indicates whether the object is DHCP.
    
    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase.
        
    .PARAMETER UseLastBackups
        Use the last full backup of database.
    
    .PARAMETER DtcSupport
        Indicates whether the DtcSupport is enabled

    .PARAMETER ClusterType
        Cluster type of the Availability Group.
        Options include: External, Wsfc or None. External by default.
    
    .PARAMETER Force
        Drop and recreate the database on remote servers using fresh backup.
        
    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.
        
    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.
        
    .PARAMETER Passthru
        Don't create the availability group, just pass thru an object that can be further customized before creation.
    
    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
        
    .NOTES
        Tags: Secondary, HA
        Author: Chrissy LeMaire (@cl), netnerds.net
        dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
        
    .LINK
        https://dbatools.io/New-DbaAvailabilityGroup
        
    .EXAMPLE
        PS C:\> $params = @{
        >>    Primary = 'sql2017a'
        >>    Secondary = 'sql2017b'
        >>    SecondarySqlCredential = 'sqladmin'
        >>    Witness = 'sql2019'
        >>    Database = 'pubs'
        >>    NetworkShare = '\\nas\sql\share'
        >>}
        
        PS C:\> Invoke-DbaDbMirror @params
        
        Performs a bunch of checks to ensure the pubs database on sql2017a
        can be mirrored from sql2017a to sql2017b. Logs in to sql2019 and sql2017a
        using Windows credentials and sql2017b using a SQL credential.
        
        Prompts for confirmation for most changes. To avoid confirmation, use -Confirm:$false or
        use the syntax in the second example.
        
    .EXAMPLE
        PS C:\> $params = @{
        >> Primary = 'sql2017a'
        >> Secondary = 'sql2017b'
        >> SecondarySqlCredential = 'sqladmin'
        >> Witness = 'sql2019'
        >> Database = 'pubs'
        >> NetworkShare = '\\nas\sql\share'
        >> Force = $true
        >> Confirm = $false
        >> }
        
        PS C:\> Invoke-DbaDbMirror @params
        
        Performs a bunch of checks to ensure the pubs database on sql2017a
        can be mirrored from sql2017a to sql2017b. Logs in to sql2019 and sql2017a
        using Windows credentials and sql2017b using a SQL credential.
        
        Drops existing pubs database on Secondary and Witness and restores them with
        a fresh backup.
        
        Does all the things in the decription, does not prompt for confirmation.
        
    .EXAMPLE
        PS C:\> $map = @{ 'database_data' = 'M:\Data\database_data.mdf' 'database_log' = 'L:\Log\database_log.ldf' }
        PS C:\> Get-ChildItem \\nas\seed | Restore-DbaDatabase -SqlInstance sql2017b -FileMapping $map -NoRecovery
        PS C:\> Get-DbaDatabase -SqlInstance sql2017a -Database pubs | New-DbaAvailabilityGroup -Secondary sql2017b -Confirm:$false
        
        Restores backups from sql2017a to a specific file struture on sql2017b then creates secondary with no prompts for confirmation.
        
    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017a -Database pubs |
        >> New-DbaAvailabilityGroup -Secondary sql2017b -UseLastBackups -Confirm:$false
        
        Mirrors pubs on sql2017a to sql2017b and uses the last full and logs from sql2017a to seed.
#>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter]$Primary,
        [PSCredential]$PrimarySqlCredential,
        [DbaInstanceParameter[]]$Secondary,
        [PSCredential]$SecondarySqlCredential,
        [string]$Name,
        [string[]]$Database,
        [string]$NetworkShare,
        [ipaddress[]]$IPAddress,
        [ipaddress]$SubnetMask,
        [int]$Port,
        [switch]$Dhcp,
        [switch]$DtcSupport,
        [ValidateSet('External', 'Wsfc', 'None')]
        [string]$ClusterType = 'External',
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$UseLastBackups,
        [switch]$Force,
        [switch]$Passthru,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName Primary) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }
        
        if ($Force -and (-not $NetworkShare -and -not $UseLastBackups)) {
            Stop-Function -Message "NetworkShare or UseLastBackups is required when Force is used"
            return
        }
        
        try {
            $source = Connect-SqlInstance -SqlInstance $Primary -SqlCredential $PrimarySqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Primary -Continue
        }
        
        if ($Certificate) {
            $cert = Get-DbaDbCertificate -SqlInstance $source -Certificate $Certificate
            if (-not $cert) {
                Stop-Function -Message "Certificate $Certificate does not exist on $Primary" -ErrorRecord $_ -Target $Certificate -Continue
            }
        }
        
        if ((Test-Bound -ParameterName NetworkShare)) {
            if (-not (Test-DbaPath -SqlInstance $source -Path $NetworkShare)) {
                Stop-Function -Continue -Message "Cannot access $NetworkShare from $($dest.Name)"
            }
        }
        
        if ($Database) {
            $InputObject += Get-DbaDatabase -SqlInstance $source -Database $Database
        }
        
        Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Validating secondary setup"
        
        foreach ($primarydb in $InputObject) {
            if ($primarydb.MirroringStatus -ne "None") {
                Stop-Function -Continue -Message "Cannot setup mirroring on database ($dbname) due to its current mirroring state: $($primarydb.MirroringStatus)"
            }
            
            if ($primarydb.Status -ne "Normal") {
                Stop-Function -Continue -Message "Cannot setup mirroring on database ($dbname) due to its current state: $($primarydb.Status)"
            }
        }
        
        $ag = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroup -ArgumentList $source, $Name
        
        if ($PassThru) {
            return $ag
        }
        
        Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Setting recovery model for $dbName on $($source.Name) to Full"
        
        if ($primarydb.RecoveryModel -ne "Full") {
            if ((Test-Bound -ParameterName UseLastBackups)) {
                Stop-Function -Continue -Message "$dbName not set to full recovery. UseLastBackups cannot be used."
            }
            else {
                Set-DbaDbRecoveryModel -SqlInstance $source -Database $primarydb.Name -RecoveryModel Full
            }
        }
        
        foreach ($second in $Secondary) {
            $stepCounter = 0
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Connecting to SQL Servers"
            
            try {
                $dest = Connect-SqlInstance -SqlInstance $second -SqlCredential $SecondarySqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $second -Continue
            }
            
            $primaryendpoint = Get-DbaEndpoint -SqlInstance $source | Where-Object EndpointType -eq DatabaseMirroring
            $mirrorendpoint = Get-DbaEndpoint -SqlInstance $dest | Where-Object EndpointType -eq DatabaseMirroring
            
            if (-not $primaryendpoint) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Setting up endpoint for primary"
                $primaryendpoint = New-DbaEndpoint -SqlInstance $source -Type DatabaseMirroring -Role Partner -Name Mirroring -EncryptionAlgorithm Aes
                $null = $primaryendpoint | Stop-DbaEndpoint
                $null = $primaryendpoint | Start-DbaEndpoint
            }
            
            if (-not $mirrorendpoint) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Setting up endpoint for secondary"
                $mirrorendpoint = New-DbaEndpoint -SqlInstance $dest -Type DatabaseMirroring -Role Partner -Name Mirroring -EncryptionAlgorithm RC4
                $null = $mirrorendpoint | Stop-DbaEndpoint
                $null = $mirrorendpoint | Start-DbaEndpoint
            }
            
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Granting permissions to service account"
            
            $serviceaccounts = $source.ServiceAccount, $dest.ServiceAccount, $witserver.ServiceAccount | Select-Object -Unique
            
            foreach ($account in $serviceaccounts) {
                if ($Pscmdlet.ShouldProcess("primary, secondary and witness (if specified)", "Creating login $account and granting CONNECT ON ENDPOINT")) {
                    $null = New-DbaLogin -SqlInstance $source -Login $account -WarningAction SilentlyContinue
                    $null = New-DbaLogin -SqlInstance $dest -Login $account -WarningAction SilentlyContinue
                    try {
                        $null = $source.Query("GRANT CONNECT ON ENDPOINT::$primaryendpoint TO [$account]")
                        $null = $dest.Query("GRANT CONNECT ON ENDPOINT::$mirrorendpoint TO [$account]")
                        if ($witserver) {
                            $null = New-DbaLogin -SqlInstance $witserver -Login $account -WarningAction SilentlyContinue
                            $witserver.Query("GRANT CONNECT ON ENDPOINT::$witnessendpoint TO [$account]")
                        }
                    }
                    catch {
                        Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                    }
                }
            }
        }
        
        foreach ($second in $Secondary) {
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Copying $dbName from primary to secondary"
            
            if (-not $validation.DatabaseExistsOnMirror -or $Force) {
                if ($UseLastBackups) {
                    $allbackups = Get-DbaBackupHistory -SqlInstance $primarydb.Parent -Database $primarydb.Name -IncludeCopyOnly -Last
                }
                else {
                    $fullbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $NetworkShare -Type Full
                    $logbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $NetworkShare -Type Log
                    $allbackups = $fullbackup, $logbackup
                }
                Write-Message -Level Verbose -Message "Backups still exist on $NetworkShare"
                if ($Pscmdlet.ShouldProcess("$Secondary", "restoring full and log backups of $primarydb from $Primary")) {
                    try {
                        $null = $allbackups | Restore-DbaDatabase -SqlInstance $Secondary -SqlCredential $SecondarySqlCredential -WithReplace -NoRecovery -TrustDbBackupHistory -EnableException
                    }
                    catch {
                        $msg = $_.Exception.InnerException.InnerException.InnerException.InnerException.Message
                        if (-not $msg) {
                            $msg = $_.Exception.InnerException.InnerException.InnerException.Message
                        }
                        if (-not $msg) {
                            $msg = $_
                        }
                        Stop-Function -Message $msg -ErrorRecord $_ -Target $dest -Continue
                    }
                }
            }
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Starting endpoints if necessary"
            try {
                $null = $primaryendpoint, $mirrorendpoint | Start-DbaEndpoint -EnableException
            }
            catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_
            }
        }
        
        foreach ($second in $Secondary) {
            try {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Setting up partner for secondary"
                $null = $mirrordb | Set-DbaDbMirror -Partner $primaryendpoint.Fqdn -EnableException
            }
            catch {
                Stop-Function -Continue -Message "Failure on secondary" -ErrorRecord $_
            }
            
            try {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Setting up partner for primary"
                $null = $primarydb | Set-DbaDbMirror -Partner $mirrorendpoint.Fqdn -EnableException
            }
            catch {
                Stop-Function -Continue -Message "Failure on primary" -ErrorRecord $_
            }
            
        }
        
        # add replica
        # add databases
        
        if ($Pscmdlet.ShouldProcess("console", "Showing results")) {
            [pscustomobject]@{
                Primary   = $Primary
                Secondary = $Secondary
                Witness   = $Witness
                Database  = $primarydb.Name
                Status    = "Success"
            } | Select-DefaultView -Property Primary, Secondary, Database, Status
        }
    }
}