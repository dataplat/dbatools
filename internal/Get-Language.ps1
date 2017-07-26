function Get-Language {
	<#
		.SYNOPSIS
			Converts Microsoft's language ID to human readable format 

		.DESCRIPTION
			Converts Microsoft's language ID to human readable format

		.PARAMETER Id
			The language ID

		.EXAMPLE
			Get-Language 1033

			Returns a pscustomobject with id, alias and name
	#>
	[CmdletBinding()]
	param (
		[int]$id
	)
	process {
		
		$culture = [System.Globalization.CultureInfo]::GetCultureInfo($id)
		
		[pscustomobject]@{
			LCID	   = $culture.LCID
			Name		   = $culture.Name
			DisplayName		   = $culture.DisplayName
		}
	}
}