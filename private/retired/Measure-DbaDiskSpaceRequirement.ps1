function Measure-DbaDiskSpaceRequirement {
    <#
    .SYNOPSIS
        Calculates disk space requirements for database migration between SQL Server instances

    .DESCRIPTION
        Analyzes database files on source and destination instances to calculate space requirements before migration. Shows file size differences, mount points, and identifies potential overwrites when copying databases between SQL Server instances.

        The function compares data and log files from the source database against existing files on the destination, accounting for scenarios where files exist only on source, only on destination, or on both sides. This prevents migration failures due to insufficient disk space and helps plan storage allocation.

        Accepts pipeline input with Source, Database, and Destination properties, making it ideal for bulk migration planning from CSV files, SQL queries, or PowerShell objects.

    .PARAMETER Source
        Specifies the source SQL Server instance containing the database to analyze for migration.
        This is where the database currently exists and from which file sizes will be measured.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the name of the database to analyze on the source instance.
        The database must exist on the source server as the function reads actual file sizes from this database.

    .PARAMETER Destination
        Specifies the destination SQL Server instance where the database will be migrated.
        Used to determine target file paths, check for existing databases with the same name, and calculate mount point requirements.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER DestinationDatabase
        Specifies the database name to use on the destination instance if different from the source database name.
        When omitted, the destination database will use the same name as the source database.
        Useful when migrating databases that need to be renamed or when avoiding naming conflicts on the destination server.

    .PARAMETER Credential
        The credentials to use to connect via CIM/WMI/PowerShell remoting.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Storage, Space, Database
        Author: Pollus Brodeur (@pollusb)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Measure-DbaDiskSpaceRequirement

    .OUTPUTS
        PSCustomObject

        Returns one object per database file analyzed during migration planning. Multiple objects are returned for databases with multiple files (one per file). Objects are returned for three scenarios: files on both source and destination, files only on source, or files only on destination.

        Default display properties (via Select-DefaultView):
        - SourceSqlInstance: The full SQL Server instance name of the source (computer\instance)
        - SourceDatabase: Name of the source database
        - SourceLogicalName: Logical name of the database file on the source
        - SourceFileName: Operating system file path of the source file
        - SourceFileSize: DbaSize object of the source file size (bytes, converts to KB/MB/GB/TB)
        - DestinationComputerName: The computer name of the destination SQL Server instance
        - DestinationSqlInstance: The full SQL Server instance name of the destination (computer\instance)
        - DestinationDatabase: Name of the destination database (may differ from source if renamed)
        - DestinationFileName: Operating system file path of the destination file (null if file only on source)
        - DestinationFileSize: DbaSize object of destination file size; null or 0 if file only on source (displayed as negative value when present)
        - DifferenceSize: DbaSize object showing the difference in file size between source and destination
        - MountPoint: The volume mount point where the destination file is or will be located
        - FileLocation: Scenario description - "Source and Destination", "Only on Source", or "Only on Destination"

        Hidden properties (available via Select-Object *):
        - SourceComputerName: The computer name of the source SQL Server instance
        - SourceInstance: The SQL Server instance name of the source
        - DestinationInstance: The SQL Server instance name of the destination
        - DestinationLogicalName: Logical name of the destination file (null if file only on source)
        - SourceDatabaseName: Source database name (used in "Only on Destination" scenario)
        - DestinationDatabaseName: Destination database name (used in "Only on Destination" scenario)

        Use Select-Object * to access all properties including hidden ones.

    .EXAMPLE
        PS C:\> Measure-DbaDiskSpaceRequirement -Source INSTANCE1 -Database DB1 -Destination INSTANCE2

        Calculate space needed for a simple migration with one database with the same name at destination.

    .EXAMPLE
        PS C:\> @(
        >> [PSCustomObject]@{Source='SQL1';Destination='SQL2';Database='DB1'},
        >> [PSCustomObject]@{Source='SQL1';Destination='SQL2';Database='DB2'}
        >> ) | Measure-DbaDiskSpaceRequirement

        Using a PSCustomObject with 2 databases to migrate on SQL2.

    .EXAMPLE
        PS C:\> Import-Csv -Path .\migration.csv -Delimiter "`t" | Measure-DbaDiskSpaceRequirement | Format-Table -AutoSize

        Using a CSV file. You will need to use this header line "Source<tab>Destination<tab>Database<tab>DestinationDatabase".

    .EXAMPLE
        PS C:\> $qry = "SELECT Source, Destination, Database FROM dbo.Migrations"
        PS C:\> Invoke-DbaCmd -SqlInstance DBA -Database Migrations -Query $qry | Measure-DbaDiskSpaceRequirement

        Using a SQL table. We are DBA after all!
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter]$Source,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Database,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$SourceSqlCredential,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter]$Destination,
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$DestinationDatabase,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$DestinationSqlCredential,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    begin {
        $local:cacheMP = @{ }
        $local:cacheDP = @{ }
        function Get-MountPoint {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                $computerName,
                [PSCredential]$credential
            )
            Get-DbaCmObject -Class Win32_MountPoint -ComputerName $computerName -Credential $credential | Select-Object @{n = 'Mountpoint'; e = { $_.Directory.split('=')[1].Replace('"', '').Replace('\\', '\') } }
        }
        function Get-MountPointFromPath {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                $path,
                [Parameter(Mandatory)]
                $computerName,
                [PSCredential]$credential
            )
            if (!$cacheMP[$computerName]) {
                try {
                    $cacheMP.Add($computerName, (Get-MountPoint -computerName $computerName -credential $credential))
                    Write-Message -Level Verbose -Message "cacheMP[$computerName] is now cached"
                } catch {
                    # This way, I won't be asking again for this computer.
                    $cacheMP.Add($computerName, '?')
                    Stop-Function -Message "Can't connect to $computerName. cacheMP[$computerName] = ?" -ErrorRecord $_ -Target $computerName -Continue
                }
            }
            if ($cacheMP[$computerName] -eq '?') {
                return '?'
            }
            foreach ($m in ($cacheMP[$computerName] | Sort-Object -Property Mountpoint -Descending)) {
                if ($path -like "$($m.Mountpoint)*") {
                    return $m.Mountpoint
                }
            }
            Write-Message -Level Warning -Message "Path $path can't be found in any MountPoints of $computerName"
        }
        function Get-MountPointFromDefaultPath {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [ValidateSet('Log', 'Data')]
                $DefaultPathType,
                [Parameter(Mandatory)]
                $SqlInstance,
                [PSCredential]$SqlCredential,
                # Could probably use the computer defined in SqlInstance but info was already available from the caller
                $computerName,
                [PSCredential]$Credential
            )
            if (!$cacheDP[$SqlInstance]) {
                try {
                    $cacheDP.Add($SqlInstance, (Get-DbaDefaultPath -SqlInstance $SqlInstance -SqlCredential $SqlCredential -EnableException))
                    Write-Message -Level Verbose -Message "cacheDP[$SqlInstance] is now cached"
                } catch {
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
                    $cacheMP.Add($computerName, (Get-MountPoint -computerName $computerName -Credential $Credential))
                } catch {
                    Stop-Function -Message "Can't connect to $computerName." -Continue
                    $cacheMP.Add($computerName, '?')
                    return '?'
                }
            }
            if ($DefaultPathType -eq 'Log') {
                $path = $cacheDP[$SqlInstance].Log
            } else {
                $path = $cacheDP[$SqlInstance].Data
            }
            foreach ($m in ($cacheMP[$computerName] | Sort-Object -Property Mountpoint -Descending)) {
                if ($path -like "$($m.Mountpoint)*") {
                    return $m.Mountpoint
                }
            }
        }
    }
    process {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        try {
            $destServer = Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination
            return
        }

        if (Test-Bound 'DestinationDatabase' -not) {
            $DestinationDatabase = $Database
        }
        Write-Message -Level Verbose -Message "$Source.[$Database] -> $Destination.[$DestinationDatabase]"

        $sourceDb = Get-DbaDatabase -SqlInstance $sourceServer -Database $Database -SqlCredential $SourceSqlCredential
        if (Test-Bound 'Database' -not) {
            Stop-Function -Message "Database [$Database] MUST exist on Source Instance $Source."
        }
        $sourceFiles = @($sourceDb.FileGroups.Files | Select-Object Name, FileName, Size, @{n = 'Type'; e = { 'Data' } })
        $sourceFiles += @($sourceDb.LogFiles | Select-Object Name, FileName, Size, @{n = 'Type'; e = { 'Log' } })

        if ($destDb = Get-DbaDatabase -SqlInstance $destServer -Database $DestinationDatabase -SqlCredential $DestinationSqlCredential) {
            $destFiles = @($destDb.FileGroups.Files | Select-Object Name, FileName, Size, @{n = 'Type'; e = { 'Data' } })
            $destFiles += @($destDb.LogFiles | Select-Object Name, FileName, Size, @{n = 'Type'; e = { 'Log' } })
            $computerName = $destDb.ComputerName
        } else {
            Write-Message -Level Verbose -Message "Database [$DestinationDatabase] does not exist on Destination Instance $Destination."
            $computerName = $destServer.ComputerName
        }

        foreach ($sourceFile in $sourceFiles) {
            foreach ($destFile in $destFiles) {
                if (($found = ($sourceFile.Name -eq $destFile.Name))) {
                    # Files found on both sides
                    [PSCustomObject]@{
                        SourceComputerName      = $sourceServer.ComputerName
                        SourceInstance          = $sourceServer.ServiceName
                        SourceSqlInstance       = $sourceServer.DomainInstanceName
                        DestinationComputerName = $destServer.ComputerName
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
                        FileLocation            = 'Source and Destination'
                    } | Select-DefaultView -ExcludeProperty SourceComputerName, SourceInstance, DestinationInstance, DestinationLogicalName
                    break
                }
            }
            if (!$found) {
                # Files on source but not on destination
                [PSCustomObject]@{
                    SourceComputerName      = $sourceServer.ComputerName
                    SourceInstance          = $sourceServer.ServiceName
                    SourceSqlInstance       = $sourceServer.DomainInstanceName
                    DestinationComputerName = $destServer.ComputerName
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
                    MountPoint              = Get-MountPointFromDefaultPath -DefaultPathType $sourceFile.Type -SqlInstance $Destination `
                        -SqlCredential $DestinationSqlCredential -computerName $computerName -credential $Credential
                    FileLocation            = 'Only on Source'
                } | Select-DefaultView -ExcludeProperty SourceComputerName, SourceInstance, DestinationInstance, DestinationLogicalName
            }
        }
        if ($destDb) {
            # Files on destination but not on source (strange scenario but possible)
            $destFilesNotSource = Compare-Object -ReferenceObject $destFiles -DifferenceObject $sourceFiles -Property Name -PassThru
            foreach ($destFileNotSource in $destFilesNotSource) {
                [PSCustomObject]@{
                    SourceComputerName      = $sourceServer.ComputerName
                    SourceInstance          = $sourceServer.ServiceName
                    SourceSqlInstance       = $sourceServer.DomainInstanceName
                    DestinationComputerName = $destServer.ComputerName
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
                    FileLocation            = 'Only on Destination'
                } | Select-DefaultView -ExcludeProperty SourceComputerName, SourceInstance, DestinationInstance, DestinationLogicalName
            }
        }
        $DestinationDatabase = $null
    }
}