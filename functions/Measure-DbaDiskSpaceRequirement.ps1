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

        .PARAMETER Consolidate
            Will summarize space by ComputerName and MountPoints.

        .NOTES
            Tags: Migration

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Measure-DbaDiskSpaceRequirement

        .EXAMPLE
            Measure-DbaDiskSpaceRequirement -SI INSTANCE1 -SD DB1 -DI INSTANCE2 -Consolidate

            Calculate a simple migration with one database with then same name at destination. In this scenario,
            no space is required since we will recover 448 KB on destination disk.

            DatabaseName1   DatabaseName2   Name1     Name2   SizeKB1 SizeKB2 DiffKB ComputerName MountPoint
            -------------   -------------   -----     -----   ------- ------- ------ ------------ ----------
            DB1             DB1             DB1       DB1        3072   -3000     72 INSTANCE2    D:\
            DB1             DB1             DB1_log   DB1_log     504   -1024   -520 INSTANCE2    D:\

            ComputerName MountPoint RequiredSpaceKB
            ------------ ---------- ---------------
            INSTANCE2    D:\                   -448

        .EXAMPLE
            @([PSCustomObject]@{Source='SQL1';Destination='SQL2';Database='DB1'},
              [PSCustomObject]@{Source='SQL1';Destination='SQL2';Database='DB2'}
            ) | Measure-DbaDiskSpaceRequirement -Consolidate

            Using a PSCustomObject with 2 databases to migrate

        .EXAMPLE
            Import-Csv -Path .\migration.csv -Delimiter "`t" | Measure-DbaDiskSpaceRequirement -Consolidate

            Using a CSV file. You will need a header in migration.csv "Source<tab>Destination<tab>Database"

        .EXAMPLE
            Invoke-DbaSqlCmd -SqlInstance DBA -Database Migrations -Query 'select Source,Destination,DatabaseName from refresh.Migrations' `
                | Measure-DbaDiskSpaceRequirement -Consolidate -Verbose

            Using a SQL table. We are DBA after all!
    #>

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]
        [Alias('SI','SqlInstance')]
        [string]$Source,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]
        [Alias('SD','Database','DatabaseName')]
        [string]$SourceDatabase,
        [Alias('SC')]
        [PSCredential]$SourceSqlCredential,
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]
        [Alias('DI')]
        [string]$Destination, 
        [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName)]
        [Alias('DD')]
        [string]$DestinationDatabase,
        [Alias('DC')]
        [PSCredential]$DestinationSqlCredential,
        [PSCredential]$Credential, # For Windows access to MountPoints
        [switch]$Consolidate # Default would be detail only.
    )
    begin {
        $NullText = '#NULL'
        # TODO: What if multiple mountpoints exists on the same drive? Will $Path -like "$($M.Name)*" return the right one? I think we need to force a lazy RegEx

        $local:CacheMP = @{}
        $local:CacheDP = @{}

        function Get-MountPointFromPath {
            # Extract MountPoint from Path. This could be reuse I guess.
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
                    Write-Verbose "CacheMP[$ComputerName] is in cache"
                } catch {
                    Write-Warning "Can't connect to $ComputerName. CacheMP[$ComputerName] = ?"
                    $CacheMP.Add($ComputerName, '?') # This way, I won't be asking again for this computer.
                }
            }
            if($CacheMP[$ComputerName] -eq '?') {
                return '?'
            }
            foreach($M in $CacheMP[$ComputerName]) {
                if($Path -like "$($M.Name)*") {
                    return $M.Name
                }
            }
            Write-Warning "Path $Path can't be found in any MountPoints of $ComputerName"
        }

        function Get-MountPointFromDefaultPath {
            # Extract MountPoint from DefaultPath. Usefull when database or file does not exist on destination.
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
                    Write-Verbose "CacheDP[$SqlInstance] is in cache"
                } catch {
                    Write-Warning "Can't connect to $SqlInstance"
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
                    Write-Warning "Can't connect to $ComputerName."
                    $CacheMP.Add($ComputerName,'?')
                    return '?'
                }
            }
            if($DefaultPathType -eq 'Log') {
                $Path = $CacheDP[$SqlInstance].Log
            } else {
                $Path = $CacheDP[$SqlInstance].Data
            }
            foreach($M in $CacheMP[$ComputerName]) {
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
        Write-Verbose "$Source.[$SourceDatabase] -> $Destination.[$DestinationDatabase]"

        $DB1 = Get-DbaDatabase -SqlInstance $Source -Database $SourceDatabase -SqlCredential $SourceSqlCredential
        if(!$DB1) {
            Stop-Function -Message "Database [$SourceDatabase] MUST exist on Source Instance $Source." -ErrorRecord $_
        }
<<<<<<< HEAD
        $DataFiles1 = @($DB1.FileGroups.Files | Select-Object Name, Filename, Size, @{n='Type';e={'Data'}})
        $DataFiles1 += @($DB1.LogFiles        | Select-Object Name, Filename, Size, @{n='Type';e={'Log'}})
        
=======
        $DF1 = @($DB1.FileGroups.Files | Select-Object Name, Filename, Size, @{n='Type';e={'Data'}})
        $DF1 += @($DB1.LogFiles        | Select-Object Name, Filename, Size, @{n='Type';e={'Log'}})

>>>>>>> 2a270a12ba1034904387e0ad53530eb79ee904b3
        #if(!$DestinationDatabase) {throw "DestinationDatabase [$DestinationDatabase] "}

        if($DB2 = Get-DbaDatabase -SqlInstance $Destination -Database $DestinationDatabase -SqlCredential $DestinationSqlCredential) {
            $DataFiles2 = @($DB2.FileGroups.Files | Select-Object Name, Filename, Size, @{n='Type';e={'Data'}})
            $DataFiles2 += @($DB2.LogFiles        | Select-Object Name, Filename, Size, @{n='Type';e={'Log'}})
            $ComputerName = $DB2.ComputerName
        } else {
            Write-Verbose "Database [$DestinationDatabase] does not exist on Destination Instance $Destination."
            $ComputerName = (Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential).NetName
        }

        foreach($File1 in $DataFiles1) {
            foreach($File2 in $DataFiles2) {
                if($found = ($File1.Name -eq $File2.Name)) { # Files found on both sides
                    $Detail += @([PSCustomObject]@{
                        DatabaseName1 = $DB1.Name
                        DatabaseName2 = $DB2.Name
                        Name1 = $File1.Name
                        Name2 = $File2.Name
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
                    DatabaseName1 = $DB1.Name
                    DatabaseName2 = $DestinationDatabase
                    Name1 = $File1.Name
                    Name2 = $NullText
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
                    DatabaseName1 = $SourceDatabase
                    DatabaseName2 = $DB2.Name
                    Name1 = $NullText
                    Name2 = $File3.Name
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
        if($Consolidate) {
            $Detail | Format-Table -AutoSize
            $Detail | Group-Object -Property ComputerName, MountPoint | ForEach-Object {
                $Required = New-Object Sqlcollaborative.Dbatools.Utility.Size (($_.Group | Measure-Object DiffKB -Sum).Sum * 1024)
                $MountPoint = ($CacheMP[$ComputerName] | Where-Object Name -eq $_.Group.MountPoint[0])
                @([PSCustomObject]@{
                    ComputerName = $_.Group.ComputerName[0]
                    MountPoint = if($_.Group.MountPoint[0]) {$_.Group.MountPoint[0]} else {0}
<<<<<<< HEAD
                    RequiredSpaceKB = $Required 
                    Capacity = $MountPoint.Capacity
                    FreeSpace = $MountPoint.Free
                    FutureFree = $MountPoint.Free - $Required
=======
                    RequiredSpaceKB = $Required
                    Capacity = $MP.Capacity
                    FreeSpace = $MP.Free
                    FutureFree = $MP.Free - $Required
>>>>>>> 2a270a12ba1034904387e0ad53530eb79ee904b3
                })
            }
        } else {
            $Detail
        }
    }
}



<<<<<<< HEAD


=======
Function Get-MountPointFromDefaultPath {
    # Extract MountPoint from DefaultPath. Usefull when database or file does not exist on destination.
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
            Write-Verbose "CacheDP[$SqlInstance] is in cache"
        } catch {
            Write-Warning "Can't connect to $SqlInstance"
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
            Write-Warning "Can't connect to $ComputerName."
            $CacheMP.Add($ComputerName,'?')
            return '?'
        }
    }
    if($DefaultPathType -eq 'Log') {
        $Path = $CacheDP[$SqlInstance].Log
    } else {
        $Path = $CacheDP[$SqlInstance].Data
    }
    foreach($M in $CacheMP[$ComputerName]) {
        if($Path -like "$($M.Name)*") {
            return $M.Name
        }
    }
}
>>>>>>> 2a270a12ba1034904387e0ad53530eb79ee904b3
