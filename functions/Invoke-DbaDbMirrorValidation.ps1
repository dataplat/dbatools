#ValidationTags#Messaging,FlowControl,CodeStyle#
function Invoke-DbaDbMirrorValidation {
    <#
        .SYNOPSIS
            Gets SQL Endpoint(s) information for each instance(s) of SQL Server.

        .DESCRIPTION
            The Set-DbaDbMirror command gets SQL Endpoint(s) information for each instance(s) of SQL Server.

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
    
        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Mirror
            Author: Chrissy LeMaire (@cl), netnerds.net
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Invoke-DbaDbMirrorValidation

        .EXAMPLE
            $params = @{
                    Primary = 'sql2017a'
                    Mirror = 'sql2017b'
                    MirrorSqlCredential = 'sqladmin'
                    Witness = 'sql2019'
                    Database = 'onthewall'
                    NetworkShare = '\\nas\sql\share'
                }
            
            Invoke-DbaDbMirrorValidation @params
        
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
        [parameter(Mandatory)]
        [string]$NetworkShare,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName Primary) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }
        
        $InputObject += Get-DbaDatabase -SqlInstance $Primary -SqlCredential $SqlCredential -Database $Database
        
        foreach ($db in $InputObject) {
            $server = $db.Parent
            $dbname = $db.Name
            $canmirror = $true
            
            if (Test-Bound -ParameterName Witness) {
                try {
                    $witserver = Connect-SqlInstance -SqlInstance $Witness -SqlCredential $WitnessSqlCredential
                    $witdb = Get-DbaDatabase -SqlInstance $Witness -SqlCredential $WitnessSqlCredential -Database $db.Name
                    $wexists = $true
                    
                    if ($witdb) {
                        $witexists = $true
                    }
                    else {
                        Write-Message -Level Verbose -Message "Database ($dbname) exists on witness server"
                        $canmirror = $false
                        $witexists = $false
                    }
                }
                catch {
                    $wexists = $false
                    $canmirror = $false
                }
            }
            
            if ($db.MirroringStatus -ne [Microsoft.SqlServer.Management.Smo.MirroringStatus]::None) {
                Write-Message -Level Verbose -Message "Cannot setup mirroring on database ($dbname) due to its current mirroring state: $($db.MirroringStatus)"
                $canmirror = $false
            }
            
            if ($db.Status -ne [Microsoft.SqlServer.Management.Smo.DatabaseStatus]::Normal) {
                Write-Message -Level Verbose -Message "Cannot setup mirroring on database ($dbname) due to its current Status: $($db.Status)"
                $canmirror = $false
            }
            
            $destdb = Get-DbaDatabase -SqlInstance $Mirror -SqlCredential $MirrorSqlCredential -Database $db.Name
            
            if ($destdb) {
                $exists = $true
            }
            else {
                Write-Message -Level Verbose -Message "Database ($dbname) does not exist on mirror server"
                $canmirror = $false
                $exists = $false
            }
            
            if (-not (Test-DbaPath -SqlInstance $destdb.Parent -Path $NetworkShare)) {
                Write-Message -Level Verbose -Message "Cannot access $NetworkShare from $($destdb.Parent.Name)"
                $canmirror = $false
                $nexists = $false
            }
            else {
                $nexists = $true
            }
            
            if ($server.EngineEdition -ne $destdb.Parent.EngineEdition) {
                Write-Message -Level Verbose -Message "This mirroring configuration is not supported. Because the principal server instance, $server, is $($server.EngineEdition) Edition, the mirror server instance must also be $($server.EngineEdition) Edition."
                $canmirror = $false
                $edition = $false
            }
            else {
                $edition = $true
            }
            
            $results = [pscustomobject]@{
                Primary  = $Primary
                Mirror   = $Mirror
                Witness  = $Witness
                Database = $db.Name
                MirroringStatus = $db.MirroringStatus
                State    = $db.Status
                DatabaseExistsOnMirror = $exists
                DatabaseExistsOnWitness = $witexists
                OnlineWitness = $wexists
                EditionMatch = $edition
                AccessibleShare = $nexists
                ValidationPassed = $canmirror
            }
            
            if ((Test-Bound -ParameterName Witness)) {
                $results | Select-DefaultView -Property Primary, Mirror, Witness, Database, MirroringStatus, State, DatabaseExistsOnMirror, OnlineWitness, DatabaseExistsOnWitness, EditionMatch, AccessibleShare, ValidationPassed
            }
            else {
                $results | Select-DefaultView -Property Primary, Mirror, Database, MirroringStatus, State, DatabaseExistsOnMirror, EditionMatch, AccessibleShare, ValidationPassed
            }
        }
    }
}