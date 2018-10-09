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

    .PARAMETER AutomatedBackupPreference
        Specifies how replicas in the primary role are treated in the evaluation to pick the desired replica to perform a backup.
    
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
    
    .PARAMETER FailureConditionLevel
        Specifies the different conditions that can trigger an automatic failover in Availability Group.
    
    .PARAMETER HealthCheckTimeout
        This setting used to specify the length of time, in milliseconds, that the SQL Server resource DLL should wait for information returned by the sp_server_diagnostics stored procedure before reporting the Always On Failover Cluster Instance (FCI) as unresponsive. 
        
        Changes that are made to the timeout settings are effective immediately and do not require a restart of the SQL Server resource.
    
        Defaults to 30000 (30 seconds).
    
    .PARAMETER Certificate 
        Specifies that the endpoint is to authenticate the connection using the certificate specified by certificate_name to establish identity for authorization. 
    
        The far endpoint must have a certificate with the public key matching the private key of the specified certificate.
    
    .PARAMETER BasicAvailabilityGroup
        Indicates whether the availability group is basic. Basic availability groups like pumpkin spice and uggs.    
    
        https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/basic-availability-groups-always-on-availability-groups
        
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
        Tags: HA
        Author: Chrissy LeMaire (@cl), netnerds.net
        dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
        
    .LINK
        https://dbatools.io/New-DbaAvailabilityGroup
        
    .EXAMPLE
        PS C:\> New-DbaAvailabilityGroup -Primary sql2016c -Name SharePoint
    
        Creates a new availability group on sql2016c named SharePoint
    
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
        [string]$Certificate,
        [switch]$BasicAvailabilityGroup,
        [ValidateSet('External', 'Wsfc', 'None')]
        [string]$ClusterType = 'External',
        [ValidateSet('None', 'Primary', 'Secondary', 'SecondaryOnly')]
        [string]$AutomatedBackupPreference = 'Secondary',
        [ValidateSet('OnAnyQualifiedFailureCondition', 'OnCriticalServerErrors', 'OnModerateServerErrors', 'OnServerDown', 'OnServerUnresponsive')]
        [string]$FailureConditionLevel = "OnServerDown",
        [ValidateSet('External', 'Wsfc', 'None')]
        [int]$HealthCheckTimeout = 30000,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$UseLastBackups,
        [switch]$Force,
        [switch]$Passthru,
        [switch]$EnableException
    )
    process {
        $stepCounter = 0
        if ($Force -and (-not $NetworkShare -and -not $UseLastBackups)) {
            Stop-Function -Message "NetworkShare or UseLastBackups is required when Force is used"
            return
        }
        
        try {
            $server = Connect-SqlInstance -SqlInstance $Primary -SqlCredential $PrimarySqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Primary -Continue
        }
        
        if ($Certificate) {
            $cert = Get-DbaDbCertificate -SqlInstance $server -Certificate $Certificate
            if (-not $cert) {
                Stop-Function -Message "Certificate $Certificate does not exist on $Primary" -ErrorRecord $_ -Target $Certificate -Continue
            }
        }
        
        if (($NetworkShare)) {
            if (-not (Test-DbaPath -SqlInstance $server -Path $NetworkShare)) {
                Stop-Function -Continue -Message "Cannot access $NetworkShare from $Primary"
            }
        }
        
        if ($Secondary) {
            $secondaries = @()
            foreach ($computer in $Secondary) {
                try {
                    $secondaries += Connect-SqlInstance -SqlInstance $computer -SqlCredential $SecondarySqlCredential
                }
                catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Primary -Continue
                }
            }
        }
        
        # database stuff
        if ($Database) {
            $InputObject += Get-DbaDatabase -SqlInstance $server -Database $Database
        }
        
        foreach ($primarydb in $InputObject) {
            if ($primarydb.MirroringStatus -ne "None") {
                Stop-Function -Continue -Message "Cannot setup mirroring on database ($dbname) due to its current mirroring state: $($primarydb.MirroringStatus)"
            }
            
            if ($primarydb.Status -ne "Normal") {
                Stop-Function -Continue -Message "Cannot setup mirroring on database ($dbname) due to its current state: $($primarydb.Status)"
            }
            
            if ($primarydb.RecoveryModel -ne "Full") {
                if ((Test-Bound -ParameterName UseLastBackups)) {
                    Stop-Function -Continue -Message "$dbName not set to full recovery. UseLastBackups cannot be used."
                }
                else {
                    Set-DbaDbRecoveryModel -SqlInstance $server -Database $primarydb.Name -RecoveryModel Full
                }
            }
        }
        
        # Start work
        try {
            $ag = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroup -ArgumentList $server, $Name
            $replica = Add-DbaAgReplica -SqlInstance $server -InputObject $ag -EnableException
            $ag.AutomatedBackupPreference = [Microsoft.SqlServer.Management.Smo.AvailabilityGroupAutomatedBackupPreference]::$AutomatedBackupPreference
            $ag.FailureConditionLevel = [Microsoft.SqlServer.Management.Smo.AvailabilityGroupFailureConditionLevel]::$FailureConditionLevel
            $ag.HealthCheckTimeout = $HealthCheckTimeout
            $ag.BasicAvailabilityGroup = $BasicAvailabilityGroup
            
            if ($PassThru) {
                $defaults = 'LocalReplicaRole', 'Name as AvailabilityGroup', 'PrimaryReplicaServerName as PrimaryReplica', 'AutomatedBackupPreference', 'AvailabilityReplicas', 'AvailabilityDatabases', 'AvailabilityGroupListeners'
                return (Select-DefaultView -InputObject $ag -Property $defaults)
            }
            $ag.Create()
        }
        catch {
            $msg = $_.Exception.InnerException.InnerException.Message
            if (-not $msg) {
                $msg = $_
            }
            Stop-Function -Message $msg -ErrorRecord $_ -Target $Primary
            return
        }
        
        # Add permissions
        foreach ($second in $secondaries) {
            $serviceaccounts = $server.ServiceAccount, $second.ServiceAccount, $witserver.ServiceAccount | Select-Object -Unique
            
            foreach ($account in $serviceaccounts) {
                if ($Pscmdlet.ShouldProcess("All involved servers", "Creating login $account and granting CONNECT ON ENDPOINT")) {
                    $null = New-DbaLogin -SqlInstance $server -Login $account -WarningAction SilentlyContinue
                    try {
                        $null = $server.Query("GRANT CONNECT ON ENDPOINT::$primaryendpoint TO [$account]")
                        foreach ($second in $secondaries) {
                            $null = New-DbaLogin -SqlInstance $second -Login $account -WarningAction SilentlyContinue
                            $null = $second.Query("GRANT CONNECT ON ENDPOINT::$secondaryendpoint TO [$account]")
                        }
                    }
                    catch {
                        Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                    }
                }
            }
        }
        
        # Add databases
        foreach ($second in $secondaries) {
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
                    # keep going to ensure output is shown even if dbs aren't added well.
                    $null = $allbackups | Restore-DbaDatabase -SqlInstance $Secondary -SqlCredential $SecondarySqlCredential -WithReplace -NoRecovery -TrustDbBackupHistory
                }
            }
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Starting endpoints if necessary"
            try {
                $null = $primaryendpoint, $secondaryendpoint | Start-DbaEndpoint -EnableException
            }
            catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_
            }
        }
        
        # Add replica
        # Add databases
        
        Get-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $Name
        
        foreach ($second in $secondaries) {
            Get-DbaAvailabilityGroup -SqlInstance $second -AvailabilityGroup $Name
        }
    }
}