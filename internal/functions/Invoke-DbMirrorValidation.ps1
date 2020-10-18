function Invoke-DbMirrorValidation {
    <#
        .SYNOPSIS
            Validates if a mirror is ready

        .DESCRIPTION
            Validates if a mirror is ready

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

        .PARAMETER SharedPath
                The network share where the backups will be

        .PARAMETER InputObject
                Enables piping from Get-DbaDatabase

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Mirror, HA
            Author: Chrissy LeMaire (@cl), netnerds.net
            dbatools PowerShell module (https://dbatools.io)
           Copyright: (c) 2018 by dbatools, licensed under MIT
            License: MIT https://opensource.org/licenses/MIT
        .EXAMPLE
            PS C:\> $params = @{
                    Primary = 'sql2017a'
                    Mirror = 'sql2017b'
                    MirrorSqlCredential = 'sqladmin'
                    Witness = 'sql2019'
                    Database = 'onthewall'
                    SharedPath = '\\nas\sql\share'
                }

            PS C:\> Invoke-DbMirrorValidation @params

            Do things

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter]$Primary,
        [PSCredential]$PrimarySqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Mirror,
        [PSCredential]$MirrorSqlCredential,
        [DbaInstanceParameter]$Witness,
        [PSCredential]$WitnessSqlCredential,
        [string[]]$Database,
        [string]$SharedPath,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName Primary) -and (Test-Bound -Not -ParameterName Database)) {
            Stop-Function -Message "Database is required when SqlInstance is specified"
            return
        }

        if ($Primary) {
            $InputObject += Get-DbaDatabase -SqlInstance $Primary -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            $dbName = $db.Name
            $canmirror = $true
            $dest = Connect-DbaInstance -SqlInstance $Mirror -SqlCredential $MirrorSqlCredential

            $endpoints = @()
            $endpoints += Get-DbaEndpoint -SqlInstance $server | Where-Object EndpointType -eq DatabaseMirroring
            $endpoints += Get-DbaEndpoint -SqlInstance $dest | Where-Object EndpointType -eq DatabaseMirroring

            if (Test-Bound -ParameterName Witness) {
                try {
                    $witserver = Connect-DbaInstance -SqlInstance $Witness -SqlCredential $WitnessSqlCredential
                    $endpoints += Get-DbaEndpoint -SqlInstance $witserver | Where-Object EndpointType -eq DatabaseMirroring
                    $witdb = Get-DbaDatabase -SqlInstance $witserver -Database $db.Name
                    $wexists = $true

                    if ($witdb.Status -ne 'Restoring') {
                        $canmirror = $false
                    }

                    if ($witdb) {
                        $witexists = $true
                    } else {
                        Write-Message -Level Verbose -Message "Database ($dbName) exists on witness server"
                        $canmirror = $false
                        $witexists = $false
                    }
                } catch {
                    $wexists = $false
                    $canmirror = $false
                }
            }

            if ($db.MirroringStatus -ne [Microsoft.SqlServer.Management.Smo.MirroringStatus]::None) {
                Write-Message -Level Verbose -Message "Cannot setup mirroring on database ($dbName) due to its current mirroring state: $($db.MirroringStatus)"
                $canmirror = $false
            }

            if ($db.Status -ne [Microsoft.SqlServer.Management.Smo.DatabaseStatus]::Normal) {
                Write-Message -Level Verbose -Message "Cannot setup mirroring on database ($dbName) due to its current Status: $($db.Status)"
                $canmirror = $false
            }

            if ($db.RecoveryModel -ne 'Full') {
                Write-Message -Level Verbose -Message "Cannot setup mirroring on database ($dbName) due to its current recovery model: $($db.RecoveryModel)"
                $canmirror = $false
            }

            $destdb = Get-DbaDatabase -SqlInstance $dest -Database $db.Name

            if ($destdb.RecoveryModel -ne 'Full') {
                $canmirror = $false
            }

            if ($destdb.Status -ne 'Restoring') {
                $canmirror = $false
            }

            if ($destdb) {
                $destdbexists = $true
            } else {
                Write-Message -Level Verbose -Message "Database ($dbName) does not exist on mirror server"
                $canmirror = $false
                $destdbexists = $false
            }

            if ((Test-Bound -ParameterName SharedPath) -and -not (Test-DbaPath -SqlInstance $dest -Path $SharedPath)) {
                Write-Message -Level Verbose -Message "Cannot access $SharedPath from $($destdb.Parent.Name)"
                $canmirror = $false
                $nexists = $false
            } else {
                $nexists = $true
            }

            if ($server.EngineEdition -ne $dest.EngineEdition) {
                Write-Message -Level Verbose -Message "This mirroring configuration is not supported. Because the principal server instance, $server, is $($server.EngineEdition) Edition, the mirror server instance must also be $($server.EngineEdition) Edition."
                $canmirror = $false
                $edition = $false
            } else {
                $edition = $true
            }

            # There's a better way to do this but I'm sleepy
            if ((Test-Bound -ParameterName Witness)) {
                if ($endpoints.Count -eq 3) {
                    $endpointpass = $true
                } else {
                    $endpointpass = $false
                }
            } else {
                if ($endpoints.Count -eq 2) {
                    $endpointpass = $true
                } else {
                    $endpointpass = $false
                }
            }

            $results = [pscustomobject]@{
                Primary                 = $Primary
                Mirror                  = $Mirror
                Witness                 = $Witness
                Database                = $db.Name
                RecoveryModel           = $db.RecoveryModel
                MirroringStatus         = $db.MirroringStatus
                State                   = $db.Status
                EndPoints               = $endpointpass
                DatabaseExistsOnMirror  = $destdbexists
                DatabaseExistsOnWitness = $witexists
                OnlineWitness           = $wexists
                EditionMatch            = $edition
                AccessibleShare         = $nexists
                DestinationDbStatus     = $destdb.Status
                WitnessDbStatus         = $witdb.Status
                ValidationPassed        = $canmirror
            }

            if ((Test-Bound -ParameterName Witness)) {
                $results | Select-DefaultView -Property Primary, Mirror, Witness, Database, RecoveryModel, MirroringStatus, State, EndPoints, DatabaseExistsOnMirror, OnlineWitness, DatabaseExistsOnWitness, EditionMatch, AccessibleShare, DestinationDbStatus, WitnessDbStatus, ValidationPassed
            } else {
                $results | Select-DefaultView -Property Primary, Mirror, Database, RecoveryModel, MirroringStatus, State, EndPoints, DatabaseExistsOnMirror, EditionMatch, AccessibleShare, DestinationDbStatus, ValidationPassed
            }
        }
    }
}