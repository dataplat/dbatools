function Get-DbaCollations {
	<#
		.SYNOPSIS
			Function to get available collations for a given SQL Server

		.DESCRIPTION
			The Get-DbaCollations function returns the list of collations available on each SQL Server.
			Only the connect permission is required to get this information.

		.PARAMETER SqlInstance
			The SQL Server instance, or instances. Only connect permission is required.

		.PARAMETER SqlCredential
			SqlCredential object to connect as. If not specified, current Windows login will be used.

		.PARAMETER Detailed
			Lookup Locale and Culture names (slightly slower)

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Author: Bryan Hamby (@galador)

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaCollations

		.EXAMPLE
			Get-DbaCollations -SqlInstance sql2016

			Gets all the collations from server sql2016 using NT authentication 

	#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[switch]$Detailed,
		[switch]$Silent
	)
	
	process {
		function Get-CodePageDescription ($CodePage) {
			$encoding = [System.Text.Encoding]::GetEncoding($CodePage)
			Select-Object -InputObject $encoding -ExpandProperty EncodingName
		}

		function Get-LocaleDescription ($LocaleId) {
			if ($LocaleId -eq 66577) {
				#No longer supported by Windows, but still shows up in SQL Server
				#http://www.databaseteam.org/1-ms-sql-server/982faddda7a789a1.htm
				return "Japanese_Unicode"
			}

			$culture = [System.Globalization.CultureInfo]::GetCultureInfo($LocaleId)
			Select-Object -InputObject $culture -ExpandProperty DisplayName
		}

		foreach ($Instance in $sqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

			$availableCollations = @()
			$server.EnumCollations().Rows | ForEach-Object {
				$collation = [PSCustomObject]@{
					Instance         = $Instance
					Name             = $_.Name            
					CodePage         = $_.CodePage        
					CodePageName     = ""
					LocaleID         = $_.LocaleID     
					LocaleName       = ""
					ComparisonStyle  = $_.ComparisonStyle 
					Description      = $_.Description     
					CollationVersion = $_.CollationVersion
				}

				if ($Detailed) {
					$collation.CodePageName = (Get-CodePageDescription $collation.CodePage)
					$collation.LocaleName = (Get-LocaleDescription $collation.LocaleID)
				}

				$availableCollations += $collation
			}

			if ($Detailed) {
				Select-DefaultView -InputObject $availableCollations -Property Instance, Name, CodePage, CodePageName, LocaleID, LocaleName, Description
			}
			else {
				Select-DefaultView -InputObject $availableCollations -Property Instance, Name, CodePage, LocaleID, Description
			}
		} #foreach instance
	} #process
} #function
