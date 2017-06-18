function Copy-DbaCustomError {
    <#
		.SYNOPSIS 
			Copy-DbaCustomError migrates custom errors (user defined messages), by the customer error ID, from one SQL Server to another.

		.DESCRIPTION
			By default, all custom errors are copied. The -CustomError parameter is auto-populated for command-line completion and can be used to copy only specific custom errors.

			If the custom error already exists on the destination, it will be skipped unless -Force is used. Interesting fact, if you drop the us_english version, all the other languages will be dropped for that specific ID as well.

			Also, the us_english version must be created first.
			
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

		.PARAMETER CustomError
			The customer error(s) to process - this list is auto populated from the server. If unspecified, all customer errors will be processed.

		.PARAMETER ExcludeCustomError
			The custom error(s) to exclude - this list is auto populated from the server

		.PARAMETER WhatIf 
			Shows what would happen if the command were to run. No actions are actually performed. 

		.PARAMETER Confirm 
			Prompts you for confirmation before executing any changing operations within the command. 

		.PARAMETER Force
			Drops and recreates the XXXXX if it exists

		.PARAMETER Silent 
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Migration, CustomError
			Author: Chrissy LeMaire (@cl), netnerds.net
			Requires: sysadmin access on SQL Servers

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Copy-DbaCustomError

		.EXAMPLE   
			Copy-DbaCustomError -Source sqlserver2014a -Destination sqlcluster

			Copies all server custom errors from sqlserver2014a to sqlcluster, using Windows credentials. If custom errors with the same name exist on sqlcluster, they will be skipped.

		.EXAMPLE
			Copy-DbaCustomError -Source sqlserver2014a -SourceSqlCredential $scred -Destination sqlcluster -DestinationSqlCredential $dcred -CustomError 60000 -Force

			Copies a single custom error, the custom error with ID number 60000 from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a custom error with the same name exists on sqlcluster, it will be updated because -Force was used.

		.EXAMPLE
			Copy-DbaCustomError -Source slserver2014a -Destination sqlcluster -ExcludeCustomError 60000 -Force

			Copies all the custom errors found on sqlserver2014a, except the custom error with ID number 60000. If a custom error with the same name exists on sqlcluster, it will be updated because -Force was used.

		.EXAMPLE   
			Copy-DbaCustomError -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

			Shows what would happen if the command were executed using force.
	#>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Source,
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$Destination,
        [System.Management.Automation.PSCredential]$SourceSqlCredential,
        [System.Management.Automation.PSCredential]$DestinationSqlCredential,
        [switch]$Force
    )

	
    begin {

        $sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
		
        $source = $sourceserver.DomainInstanceName
        $destination = $destserver.DomainInstanceName
		
        if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9) {
            throw "Custom Errors are only supported in SQL Server 2005 and above. Quitting."
        }
    }
	
    process {

        # Us has to go first
        $orderedcustomerrors = @($sourceserver.UserDefinedMessages | Where-Object { $_.Language -eq "us_english" })
        $orderedcustomerrors += $sourceserver.UserDefinedMessages | Where-Object { $_.Language -ne "us_english" }
        $destcustomerrors = $destserver.UserDefinedMessages
		
        foreach ($customerror in $orderedcustomerrors) {
            $customerrorid = $customerror.ID
            $language = $customerror.language.ToString()
			
            if ($customerrors.length -gt 0 -and $customerrors -notcontains $customerrorid) { continue }
			
            if ($destcustomerrors.ID -contains $customerror.ID) {
                if ($force -eq $false) {
                    Write-Warning "Custom error $customerrorid $language exists at destination. Use -Force to drop and migrate."
                    continue
                }
                else {
                    If ($Pscmdlet.ShouldProcess($destination, "Dropping custom error $customerrorid $language and recreating")) {
                        try {
                            Write-Verbose "Dropping custom error $customerrorid (drops all languages for custom error $customerrorid)"
                            $destserver.UserDefinedMessages[$customerrorid, $language].Drop()
                        }
                        catch { 
                            Write-Exception $_ 
                            continue
                        }
                    }
                }
            }
			
            If ($Pscmdlet.ShouldProcess($destination, "Creating custom error $customerrorid $language")) {
                try {
                    Write-Output "Copying custom error $customerrorid $language"
                    $sql = $customerror.Script() | Out-String
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
	
    end {
        $sourceserver.ConnectionContext.Disconnect()
        $destserver.ConnectionContext.Disconnect()
        If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Custom error migration finished" }
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlCustomError
    }
} 
