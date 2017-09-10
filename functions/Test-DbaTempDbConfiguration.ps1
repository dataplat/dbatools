function Test-DbaTempDbConfiguration {
	<#
		.SYNOPSIS
			Evaluates tempdb against several rules to match best practices.

		.DESCRIPTION
			Evaluates tempdb against a set of rules to match best practices. The rules are:
			
			* TF 1118 enabled - Is Trace Flag 1118 enabled (See KB328551).
			* File Count - Does the count of data files in tempdb match the number of logical cores, up to 8?
			* File Growth - Are any files set to have percentage growth? Best practice is all files have an explicit growth value.
			* File Location - Is tempdb located on the C:\? Best practice says to locate it elsewhere.
			* File MaxSize Set (optional) - Do any files have a max size value? Max size could cause tempdb problems if it isn't allowed to grow.

			Other rules can be added at a future date.

	    .PARAMETER SqlInstance
            The SQL Server Instance to connect to. SQL Server 2005 and higher are supported.
        
		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Detailed
			If this switch is enabled, all test results will be displayed. By default, only those results which do not match best practices are displayed.

		.NOTES
			Original Author: Michael Fal (@Mike_Fal), http://mikefal.net
			Based off of Amit Bannerjee's (@banerjeeamit) Get-TempDB function (https://github.com/amitmsft/SqlOnAzureVM/blob/master/Get-TempdbFiles.ps1)

			dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
			Copyright (C) 2016 Chrissy LeMaire
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Test-DbaTempDbConfiguration

		.EXAMPLE
			Test-DbaTempDbConfiguration -SqlInstance localhost

			Checks tempdb on the localhost machine.

		.EXAMPLE
			Test-DbaTempDbConfiguration -SqlInstance localhost -Detailed

			Checks tempdb on the localhost machine. All rest results are shown.

	#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[Switch]$Detailed
	)

	begin {
		$result = @()
		
	}

	process {
		foreach ($servername in $SqlInstance) {
			Write-Verbose "Connecting to $servername."
			$server = Connect-SqlInstance $servername -SqlCredential $SqlCredential

			if ($server.versionMajor -lt 9) {
				Write-Warning "This function does not support versions lower than SQL Server 2005 (v9). Skipping server '$servername'."
				continue
			}

			#test for TF 1118
			if ($server.VersionMajor -ge 13) {
				$notes = 'SQL 2016 has this functionality enabled by default'
				# DBA May have changed setting. May need to check.
				$value = [PSCustomObject]@{
					ComputerName   = $server.NetName
					InstanceName   = $server.ServiceName
					SqlInstance    = $server.DomainInstanceName
					Rule           = 'TF 1118 Enabled'
					Recommended    = $true
					CurrentSetting = $true
				}
			}
			else {
				$sql = "dbcc traceon (3604);dbcc tracestatus (-1)"
				$tfcheck = $server.Databases['tempdb'].ExecuteWithResults($sql).Tables[0].TraceFlag
				$notes = 'KB328551 describes how TF 1118 can benefit performance.'

				if (($tfcheck -join ',').Contains('1118')) {

					$value = [PSCustomObject]@{
						ComputerName   = $server.NetName
						InstanceName   = $server.ServiceName
						SqlInstance    = $server.DomainInstanceName
						Rule           = 'TF 1118 Enabled'
						Recommended    = $true
						CurrentSetting = $true
					}
				}
				else {
					$value = [PSCustomObject]@{
						ComputerName   = $server.NetName
						InstanceName   = $server.ServiceName
						SqlInstance    = $server.DomainInstanceName
						Rule           = 'TF 1118 Enabled'
						Recommended    = $true
						CurrentSetting = $false
					}
				}
			}

			if ($value.Recommended -ne $value.CurrentSetting -and $null -ne $value.Recommended) {
				$isBestPractice = $false
			}
			else {
				$isBestPractice = $true
			}

			$value | Add-Member -Force -MemberType NoteProperty -Name IsBestpractice -Value $isBestPractice
			$value | Add-Member -Force -MemberType NoteProperty -Name Notes -Value $notes
			$result += $value
			Write-Verbose "TF 1118 evaluated"

			#get files and log files
			$datafiles = $server.Databases['tempdb'].ExecuteWithResults("SELECT physical_name as FileName, max_size as MaxSize, CASE WHEN is_percent_growth = 1 THEN 'Percent' ELSE 'KB' END as GrowthType from sys.database_files WHERE type_desc = 'ROWS'").Tables[0]
			$logfiles = $server.Databases['tempdb'].ExecuteWithResults("SELECT physical_name as FileName, max_size as MaxSize, CASE WHEN is_percent_growth = 1 THEN 'Percent' ELSE 'KB' END as GrowthType from sys.database_files WHERE type_desc = 'LOG'").Tables[0]

			Write-Verbose "TempDB file objects gathered"

			$cores = $server.Processors

			if ($cores -gt 8) {
				$cores = 8
			}

			$value = [PSCustomObject]@{
				ComputerName   = $server.NetName
				InstanceName   = $server.ServiceName
				SqlInstance    = $server.DomainInstanceName
				Rule           = 'File Count'
				Recommended    = $cores
				CurrentSetting = $datafiles.Rows.Count
			}

			if ($value.Recommended -ne $value.CurrentSetting -and $null -ne $value.Recommended) {
				$isBestPractice = $false
			}
			else {
				$isBestPractice = $true
			}

			$value | Add-Member -Force -MemberType NoteProperty -Name IsBestpractice -Value $isBestPractice
			$value | Add-Member -Force -MemberType NoteProperty -Name Notes -Value 'Microsoft recommends that the number of tempdb data files is equal to the number of logical cores up to 8.'
			$result += $value

			Write-Verbose "File counts evaluated."

			#test file growth
			$percdata = $datafiles | Where-Object { $_.GrowthType -ne 'KB' } | Measure-Object
			$perclog = $logfiles  | Where-Object { $_.GrowthType -ne 'KB' } | Measure-Object

			$totalcount = $percdata.count + $perclog.count
			if ($totalcount -gt 0) {
				$totalcount = $true
			}
			else {
				$totalcount = $false
			}

			$value = [PSCustomObject]@{
				ComputerName   = $server.NetName
				InstanceName   = $server.ServiceName
				SqlInstance    = $server.DomainInstanceName
				Rule           = 'File Growth in Percent'
				Recommended    = $false
				CurrentSetting = $totalcount
			}

			if ($value.Recommended -ne $value.CurrentSetting -and $null -ne $value.Recommended) {
				$isBestPractice = $false
			}
			else {
				$isBestPractice = $true
			}

			$value | Add-Member -Force -MemberType NoteProperty -Name IsBestpractice -Value $isBestPractice
			$value | Add-Member -Force -MemberType NoteProperty -Name Notes -Value 'Set grow with explicit values, not by percent.'
			$result += $value

			Write-Verbose "File growth settings evaluated."
			#test file Location

			$cdata = ($datafiles | Where-Object { $_.FileName -like 'C:*' } | Measure-Object).Count + ($logfiles | Where-Object { $_.FileName -like 'C:*' } | Measure-Object).Count
			if ($cdata -gt 0) {
				$cdata = $true
			}
			else {
				$cdata = $false
			}

			$value = [PSCustomObject]@{
				ComputerName   = $server.NetName
				InstanceName   = $server.ServiceName
				SqlInstance    = $server.DomainInstanceName
				Rule           = 'File Location'
				Recommended    = $false
				CurrentSetting = $cdata
			}

			if ($value.Recommended -ne $value.CurrentSetting -and $null -ne $value.Recommended) {
				$isBestPractice = $false
			}
			else {
				$isBestPractice = $true
			}

			$value | Add-Member -Force -MemberType NoteProperty -Name IsBestpractice -Value $isBestPractice
			$value | Add-Member -Force -MemberType NoteProperty -Name Notes -Value "Do not place your tempdb files on C:\."
			$result += $value

			Write-Verbose "File locations evaluated."

			#Test growth limits
			$growthlimits = ($datafiles | Where-Object { $_.MaxSize -gt 0 } | Measure-Object).Count + ($logfiles | Where-Object { $_.MaxSize -gt 0 } | Measure-Object).Count
			if ($growthlimits -gt 0) {
				$growthlimits = $true
			}
			else {
				$growthlimits = $false
			}

			$value = [PSCustomObject]@{
				ComputerName   = $server.NetName
				InstanceName   = $server.ServiceName
				SqlInstance    = $server.DomainInstanceName
				Rule           = 'File MaxSize Set'
				Recommended    = $false
				CurrentSetting = $growthlimits
			}

			if ($value.Recommended -ne $value.CurrentSetting -and $null -ne $value.Recommended) {
				$isBestPractice = $false
			}
			else {
				$isBestPractice = $true
			}

			$value | Add-Member -Force -MemberType NoteProperty -Name IsBestpractice -Value $isBestPractice
			$value | Add-Member -Force -MemberType NoteProperty -Name Notes -Value "Consider setting your tempdb files to unlimited growth."
			$result += $value

			Write-Verbose "MaxSize values evaluated."
		}
	}

	end {
		if ($Detailed) {
			return $result
		}
		else {
			$failed = $result | Where-Object { $_.isBestPractice -eq $false }
			if ($null -eq $failed) {
				Write-Output "All tests passed! tempdb is properly optimized."
			}
			else {
				return $failed
			}
		}
		
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Test-SqlTempDbConfiguration
	}
}
