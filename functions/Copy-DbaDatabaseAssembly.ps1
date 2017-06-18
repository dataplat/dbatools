function Copy-DbaDatabaseAssembly {
    <#
		.SYNOPSIS 
			Copy-DbaDatabaseAssembly migrates assemblies from one SQL Server to another. 

		.DESCRIPTION
			By default, all assemblies are copied. The -Assemblies parameter is autopopulated for command-line completion and can be used to copy only specific assemblies.

			If the assembly already exists on the destination, it will be skipped unless -Force is used. 
				
			This script does not yet copy dependents.

		.PARAMETER Source
			Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER SourceSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Destination
			Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

		.PARAMETER DestinationSqlCredential
			Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

			$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter. 

			Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Assembly
			The assembly(ies) to process - this list is auto populated from the server. If unspecified, all assemblies will be processed.

		.PARAMETER ExcludeAssembly
			The assembly(ies) to exclude - this list is auto populated from the server

		.PARAMETER WhatIf 
			Shows what would happen if the command were to run. No actions are actually performed. 

		.PARAMETER Confirm 
			Prompts you for confirmation before executing any changing operations within the command. 

		.PARAMETER Force
			Drops and recreates the XXXXX if it exists

		.PARAMETER Silent 
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, Assembly
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			http://dbatools.io/Get-SqlDatabaseAssembly

		.EXAMPLE   
			Copy-DbaDatabaseAssembly -Source sqlserver2014a -Destination sqlcluster

			Copies all assemblies from sqlserver2014a to sqlcluster, using Windows credentials. If assemblies with the same name exist on sqlcluster, they will be skipped.

		.EXAMPLE   
			Copy-DbaDatabaseAssembly -Source sqlserver2014a -Destination sqlcluster -Assemblies dbname.assemblyname, dbname3.anotherassembly -SourceSqlCredential $cred -Force

			Copies two assemblies, the dbname.assemblyname and dbname3.anotherassembly, from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a assembly with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.
				
			In this example, anotherassembly will be copied to the dbname3 database on the server "sqlcluster".
			
		.EXAMPLE   
			Copy-DbaThing -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

			Shows what would happen if the command were executed using force.
	#>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [System.Management.Automation.PSCredential]$SourceSqlCredential,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [System.Management.Automation.PSCredential]$DestinationSqlCredential,
        [object[]]$Assembly,
		[object[]]$ExcludeAssembly,
        [switch]$Force,
        [switch]$Silent
    )
    begin {
		
        $sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
		
        $source = $sourceserver.DomainInstanceName
        $destination = $destserver.DomainInstanceName
		
        if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9) {
            throw "Assemblies are only supported in SQL Server 2005 and above. Quitting."
        }
	
    }
    process {
		
        $sourceassemblies = @()
        foreach ($database in $sourceserver.Databases) {
            try {
                # a bug here requires a try/catch
                $userassemblies = $database.assemblies | Where-Object { $_.isSystemObject -eq $false }
                foreach ($assembly in $userassemblies) {
                    $sourceassemblies += $assembly
                }
            }
            catch { }
        }
		
        $destassemblies = @()
        foreach ($database in $destserver.Databases) {
            try {
                # a bug here requires a try/catch
                $userassemblies = $database.assemblies | Where-Object { $_.isSystemObject -eq $false }
                foreach ($assembly in $userassemblies) {
                    $destassemblies += $assembly
                }
            }
            catch { }
        }
		
        foreach ($assembly in $sourceassemblies) {
            $assemblyname = $assembly.Name
            $dbname = $assembly.Parent.Name
            $destdb = $destserver.Databases[$dbname]
			
            if ($destdb -eq $null) { Write-Warning "Destination database $dbname does not exist. Skipping $assemblyname."; continue }
            if ($assemblies.length -gt 0 -and $assemblies -notcontains "$dbname.$assemblyname") { continue }
			
            if ($assembly.AssemblySecurityLevel -eq "External" -and $destdb.Trustworthy -eq $false) {
                If ($Pscmdlet.ShouldProcess($destination, "Setting $dbname to External")) {
                    Write-Warning "Setting $dbname Security Level to External on $destination"
                    $sql = "ALTER DATABASE $dbname SET TRUSTWORTHY ON"
                    try {
                        $destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
                    }
                    catch { Write-Exception $_ }
                }
            }
			
			
            if ($destserver.Databases[$dbname].Assemblies.Name -contains $assembly.name) {
                if ($force -eq $false) {
                    Write-Warning "Assembly $assemblyname exists at destination in the $dbname database. Use -Force to drop and migrate."
                    continue
                }
                else {
                    If ($Pscmdlet.ShouldProcess($destination, "Dropping assembly $assemblyname and recreating")) {
                        try {
                            Write-Output "Dropping assembly $assemblyname"
                            Write-Output "This won't work if there are dependencies."
                            $destserver.Databases[$dbname].Assemblies[$assemblyname].Drop()
                            Write-Output "Copying assembly $assemblyname"
                            $destserver.Databases[$dbname].ExecuteNonQuery($assembly.Script()) | Out-Null
                        }
                        catch { 
                            Write-Exception $_ 
                            continue
                        }
                    }
                }
            }
			
            If ($Pscmdlet.ShouldProcess($destination, "Creating assembly $assemblyname")) {
                try {
                    Write-Output "Copying assembly $assemblyname from database."
                    $destserver.Databases[$dbname].ExecuteNonQuery($assembly.Script()) | Out-Null
                }
                catch {
                    Write-Exception $_
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlDatabaseAssembly
    }
}
