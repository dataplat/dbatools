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
        [PSCredential][System.Management.Automation.CredentialAttribute()]
        $SourceSqlCredential,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [PSCredential][System.Management.Automation.CredentialAttribute()]
        $DestinationSqlCredential,
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
				
                $serverJobCategories = $sourceServer.JobServer.JobCategories | Where-Object ID -ge 100
                $destJobCategories = $destServer.JobServer.JobCategories | Where-Object ID -ge 100
				
                foreach ($jobCategory in $serverJobCategories) {
                    $categoryName = $jobCategory.Name
                    if ($JobCategories.Count -gt 0 -and $JobCategories -notcontains $categoryName) { continue }
					
                    if ($destJobCategories.Name -contains $jobCategory.name) {
                        if ($force -eq $false) {
                            Write-Warning "Job category $categoryName exists at destination. Use -Force to drop and migrate."
                            continue
                        }
                        else {
                            if ($Pscmdlet.ShouldProcess($destination, "Dropping job category $categoryName and recreating")) {
                                try {
                                    Write-Verbose "Dropping Job category $categoryName"
                                    $destServer.JobServer.JobCategories[$categoryName].Drop()
                                }
                                catch { 
                                    Write-Exception $_ 
                                    continue
                                }
                            }
                        }
                    }
					
                    if ($Pscmdlet.ShouldProcess($destination, "Creating Job category $categoryName")) {
                        try {
                            Write-Output "Copying Job category $categoryName"
                            $sql = $jobCategory.Script() | Out-String
                            $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                            Write-Verbose $sql
                            $destServer.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
                        }
                        catch {
                            Write-Exception $_
                        }
                    }
                }
            }
        }
		
        function Copy-OperatorCategory {
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
                $serverOperatorCategories = $sourceServer.JobServer.OperatorCategories | Where-Object ID -ge 100
                $destOperatorCategories = $destServer.JobServer.OperatorCategories | Where-Object ID -ge 100
				
                foreach ($operatorCategory in $serverOperatorCategories) {
                    $categoryName = $operatorCategory.Name
				
                    if ($operatorCategories.Count -gt 0 -and $operatorCategories -notcontains $categoryName) { continue }
					
                    if ($destOperatorCategories.Name -contains $operatorCategory.Name) {
                        if ($force -eq $false) {
                            Write-Warning "Operator category $categoryName exists at destination. Use -Force to drop and migrate."
                            continue
                        }
                        else {
                            if ($Pscmdlet.ShouldProcess($destination, "Dropping operator category $categoryName and recreating")) {
                                try {
                                    Write-Verbose "Dropping Operator category $categoryName"
                                    $destServer.JobServer.OperatorCategories[$categoryName].Drop()
                                    Write-Output "Copying Operator category $categoryName"
                                    $sql = $operatorCategory.Script() | Out-String
                                    $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                                    Write-Verbose $sql
                                    $destServer.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
                                }
                                catch { Write-Exception $_ }
                            }
                        }
                    }
                    else {
                        if ($Pscmdlet.ShouldProcess($destination, "Creating Operator category $categoryName")) {
                            try {
                                Write-Output "Copying Operator category $categoryName"
                                $sql = $operatorCategory.Script() | Out-String
                                $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                                Write-Verbose $sql
                                $destServer.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
                            }
                            catch {
                                Write-Exception $_
                            }
                        }
                    }
                }
            }
        }
		
        function Copy-AlertCategory {
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
                if ($sourceServer.VersionMajor -lt 9 -or $destServer.VersionMajor -lt 9) {
                    throw "Server AlertCategories are only supported in SQL Server 2005 and above. Quitting."
                }
				
                $serverAlertCategories = $sourceServer.JobServer.AlertCategories | Where-Object ID -ge 100
                $destAlertCategories = $destServer.JobServer.AlertCategories | Where-Object ID -ge 100
				
                foreach ($alertCategory in $serverAlertCategories) {
                    $categoryName = $alertCategory.Name
                    if ($alertCategories.Length -gt 0 -and $alertCategories -notcontains $categoryName) { continue }
					
                    if ($destAlertCategories.Name -contains $alertCategory.name) {
                        if ($force -eq $false) {
                            Write-Warning "Alert category $categoryName exists at destination. Use -Force to drop and migrate."
                            continue
                        }
                        else {
                            if ($Pscmdlet.ShouldProcess($destination, "Dropping alert category $categoryName and recreating")) {
                                try {
                                    Write-Verbose "Dropping Alert category $categoryName"
                                    $destServer.JobServer.AlertCategories[$categoryName].Drop()
                                    Write-Output "Copying Alert category $categoryName"
                                    $sql = $alertcategory.Script() | Out-String
                                    $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                                    Write-Verbose $sql
                                    $destServer.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
                                }
                                catch { Write-Exception $_ }
                            }
                        }
                    }
                    else {
                        if ($Pscmdlet.ShouldProcess($destination, "Creating Alert category $categoryName")) {
                            try {
                                Write-Output "Copying Alert category $categoryName"
                                $sql = $alertCategory.Script() | Out-String
                                $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destination'"
                                Write-Verbose $sql
                                $destServer.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
                            }
                            catch {
                                Write-Exception $_
                            }
                        }
                    }
                }
            }
        }
		
        $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
		
        $source = $sourceServer.DomainInstanceName
        $destination = $destServer.DomainInstanceName
		
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
		
        if (($OperatorCategory.Count + $AlertCategory.Count + $jobCategory.Count) -gt 0) {
			
            if ($OperatorCategory.Count -gt 0) {
                Copy-OperatorCategory -OperatorCategories $OperatorCategory 
            }
			
            if ($AlertCategory.Count -gt 0) {
                Copy-AlertCategory -AlertCategories $AlertCategory 
            }
			
            if ($jobCategory.Count -gt 0) {
                Copy-JobCategory -JobCategories $jobCategory 
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
