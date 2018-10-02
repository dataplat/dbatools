#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Invoke-DbaDbMirroring {
    <#
        .SYNOPSIS
            Gets SQL Endpoint(s) information for each instance(s) of SQL Server.

        .DESCRIPTION
            Creates a new mirror for some dbs

            Thanks to https://github.com/mmessano/PowerShell/blob/master/SQL-ConfigureDatabaseMirroring.ps1
    
        .PARAMETER Primary
            SQL Server name or SMO object representing the primary SQL Server.

        .PARAMETER PrimarySqlCredential
            Login to the primary instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Mirror
            SQL Server name or SMO object representing the mirror SQL Server.

        .PARAMETER MirrorSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Witness
            SQL Server name or SMO object representing the witness SQL Server.

        .PARAMETER WitnessSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)
    
        .PARAMETER Database
                The database or databases to mirror
    
        .PARAMETER NetworkShare
                The network share where the backups will be
    
        .PARAMETER InputObject
                Enables piping from Get-DbaDatabase
  
        .PARAMETER UseLastBackups
                Use the last full backup of database
  
        .PARAMETER Force
                Drop and recreate the database on remote servers using fresh backup
    
        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Mirror, HA
            Author: Chrissy LeMaire (@cl), netnerds.net
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT
            
            TODO: add service accounts

        .LINK
            https://dbatools.io/Invoke-DbaDbMirroring

        .EXAMPLE
            $params = @{
                    Primary = 'sql2017a'
                    Mirror = 'sql2017b'
                    MirrorSqlCredential = 'sqladmin'
                    Witness = 'sql2019'
                    Database = 'onthewall'
                    NetworkShare = '\\nas\sql\share'
                }
    
            Invoke-DbaDbMirroring @params
        
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter]$Primary,
        [PSCredential]$PrimarySqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Mirror,
        [PSCredential]$MirrorSqlCredential,
        [DbaInstanceParameter]$Witness,
        [PSCredential]$WitnessSqlCredential,
        [string[]]$Database,
        [string]$NetworkShare,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$UseLastBackups,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        $params = $PSBoundParameters
        $null = $params.Remove('UseLastBackups')
        $null = $params.Remove('Force')
        $totalSteps = 10
        $Activity = "Setting up mirroring"
    }
    process {
        if ((Test-Bound -ParameterName Primary) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }
        
        if ($Force -and (Test-Bound -Not -ParameterName NetworkShare) -and (Test-Bound -Not -ParameterName UseLastBackups)) {
            Stop-Function -Message "NetworkShare or UseLastBackups is required when Force is used"
            return
        }
        
        $InputObject += Get-DbaDatabase -SqlInstance $Primary -SqlCredential $PrimarySqlCredential -Database $Database
        
        foreach ($primarydb in $InputObject) {
            $stepCounter = 0
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Connecting to SQL Servers"
            $source = $primarydb.Parent
            $dest = Connect-DbaInstance -SqlInstance $Mirror -Credential $MirrorSqlCredential
            if ($Witness) {
                $witserver = Connect-DbaInstance -SqlInstance $Witness -Credential $WitnessSqlCredential
            }
            
            $dbName = $primarydb.Name
            
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Validating mirror setup"
            $validation = Invoke-DbaDbMirrorValidation @params
            
            if ((Test-Bound -ParameterName NetworkShare) -and -not $validation.AccessibleShare) {
                Stop-Function -Continue -Message "Cannot access $NetworkShare from $($dest.Name)"
            }
            
            if (-not $validation.EditionMatch) {
                Stop-Function -Continue -Message "This mirroring configuration is not supported. Because the principal server instance, $source, is $($source.EngineEdition) Edition, the mirror server instance must also be $($source.EngineEdition) Edition."
            }
            
            if ($validation.MirroringStatus -ne "None") {
                Stop-Function -Continue -Message "Cannot setup mirroring on database ($dbname) due to its current mirroring state: $($primarydb.MirroringStatus)"
            }
            if ($primarydb.Status -ne "Normal") {
                Stop-Function -Continue -Message "Cannot setup mirroring on database ($dbname) due to its current state: $($primarydb.Status)"
            }
            
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Setting recovery model for $dbName on $($source.Name) to Full"
            
            if ($primarydb.RecoveryModel -ne "Full") {
                if ((Test-Bound -ParameterName UseLastBackups)) {
                    Stop-Function -Continue -Message "$dbName not set to full recovery. UseLastBackups cannot be used."
                }
                else {
                    Set-DbaDbRecoveryModel -SqlInstance $source -Database $primarydb.Name -RecoveryModel Full -Confirm:$false
                }
            }
            
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Copying $dbName from primary to mirror"
            
            if (-not $validation.DatabaseExistsOnMirror -or $Force) {
                $fullbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $NetworkShare -Type Full
                $logbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $NetworkShare -Type Log
                $null = $fullbackup, $logbackup | Restore-DbaDatabase -SqlInstance $dest -WithReplace
            }
            
            $mirrordb = Get-DbaDatabase -SqlInstance $dest -Database $dbName
            
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Copying $dbName from primary to witness"
            
            if ($Witness -and (-not $validation.DatabaseExistsOnWitness -or $Force)) {
                if (-not $fullbackup) {
                    $fullbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $NetworkShare -Type Full
                    $logbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $NetworkShare -Type Log
                }
                $null = $fullbackup, $logbackup | Restore-DbaDatabase -SqlInstance $witserver -WithReplace
            }
            
            if ($Witness) {
                $witnessdb = Get-DbaDatabase -SqlInstance $witserver -Database $dbName
            }
            
            $primaryendpoint = Get-DbaEndpoint -SqlInstance $source | Where-Object EndpointType -eq DatabaseMirroring
            $mirrorendpoint = Get-DbaEndpoint -SqlInstance $dest | Where-Object EndpointType -eq DatabaseMirroring
            
            if (-not $primaryendpoint) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Setting up endpoint for primary"
                $primaryendpoint = New-DbaEndpoint -SqlInstance $source -Type DatabaseMirroring -Role Partner
                $null = $primaryendpoint | Stop-DbaEndpoint
                $null = $primaryendpoint | Start-DbaEndpoint
            }
            
            if (-not $mirrorendpoint) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Setting up endpoint for mirror"
                $mirrorendpoint = New-DbaEndpoint -SqlInstance $dest -Type DatabaseMirroring -Role Partner
                $null = $mirrorendpoint | Stop-DbaEndpoint
                $null = $mirrorendpoint | Start-DbaEndpoint
            }
            
            if ($witserver) {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Setting up endpoint for witness"
                $witnessendpoint = Get-DbaEndpoint -SqlInstance $witserver | Where-Object EndpointType -eq DatabaseMirroring
                if (-not $witnessendpoint) {
                    $witnessendpoint = New-DbaEndpoint -SqlInstance $witserver -Type DatabaseMirroring -Role Witness
                    $null = $witnessendpoint | Stop-DbaEndpoint
                    $null = $witnessendpoint | Start-DbaEndpoint
                }
            }
            
            Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Starting endpoints if necessary"
            try {
                $null = $primaryendpoint, $mirrorendpoint, $witnessendpoint | Start-DbaEndpoint
            }
            catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_
            }
            
            try {
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Setting up partner for primary"
                $primarydb | Set-DbaDbMirror -Partner $mirrorendpoint.Fqdn
                Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Setting up partner for mirror"
                $mirrordb | Set-DbaDbMirror -Partner $primaryendpoint.Fqdn
                
                if ($witnessdb) {
                    Write-ProgressHelper -TotalSteps $totalSteps -Activity $activity -StepNumber ($stepCounter++) -Message "Setting up partner for witness"
                    $witnessdb | Set-DbaDbMirror -Witness $primaryendpoint.Fqdn
                }
            }
            catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_
            }
            
            $results = [pscustomobject]@{
                Primary  = $Primary
                Mirror   = $Mirror
                Witness  = $Witness
                Database = $primarydb.Name
                Status   = "Success"
            }
            
            if ($Witness) {
                $results
            }
            else {
                $results | Select-DefaultView -ExcludeProperty Witness
            }
        }
    }
}