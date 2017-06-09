function Copy-DbaAgentCategory {
    <#
		.SYNOPSIS 
			Copy-DbaAgentCategory migrates SQL Agent categories from one SQL Server to another. This is similar to sp_add_category.

			https://msdn.microsoft.com/en-us/library/ms181597.aspx

		.DESCRIPTION
			By default, all SQL Agent categories for Jobs, Operators and Alerts are copied. 

			The -OperatorCategories parameter is autopopulated for command-line completion and can be used to copy only specific operator categories.
			The -AgentCategories parameter is autopopulated for command-line completion and can be used to copy only specific agent categories.
			The -JobCategories parameter is autopopulated for command-line completion and can be used to copy only specific job categories.

			If the category already exists on the destination, it will be skipped unless -Force is used.  

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

		.PARAMETER CategoryType
			Specifies the Category Type to migrate. Valid options are Job, Alert and Operator. When CategoryType is specified, all categories from the selected type will be migrated. For granular migrations, use the three parameters below.

		.PARAMETER OperatorCategory
			This parameter is autopopulated for command-line completion and can be used to copy only specific operator categories.

		.PARAMETER AgentCategory
			This parameter is autopopulated for command-line completion and can be used to copy only specific agent categories.

		.PARAMETER JobCategory
			This parameter is autopopulated for command-line completion and can be used to copy only specific job categories.

		.PARAMETER WhatIf 
			Shows what would happen if the command were to run. No actions are actually performed. 

		.PARAMETER Confirm 
			Prompts you for confirmation before executing any changing operations within the command. 

		.PARAMETER Force
			Drops and recreates the XXXXX if it exists

		.PARAMETER Silent 
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, Agent
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaAgentCategory

		.EXAMPLE   
			Copy-DbaAgentCategory -Source sqlserver2014a -Destination sqlcluster

			Copies all operator categories from sqlserver2014a to sqlcluster, using Windows credentials. If operator categories with the same name exist on sqlcluster, they will be skipped.

		.EXAMPLE   
			Copy-DbaAgentCategory -Source sqlserver2014a -Destination sqlcluster -OperatorCategory PSOperator -SourceSqlCredential $cred -Force

			Copies a single operator category, the PSOperator operator category from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a operator category with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

		.EXAMPLE   
			Copy-DbaAgentCategory -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

			Shows what would happen if the command were executed using force.
	#>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldprocess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [System.Management.Automation.PSCredential]$SourceSqlCredential,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [System.Management.Automation.PSCredential]$DestinationSqlCredential,
        [Parameter(ParameterSetName = 'SpecifcAlerts')]
        [ValidateSet('Job', 'Alert', 'Operator')]
        [string[]]$CategoryType,
        [switch]$Force,
		[switch]$Silent
    )

    begin {
		
        Function Copy-JobCategory {
            <#
				.SYNOPSIS 
					Copy-JobCategory migrates job categories from one SQL Server to another. 

				.DESCRIPTION
					By default, all job categories are copied. The -JobCategories parameter is autopopulated for command-line completion and can be used to copy only specific job categories.

					If the associated credential for the category does not exist on the destination, it will be skipped. If the job category already exists on the destination, it will be skipped unless -Force is used.  
			#>
            param (
                [string[]]$JobCategories
            )
			
            process {
				
                $serverjobcategories = $sourceserver.JobServer.JobCategories | Where-Object { $_.ID -ge 100 }
                $destjobcategories = $destserver.JobServer.JobCategories | Where-Object { $_.ID -ge 100 }
				
                foreach ($jobcategory in $serverjobcategories) {
                    $categoryname = $jobcategory.name
                    if ($jobcategories.count -gt 0 -and $jobcategories -notcontains $categoryname) { continue }
					
                    if ($destjobcategories.name -contains $jobcategory.name) {
                        if ($force -eq $false) {
                            Write-Warning "Job category $categoryname exists at destination. Use -Force to drop and migrate."
                            continue
                        }
                        else {
                            If ($Pscmdlet.ShouldProcess($destination, "Dropping job category $categoryname and recreating")) {
                                try {
                                    Write-Verbose "Dropping Job category $categoryname"
                                    $destserver.jobserver.jobcategories[$categoryname].Drop()
									
                                }
                                catch { 
                                    Write-Exception $_ 
                                    continue
                                }
                            }
                        }
                    }
					
                    If ($Pscmdlet.ShouldProcess($destination, "Creating Job category $categoryname")) {
                        try {
                            Write-Output "Copying Job category $categoryname"
                            $sql = $jobcategory.Script() | Out-String
                            $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                            Write-Verbose $sql
                            $destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
                        }
                        catch {
                            Write-Exception $_
                        }
                    }
                }
            }
        }
		
        Function Copy-OperatorCategory {
            <#
				.SYNOPSIS 
					Copy-OperatorCategory migrates operator categories from one SQL Server to another. 

				.DESCRIPTION
					By default, all operator categories are copied. The -OperatorCategories parameter is autopopulated for command-line completion and can be used to copy only specific operator categories.

					If the associated credential for the category does not exist on the destination, it will be skipped. If the operator category already exists on the destination, it will be skipped unless -Force is used.  
			#>
            [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldprocess = $true)]
            param (
                [string[]]$OperatorCategories
            )
			
            process {
                $serveroperatorcategories = $sourceserver.JobServer.OperatorCategories | Where-Object { $_.ID -ge 100 }
                $destoperatorcategories = $destserver.JobServer.OperatorCategories | Where-Object { $_.ID -ge 100 }
				
                foreach ($operatorcategory in $serveroperatorcategories) {
                    $categoryname = $operatorcategory.name
				
                    if ($operatorcategories.count -gt 0 -and $operatorcategories -notcontains $categoryname) { continue }
					
                    if ($destoperatorcategories.name -contains $operatorcategory.name) {
                        if ($force -eq $false) {
                            Write-Warning "Operator category $categoryname exists at destination. Use -Force to drop and migrate."
                            continue
                        }
                        else {
                            If ($Pscmdlet.ShouldProcess($destination, "Dropping operator category $categoryname and recreating")) {
                                try {
                                    Write-Verbose "Dropping Operator category $categoryname"
                                    $destserver.jobserver.operatorcategories[$categoryname].Drop()
                                    Write-Output "Copying Operator category $categoryname"
                                    $sql = $operatorcategory.Script() | Out-String
                                    $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                                    Write-Verbose $sql
                                    $destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
                                }
                                catch { Write-Exception $_ }
                            }
                        }
                    }
                    else {
                        If ($Pscmdlet.ShouldProcess($destination, "Creating Operator category $categoryname")) {
                            try {
                                Write-Output "Copying Operator category $categoryname"
                                $sql = $operatorcategory.Script() | Out-String
                                $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                                Write-Verbose $sql
                                $destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
                            }
                            catch {
                                Write-Exception $_
                            }
                        }
                    }
                }
            }
        }
		
        Function Copy-AlertCategory {
            <#
				.SYNOPSIS 
					Copy-AlertCategory migrates alert categories from one SQL Server to another. 

				.DESCRIPTION
					By default, all alert categories are copied. The -AlertCategories parameter is autopopulated for command-line completion and can be used to copy only specific alert categories.

					If the associated credential for the category does not exist on the destination, it will be skipped. If the alert category already exists on the destination, it will be skipped unless -Force is used.  			
			#>
            [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldprocess = $true)]
            param (
                [string[]]$AlertCategories
            )

            process {
                if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9) {
                    throw "Server AlertCategories are only supported in SQL Server 2005 and above. Quitting."
                }
				
                $serveralertcategories = $sourceserver.JobServer.AlertCategories | Where-Object { $_.ID -ge 100 }
                $destalertcategories = $destserver.JobServer.AlertCategories | Where-Object { $_.ID -ge 100 }
				
                foreach ($alertcategory in $serveralertcategories) {
                    $categoryname = $alertcategory.name
                    if ($alertcategories.length -gt 0 -and $alertcategories -notcontains $categoryname) { continue }
					
                    if ($destalertcategories.name -contains $alertcategory.name) {
                        if ($force -eq $false) {
                            Write-Warning "Alert category $categoryname exists at destination. Use -Force to drop and migrate."
                            continue
                        }
                        else {
                            If ($Pscmdlet.ShouldProcess($destination, "Dropping alert category $categoryname and recreating")) {
                                try {
                                    Write-Verbose "Dropping Alert category $categoryname"
                                    $destserver.jobserver.alertcategories[$categoryname].Drop()
                                    Write-Output "Copying Alert category $categoryname"
                                    $sql = $alertcategory.Script() | Out-String
                                    $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                                    Write-Verbose $sql
                                    $destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
                                }
                                catch { Write-Exception $_ }
                            }
                        }
                    }
                    else {
                        If ($Pscmdlet.ShouldProcess($destination, "Creating Alert category $categoryname")) {
                            try {
                                Write-Output "Copying Alert category $categoryname"
                                $sql = $alertcategory.Script() | Out-String
                                $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                                Write-Verbose $sql
                                $destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
                            }
                            catch {
                                Write-Exception $_
                            }
                        }
                    }
                }
            }
        }
		
        $sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
		
        $source = $sourceserver.DomainInstanceName
        $destination = $destserver.DomainInstanceName
		
    }
    process {
        if ($CategoryType.count -gt 0) {
			
            switch ($CategoryType) {
                "Job" {
                    Copy-JobCategory
                }
				
                "Alert" {
                    Copy-AlertCategory
                }
				
                "Operator" {
                    Copy-OperatorCategory
                }
            }
			
            return
        }
		
        if (($OperatorCategory.Count + $AlertCategory.Count + $JobCategory.Count) -gt 0) {
			
            if ($OperatorCategory.Count -gt 0) {
                Copy-OperatorCategory -OperatorCategories $OperatorCategory 
            }
			
            if ($AlertCategory.Count -gt 0) {
                Copy-AlertCategory -AlertCategories $AlertCategory 
            }
			
            if ($JobCategory.Count -gt 0) {
                Copy-JobCategory -JobCategories $JobCategory 
            }

            return
        }
		
        Copy-OperatorCategory 
        Copy-AlertCategory 
        Copy-JobCategory 
    }	
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlAgentCategory
    }
}
