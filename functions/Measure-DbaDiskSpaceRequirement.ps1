function Measure-DbaDiskSpaceRequirement {
    <#
        .SYNOPSIS
            Calculate the space needed to copy and possibly replace a database from one SQL server to another.

        .DESCRIPTION
            Returns a file list from source and destination where source file may overwrite destination. Complex scenarios where a new file may exist is taken into account.
            This command will accept a hash object in pipeline with the following keys: Source, SourceDatabase, Destination. Using this command will provide a way to prepare before a complex migration with multiple databases from different sources and destinations.

        .PARAMETER Source
            Source SQL Server.

        .PARAMETER SourceSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            The database to copy. It MUST exist.

        .PARAMETER Destination
            Destination SQL Server instance.

        .PARAMETER DestinationSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER DestinationDatabase
            The database name at destination.
            May or may not be present, if unspecified it will default to the database name provided in SourceDatabase.

        .PARAMETER Credential
            The credentials to use to connect via CIM/WMI/PowerShell remoting.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
           Tags: Database, DiskSpace, Migration
           Author: Pollus Brodeur (@pollusb)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Measure-DbaDiskSpaceRequirement

        .EXAMPLE
            Measure-DbaDiskSpaceRequirement -Source INSTANCE1 -Database DB1 -Destination INSTANCE2

            Calculate space needed for a simple migration with one database with the same name at destination.

        .EXAMPLE
            @([PSCustomObject]@{Source='SQL1';Destination='SQL2';Database='DB1'},
              [PSCustomObject]@{Source='SQL1';Destination='SQL2';Database='DB2'}
            ) | Measure-DbaDiskSpaceRequirement

            Using a PSCustomObject with 2 databases to migrate on SQL2.

        .EXAMPLE
            Import-Csv -Path .\migration.csv -Delimiter "`t" | Measure-DbaDiskSpaceRequirement | Format-Table -AutoSize

            Using a CSV file. You will need to use this header line "Source<tab>Destination<tab>Database<tab>DestinationDatabase".

        .EXAMPLE
            Invoke-DbaSqlCmd -SqlInstance DBA -Database Migrations -Query 'select Source, Destination, Database from dbo.Migrations' `
                | Measure-DbaDiskSpaceRequirement

            Using a SQL table. We are DBA after all!
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [DbaInstanceParameter]$Source,
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Database,
        [PSCredential]$SourceSqlCredential,
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [DbaInstanceParameter]$Destination,
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$DestinationDatabase,
        [PSCredential]$DestinationSqlCredential,
        [PSCredential]$Credential,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        $local:cacheMP = @{}
        $local:cacheDP = @{}

        function Get-MountPointFromPath {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                $path,
                [Parameter(Mandatory = $true)]
                $computerName,
                [PSCredential]$credential
            )
            if (!$cacheMP[$computerName]) {
                try {
                    $cacheMP.Add($computerName, (Get-DbaDiskSpace -ComputerName $computerName -Credential $Credential -EnableException))
                    Write-Message -Level Verbose -Message "cacheMP[$computerName] is in cache"
                }
                catch {
                    # This way, I won't be asking again for this computer.
                    $cacheMP.Add($computerName, '?')
                    Stop-Function -Message "Can't connect to $computerName. cacheMP[$computerName] = ?" -ErrorRecord $_ -Target $computerName -Continue
                }
            }
            if ($cacheMP[$computerName] -eq '?') {
                return '?'
            }
            foreach ($m in ($cacheMP[$computerName] | Sort-Object -Property Name -Descending)) {
                if ($path -like "$($m.Name)*") {
                    return $m.Name
                }
            }
            Write-Message -Level Warning -Message "Path $path can't be found in any MountPoints of $computerName"
        }
        function Get-MountPointFromDefaultPath {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [ValidateSet('Log', 'Data')]
                $DefaultPathType,
                [Parameter(Mandatory = $true)]
                $SqlInstance,
                [PSCredential]$SqlCredential,
                # Could probably use the computer defined in SqlInstance but info was already available from the caller
                $computerName,
                [PSCredential]$Credential
            )
            if (!$cacheDP[$SqlInstance]) {
                try {
                    $cacheDP.Add($SqlInstance, (Get-DbaDefaultPath -SqlInstance $SqlInstance -SqlCredential $SqlCredential -EnableException))
                    Write-Message -Level Verbose -Message "cacheDP[$SqlInstance] is in cache"
                }
                catch {
                    Stop-Function -Message "Can't connect to $SqlInstance" -Continue
                    $cacheDP.Add($SqlInstance, '?')
                    return '?'
                }
            }
            if ($cacheDP[$SqlInstance] -eq '?') {
                return '?'
            }
            if (!$computerName) {
                $computerName = $cacheDP[$SqlInstance].ComputerName
            }
            if (!$cacheMP[$computerName]) {
                try {
                    $cacheMP.Add($computerName, (Get-DbaDiskSpace -ComputerName $computerName -Credential $Credential))
                }
                catch {
                    Stop-Function -Message "Can't connect to $computerName." -Continue
                    $cacheMP.Add($computerName, '?')
                    return '?'
                }
            }
            if ($DefaultPathType -eq 'Log') {
                $path = $cacheDP[$SqlInstance].Log
            }
            else {
                $path = $cacheDP[$SqlInstance].Data
            }
            foreach ($m in ($cacheMP[$computerName] | Sort-Object -Property Name -Descending)) {
                if ($path -like "$($m.Name)*") {
                    return $m.Name
                }
            }
        }
    }
    process {
        Write-Message -Level Verbose -Message "Attempting to connect to SQL Servers."
        try {
            Write-Message -Level Verbose -Message "Connecting to $Source."
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
        }

        try {
            Write-Message -Level Verbose -Message "Connecting to $Destination."
            $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination
        }

        if (Test-Bound 'DestinationDatabase' -not) {
            $DestinationDatabase = $Database
        }
        Write-Message -Level Verbose -Message "$Source.[$Database] -> $Destination.[$DestinationDatabase]"

        $sourceDb = Get-DbaDatabase -SqlInstance $sourceServer -Database $Database -SqlCredential $SourceSqlCredential
        if (Test-Bound 'Database' -not) {
            Stop-Function -Message "Database [$Database] MUST exist on Source Instance $Source." -ErrorRecord $_
        }
        $sourceFiles = @($sourceDb.FileGroups.Files | Select-Object Name, FileName, Size, @{n='Type'; e= {'Data'}})
        $sourceFiles += @($sourceDb.LogFiles        | Select-Object Name, FileName, Size, @{n='Type'; e= {'Log'}})

        if ($destDb = Get-DbaDatabase -SqlInstance $destServer -Database $DestinationDatabase -SqlCredential $DestinationSqlCredential) {
            $destFiles = @($destDb.FileGroups.Files | Select-Object Name, FileName, Size, @{n='Type'; e= {'Data'}})
            $destFiles += @($destDb.LogFiles        | Select-Object Name, FileName, Size, @{n='Type'; e= {'Log'}})
            $computerName = $destDb.ComputerName
        }
        else {
            Write-Message -Level Verbose -Message "Database [$DestinationDatabase] does not exist on Destination Instance $Destination."
            $computerName = $destServer.NetName
        }

        foreach ($sourceFile in $sourceFiles) {
            foreach ($destFile in $destFiles) {
                if ($found = ($sourceFile.Name -eq $destFile.Name)) {
                    # Files found on both sides
                    [PSCustomObject]@{
                            SourceComputerName      = $sourceServer.NetName
                            SourceInstance          = $sourceServer.ServiceName
                            SourceSqlInstance       = $sourceServer.DomainInstanceName
                            DestinationComputerName = $destServer.NetName
                            DestinationInstance     = $destServer.ServiceName
                            DestinationSqlInstance  = $destServer.DomainInstanceName
                            SourceDatabase          = $sourceDb.Name
                            SourceLogicalName       = $sourceFile.Name
                            SourceFileName          = $sourceFile.FileName
                            SourceFileSize          = [DbaSize]($sourceFile.Size * 1000)
                            DestinationDatabase     = $destDb.Name
                            DestinationLogicalName  = $destFile.Name
                            DestinationFileName     = $destFile.FileName
                            DestinationFileSize     = [DbaSize]($destFile.Size * 1000) * -1
                            DifferenceSize          = [DbaSize]( ($sourceFile.Size * 1000) - ($destFile.Size * 1000) )
                            MountPoint              = Get-MountPointFromPath -Path $destFile.Filename -ComputerName $computerName -Credential $Credential
                        } | Select-DefaultView -ExcludeProperty SourceComputerName, SourceInstance, DestinationComputerName, DestinationInstance
                    break
                }
            }
            if (!$found) {
                # Files on source but not on destination
                [PSCustomObject]@{
                        SourceComputerName      = $sourceServer.NetName
                        SourceInstance          = $sourceServer.ServiceName
                        SourceSqlInstance       = $sourceServer.DomainInstanceName
                        DestinationComputerName = $destServer.NetName
                        DestinationInstance     = $destServer.ServiceName
                        DestinationSqlInstance  = $destServer.DomainInstanceName
                        SourceDatabase          = $sourceDb.Name
                        SourceLogicalName       = $sourceFile.Name
                        SourceFileName          = $sourceFile.FileName
                        SourceFileSize          = [DbaSize]($sourceFile.Size * 1000)
                        DestinationDatabase     = $DestinationDatabase
                        DestinationLogicalName  = $null
                        DestinationFileName     = $null
                        DestinationFileSize     = [DbaSize]0
                        DifferenceSize          = [DbaSize]($sourceFile.Size * 1000)
                        MountPoint              = Get-MountPointFromDefaultPath -DefaultPathType $sourceFile.Type -SqlInstance $destServer -SqlCredential $DestinationSqlCredential
                    } | Select-DefaultView -ExcludeProperty SourceComputerName, SourceInstance, DestinationComputerName, DestinationInstance
            }
        }
        if ($destDb) {
            # Files on destination but not on source (strange scenario but possible)
            $destFilesNotSource = Compare-Object -ReferenceObject $destFiles -DifferenceObject $sourceFiles -Property Name -PassThru
            foreach ($destFileNotSource in $destFilesNotSource) {
                [PSCustomObject]@{
                        SourceComputerName      = $sourceServer.NetName
                        SourceInstance          = $sourceServer.ServiceName
                        SourceSqlInstance       = $sourceServer.DomainInstanceName
                        DestinationComputerName = $destServer.NetName
                        DestinationInstance     = $destServer.ServiceName
                        DestinationSqlInstance  = $destServer.DomainInstanceName
                        SourceDatabaseName      = $Database
                        SourceLogicalName       = $null
                        SourceFileName          = $null
                        SourceFileSize          = [DbaSize]0
                        DestinationDatabaseName = $destDb.Name
                        DestinationLogicalName  = $destFileNotSource.Name
                        DestinationFileName     = $destFile.FileName
                        DestinationFileSize     = [DbaSize]($destFileNotSource.Size * 1000) * -1
                        DifferenceSize          = [DbaSize]($destFileNotSource.Size * 1000) * -1
                        MountPoint              = Get-MountPointFromPath -Path $destFileNotSource.Filename -ComputerName $computerName -Credential $Credential
                    } | Select-DefaultView  -ExcludeProperty SourceComputerName, SourceInstance, DestinationComputerName, DestinationInstance
            }
        }
        $DestinationDatabase = $null
    }
}
