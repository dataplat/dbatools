function Copy-DbaDbAssembly {
    <#
    .SYNOPSIS
        Copies CLR assemblies from source databases to destination SQL Server instances

    .DESCRIPTION
        Migrates custom CLR assemblies from databases on a source SQL Server to corresponding databases on destination instances. This function scans all accessible databases for user-created assemblies and recreates them on the target servers, automatically handling security requirements like setting the TRUSTWORTHY property for external assemblies.

        Designed for database migration scenarios where applications rely on custom .NET assemblies registered in SQL Server. If assemblies already exist on the destination, they're skipped unless you use -Force to drop and recreate them.

        The function does not copy assembly dependencies or dependent objects like CLR stored procedures, functions, or user-defined types that reference the assemblies.

    .PARAMETER Source
        Source SQL Server instance containing the CLR assemblies to copy. Requires sysadmin access to scan all accessible databases for user-created assemblies.
        The function will inventory all custom assemblies across every database on this instance for migration.

    .PARAMETER SourceSqlCredential
        Alternative credentials for connecting to the source SQL Server instance. Use this when your current Windows credentials don't have sysadmin access to the source server.
        Accepts PowerShell credential objects created with Get-Credential and supports SQL Server Authentication or Active Directory authentication methods.

    .PARAMETER Destination
        Target SQL Server instance(s) where CLR assemblies will be created. Accepts multiple destinations to copy assemblies to several servers simultaneously.
        Requires sysadmin access and corresponding databases must already exist on the destination for assembly migration to succeed.

    .PARAMETER DestinationSqlCredential
        Alternative credentials for connecting to the destination SQL Server instance(s). Use this when your current Windows credentials don't have sysadmin access to the target servers.
        Accepts PowerShell credential objects created with Get-Credential and supports SQL Server Authentication or Active Directory authentication methods.

    .PARAMETER Assembly
        Specific CLR assemblies to copy instead of migrating all assemblies. Use the format 'DatabaseName.AssemblyName' to target assemblies in specific databases.
        This is useful when you only need to migrate certain assemblies rather than performing a full assembly migration across all databases.

    .PARAMETER ExcludeAssembly
        CLR assemblies to skip during the migration process. Use the format 'DatabaseName.AssemblyName' to exclude specific assemblies from specific databases.
        This is helpful when you want to migrate most assemblies but need to skip problematic or obsolete ones that shouldn't be copied to the destination.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Drops existing assemblies on the destination before recreating them from the source. By default, assemblies that already exist are skipped.
        Use this when you need to overwrite destination assemblies with updated versions from the source, but be aware that assemblies with dependencies cannot be dropped.

    .NOTES
        Tags: Migration, Assembly
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaDbAssembly

    .OUTPUTS
        MigrationObject (PSCustomObject)

        Returns one object per assembly processed, documenting the copy operation result for each assembly migration attempt.

        Default display properties (via Select-DefaultView):
        - DateTime: Timestamp when the operation was performed
        - SourceServer: Name of the source SQL Server instance
        - DestinationServer: Name of the destination SQL Server instance
        - Name: Name of the assembly being copied
        - Type: Always "Database Assembly" indicating the object type
        - Status: Result of the operation (Successful, Skipped, or Failed)
        - Notes: Additional information about why the operation was skipped or failed (null if successful)

        Additional properties available:
        - SourceDatabase: Database name on the source server containing the assembly
        - SourceDatabaseID: Unique identifier of the source database
        - DestinationDatabase: Database name on the destination server
        - DestinationDatabaseID: Unique identifier of the destination database

    .EXAMPLE
        PS C:\> Copy-DbaDbAssembly -Source sqlserver2014a -Destination sqlcluster

        Copies all assemblies from sqlserver2014a to sqlcluster using Windows credentials. If assemblies with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaDbAssembly -Source sqlserver2014a -Destination sqlcluster -Assembly dbname.assemblyname, dbname3.anotherassembly -SourceSqlCredential $cred -Force

        Copies two assemblies, the dbname.assemblyname and dbname3.anotherassembly from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If an assembly with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

        In this example, anotherassembly will be copied to the dbname3 database on the server sqlcluster.

    .EXAMPLE
        PS C:\> Copy-DbaDbAssembly -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [object[]]$Assembly,
        [object[]]$ExcludeAssembly,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        $sourceAssemblies = @()
        foreach ($database in ($sourceServer.Databases | Where-Object IsAccessible)) {
            Write-Message -Level Verbose -Message "Processing $database on source"

            try {
                # a bug here requires a try/catch
                $userAssemblies = $database.Assemblies | Where-Object IsSystemObject -eq $false
                foreach ($asmb in $userAssemblies) {
                    $sourceAssemblies += $asmb
                }
            } catch {
                #here to avoid an empty catch
                $null = 1
            }
        }

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            $destAssemblies = @()
            foreach ($database in $destServer.Databases) {
                Write-Message -Level VeryVerbose -Message "Processing $database on destination"
                try {
                    # a bug here requires a try/catch
                    $userAssemblies = $database.Assemblies | Where-Object IsSystemObject -eq $false
                    foreach ($asmb in $userAssemblies) {
                        $destAssemblies += $asmb
                    }
                } catch {
                    #here to avoid an empty catch
                    $null = 1
                }
            }
            foreach ($currentAssembly in $sourceAssemblies) {
                $assemblyName = $currentAssembly.Name
                $dbName = $currentAssembly.Parent.Name
                $destDb = $destServer.Databases[$dbName]
                Write-Message -Level VeryVerbose -Message "Processing $assemblyName on $dbName"
                $copyDbAssemblyStatus = [PSCustomObject]@{
                    SourceServer          = $sourceServer.Name
                    SourceDatabase        = $dbName
                    SourceDatabaseID      = $currentAssembly.Parent.ID
                    DestinationServer     = $destServer.Name
                    DestinationDatabase   = $destDb
                    DestinationDatabaseID = $destDb.ID
                    type                  = "Database Assembly"
                    Name                  = $assemblyName
                    Status                = $null
                    Notes                 = $null
                    DateTime              = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                }


                if (!$destDb) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Destination database $dbName does not exist. Skipping $assemblyName.")) {
                        Write-Message -Level Verbose -Message "Destination database $dbName does not exist. Skipping $assemblyName."
                        $copyDbAssemblyStatus.Status = "Skipped"
                        $copyDbAssemblyStatus.Notes = "Destination database does not exist"
                        $copyDbAssemblyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                }

                if ((Test-Bound -ParameterName Assembly) -and $Assembly -notcontains "$dbName.$assemblyName" -or $ExcludeAssembly -contains "$dbName.$assemblyName") {
                    continue
                }

                if ($currentAssembly.AssemblySecurityLevel -eq "External" -and -not $destDb.Trustworthy) {
                    if ($Pscmdlet.ShouldProcess($destinstance, "Setting $dbName to External")) {
                        Write-Message -Level Verbose -Message "Setting $dbName Security Level to External on $destinstance."
                        $sql = "ALTER DATABASE $dbName SET TRUSTWORTHY ON"
                        try {
                            Write-Message -Level Debug -Message $sql
                            $destServer.Query($sql)
                        } catch {
                            $copyDbAssemblyStatus.Status = "Failed to set security level to external"
                            $copyDbAssemblyStatus.Notes = "$PSItem"
                            $copyDbAssemblyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Failed to set security level to external for $dbName on $destinstance | $PSItem"
                            continue
                        }
                    }
                }

                if ($destDb.Query("SELECT name FROM sys.assemblies WHERE name = '$assemblyName'").name) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Assembly $assemblyName exists at destination in the $dbName database. Use -Force to drop and migrate.")) {
                            Write-Message -Level Verbose -Message "Assembly $assemblyName exists at destination in the $dbName database. Use -Force to drop and migrate."
                            $copyDbAssemblyStatus.Status = "Skipped"
                            $copyDbAssemblyStatus.Notes = "Already exists on destination"
                            $copyDbAssemblyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping assembly $assemblyName on $($destDb.Name) on $($destServer.Name)")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping assembly $assemblyName."

                                if ($destDb.Query("SELECT a.name FROM sys.assemblies a WHERE a.name = '$assemblyName' AND EXISTS (SELECT 1 FROM sys.assembly_references b WHERE b.assembly_id = a.assembly_id OR b.referenced_assembly_id = a.assembly_id)").name) {
                                    Write-Message -Level Verbose -Message "This won't work if there are dependencies."
                                    throw "$assemblyName has dependencies but this command does not yet support dependent objects"
                                }

                                $destDb.Query("DROP ASSEMBLY $assemblyName")
                            } catch {
                                $copyDbAssemblyStatus.Status = "Failed"
                                $copyDbAssemblyStatus.Notes = "$PSItem"
                                $copyDbAssemblyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Failed to drop assembly $assemblyName for $dbName on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating assembly $assemblyName")) {
                    try {
                        Write-Message -Level Verbose -Message "Copying assembly $assemblyName from database."
                        $sql = $currentAssembly.Script()
                        Write-Message -Level Debug -Message ($sql -join ' ')
                        $destDb.Query($sql, $dbName)

                        $copyDbAssemblyStatus.Status = "Successful"
                        $copyDbAssemblyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                    } catch {
                        $copyDbAssemblyStatus.Status = "Failed"
                        $copyDbAssemblyStatus.Notes = $PSItem
                        $copyDbAssemblyStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Failed to create assembly $assemblyName for $dbName on $destinstance | $PSItem"
                        continue
                    }
                }
            }
        }
    }
}