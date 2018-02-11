Function Measure-DbaDiskSpaceRequirement {
    <#
        .SYNOPSIS
            Calculate the space needed to copy and possibly replace a database from one SQL server to another.

        .DESCRIPTION
            Returns a file list from source and destination where source file may overwrite destination. Complex scenarios where a new file may exist is taken
            into account. This procedure will accept an object in pipeline as long as it as provide these required properties: Source, SourceDatabase, Destination.
            Using this method will provide a way to prepare before a complex migration with lots of databases from different sources and destinations.

        .PARAMETER Source
            The source SQL Server instance.

        .PARAMETER SourceSqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

            Windows Authentication will be used if SourceSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER SourceDatabase
            The database to copy. It MUST exist.

        .PARAMETER Destination
            The destination SQL Server instance.

        .PARAMETER DestinationSqlCredential
            Same as SourceSqlCredential.

        .PARAMETER DestinationDatabase
            The database name at destination. May or may not be present. Unspecified name will assume database name be the same as source.

        .PARAMETER Credential
            Windows credentials to connect via CIM/WMI/PowerShell remoting for MountPoint definition.

        .NOTES
            Author: Pollus Brodeur (@pollusb)
            Tags: Migration

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Measure-DbaDiskSpaceRequirement

        .EXAMPLE
            Measure-DbaDiskSpaceRequirement -Source INSTANCE1 -SourceDatabase DB1 -Destination INSTANCE2

            Calculate space needed for a simple migration with one database with the same name at destination.

        .EXAMPLE
            @([PSCustomObject]@{Source='SQL1';Destination='SQL2';SourceDatabase='DB1'},
              [PSCustomObject]@{Source='SQL1';Destination='SQL2';SourceDatabase='DB2'}
            ) | Measure-DbaDiskSpaceRequirement

            Using a PSCustomObject with 2 databases to migrate on SQL2

        .EXAMPLE
            Import-Csv -Path .\migration.csv -Delimiter "`t" | Measure-DbaDiskSpaceRequirement | Format-Table -AutoSize

            Using a CSV file. You will need to use this header line "Source<tab>Destination<tab>SourceDatabase<tab>DestinationDatabase"

        .EXAMPLE
            Invoke-DbaSqlCmd -SqlInstance DBA -Database Migrations -Query 'select Source, Destination, SourceDatabase from dbo.Migrations' `
                | Measure-DbaDiskSpaceRequirement

            Using a SQL table. We are DBA after all!
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter]$Source,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]
        [string]$SourceDatabase,
        [PSCredential]$SourceSqlCredential,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]
        [DbaInstanceParameter]$Destination,
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName)]
        [string]$DestinationDatabase,
        [PSCredential]$DestinationSqlCredential,
        [PSCredential]$Credential
    )
    begin {
        $NullText = '#NULL'

        $local:CacheMP = @{}
        $local:CacheDP = @{}

        function Get-MountPointFromPath {
            [CmdletBinding()]
            Param(
                [Parameter(Mandatory)]
                $Path,
                [Parameter(Mandatory)]
                $ComputerName,
                [PSCredential]$Credential
            )
            if(!$CacheMP[$ComputerName]) {
                try {
                    $CacheMP.Add($ComputerName, (Get-DbaDiskSpace -ComputerName $ComputerName -Credential $Credential -EnableException))
                    Write-Message -Level Verbose -Message "CacheMP[$ComputerName] is in cache" -EnableException:$false
                } catch {
                    $CacheMP.Add($ComputerName, '?') # This way, I won't be asking again for this computer.
                    Stop-Function -Message "Can't connect to $ComputerName. CacheMP[$ComputerName] = ?" -Continue
                }
            }
            if($CacheMP[$ComputerName] -eq '?') {
                return '?'
            }
            foreach($M in ($CacheMP[$ComputerName] | Sort-Object -Property Name -Descending)) {
                if($Path -like "$($M.Name)*") {
                    return $M.Name
                }
            }
            Write-Message -Level Warning -Message "Path $Path can't be found in any MountPoints of $ComputerName" -EnableException:$false
        }
        function Get-MountPointFromDefaultPath {
            [CmdletBinding()]
            Param(
                [Parameter(Mandatory)]
                [ValidateSet('Log','Data')]
                $DefaultPathType,
                [Parameter(Mandatory)]
                $SqlInstance,
                [PSCredential]$SqlCredential,
                $ComputerName, # Could probably use the computer defined in SqlInstance but info was already available from the caller
                [PSCredential]$Credential
            )
            if(!$CacheDP[$SqlInstance]) {
                try {
                    $CacheDP.Add($SqlInstance, (Get-DbaDefaultPath -SqlInstance $SqlInstance -SqlCredential $SqlCredential -EnableException))
                    Write-Message -Level Verbose -Message "CacheDP[$SqlInstance] is in cache" -EnableException:$false
                } catch {
                    Stop-Function -Message "Can't connect to $SqlInstance" -Continue -EnableException:$false
                    $CacheDP.Add($SqlInstance, '?')
                    return '?'
                }
            }
            if($CacheDP[$SqlInstance] -eq '?') {
                return '?'
            }
            if(!$ComputerName) {
                $ComputerName = $CacheDP[$SqlInstance].ComputerName
            }
            if(!$CacheMP[$ComputerName]) {
                try {
                    $CacheMP.Add($ComputerName, (Get-DbaDiskSpace -ComputerName $ComputerName -Credential $Credential))
                } catch {
                    Stop-Function -Message "Can't connect to $ComputerName." -Continue -EnableException:$false
                    $CacheMP.Add($ComputerName,'?')
                    return '?'
                }
            }
            if($DefaultPathType -eq 'Log') {
                $Path = $CacheDP[$SqlInstance].Log
            } else {
                $Path = $CacheDP[$SqlInstance].Data
            }
            foreach($M in ($CacheMP[$ComputerName] | Sort-Object -Property Name -Descending)) {
                if($Path -like "$($M.Name)*") {
                    return $M.Name
                }
            }
        }
    }
    process {
        if(!$DestinationDatabase) {
            $DestinationDatabase = $SourceDatabase
        }
        Write-Message -Level Verbose -Message "$Source.[$SourceDatabase] -> $Destination.[$DestinationDatabase]" -EnableException:$false

        $DB1 = Get-DbaDatabase -SqlInstance $Source -Database $SourceDatabase -SqlCredential $SourceSqlCredential
        if(!$DB1) {
            Stop-Function -Message "Database [$SourceDatabase] MUST exist on Source Instance $Source." -ErrorRecord $_ -EnableException:$false
        }
        $DataFiles1 = @($DB1.FileGroups.Files | Select-Object Name, FileName, Size, @{n='Type';e={'Data'}})
        $DataFiles1 += @($DB1.LogFiles        | Select-Object Name, FileName, Size, @{n='Type';e={'Log'}})

        if($DB2 = Get-DbaDatabase -SqlInstance $Destination -Database $DestinationDatabase -SqlCredential $DestinationSqlCredential) {
            $DataFiles2 = @($DB2.FileGroups.Files | Select-Object Name, FileName, Size, @{n='Type';e={'Data'}})
            $DataFiles2 += @($DB2.LogFiles        | Select-Object Name, FileName, Size, @{n='Type';e={'Log'}})
            $ComputerName = $DB2.ComputerName
        } else {
            Write-Message -Level Verbose -Message "Database [$DestinationDatabase] does not exist on Destination Instance $Destination." -EnableException:$false
            $ComputerName = (Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential).NetName
        }

        foreach($File1 in $DataFiles1) {
            foreach($File2 in $DataFiles2) {
                if($found = ($File1.Name -eq $File2.Name)) { # Files found on both sides
                    $Detail += @([PSCustomObject]@{
                        Source = $Source
                        Destination = $Destination
                        DatabaseName1 = $DB1.Name
                        DatabaseName2 = $DB2.Name
                        Name1 = $File1.Name
                        Name2 = $File2.Name
                        FilePath1 = $File1.FileName
                        FilePath2 = $File2.FileName
                        SizeKB1 = $File1.Size
                        SizeKB2 = $File2.Size * -1
                        DiffKB = $File1.Size - $File2.Size
                        ComputerName = $ComputerName
                        MountPoint = Get-MountPointFromPath -Path $File2.Filename -ComputerName $ComputerName -Credential $Credential
                    })
                    break
                }
            }
            if(!$found) { # Files on source but not on destination
                $Detail += @([PSCustomObject]@{
                    Source = $Source
                    Destination = $Destination
                    DatabaseName1 = $DB1.Name
                    DatabaseName2 = $DestinationDatabase
                    Name1 = $File1.Name
                    Name2 = $NullText
                    FilePath1 = $File1.FileName
                    FilePath2 = $NullText
                    SizeKB1 = $File1.Size
                    SizeKB2 = 0
                    DiffKB = $File1.Size
                    ComputerName = $ComputerName
                    MountPoint = Get-MountPointFromDefaultPath -DefaultPathType $File1.Type -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
                })
            }
        }
        if($DB2) { # Files on destination but not on source (strange scenario but possible)
            $DataFiles3 = Compare-Object -ReferenceObject $DataFiles2 -DifferenceObject $DataFiles1 -Property Name -PassThru
            foreach($File3 in $DataFiles3) {
                $Detail += @([PSCustomObject]@{
                    Source = $Source
                    Destination = $Destination
                    DatabaseName1 = $SourceDatabase
                    DatabaseName2 = $DB2.Name
                    Name1 = $NullText
                    Name2 = $File3.Name
                    FilePath1 = $NullText
                    FilePath2 = $File2.FileName
                    SizeKB1 = 0
                    SizeKB2 = $File3.Size * -1
                    DiffKB = $File3.Size * -1
                    ComputerName = $ComputerName
                    MountPoint = Get-MountPointFromPath -Path $File3.Filename -ComputerName $ComputerName -Credential $Credential
                })
            }
        }
        $DestinationDatabase = ''
    }
    end {
        $Detail | Select-DefaultView -Property DatabaseName1, DatabaseName2, Name1, Name2, SizeKB1, SizeKB2, DiffKB, ComputerName, MountPoint
    }
}