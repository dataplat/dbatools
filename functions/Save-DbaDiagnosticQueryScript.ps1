function Save-DbaDiagnosticQueryScript {
<#
.SYNOPSIS 
Save-DbaDiagnosticQueryScript downloads the most recent version of all Glenn Berry DMV scripts

.DESCRIPTION
The dbatools module will have the diagnostice queries pre-installed. Use this only to update to a more recent version or specific versions.

This function is mainly used by Invoke-DbaDiagnosticQuery, but can also be used independently to download the Glenn Berry DMV scripts.

Use this function to pre-download the scripts from a device with an Internet connection.
	
The function Invoke-DbaDiagnosticQuery will try to download these scripts automatically, but it obviously needs an internet connection to do that.

.PARAMETER Path
Specifies the path to the output
	
.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.NOTES
Author: André Kamman (@AndreKamman), http://clouddba.io

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.EXAMPLE   
Save-DbaDiagnosticQueryScript -Path c:\temp

Downloads the most recent version of all Glenn Berry DMV scripts to the specified location.
If Path is not specified, the "My Documents" location will be used

#>
	[CmdletBinding()]
	param (
		[System.IO.FileInfo]$Path = [Environment]::GetFolderPath("mydocuments"),
		[Switch]$Silent
	)
	
	if (-not (Test-Path $Path)) {
		Stop-Function -Message "Path does not exist or access denied" -Target $path
		return
	}
	
	Add-Type -AssemblyName System.Web
	
	Write-Message -Level Output -Message "Downloading SQL Server Diagnostic Query scripts"
	
	$glenberryrss = "http://www.sqlskills.com/blogs/glenn/feed/"
	$glenberrysql = @()
	
	Write-Message -Level Output -Message "Downloading $glenberryrss"
	
	try {
		$rss = Invoke-WebRequest -uri $glenberryrss -UseBasicParsing -ErrorAction Stop
	}
	catch {
		Stop-Function -Message "Invoke-WebRequest failed: $_" -Target $rss -InnerErrorRecord $_
		return
	}
	
	foreach ($link in $rss.Links.outerHTML) {
		if ($link -Match "https:\/\/dl.dropboxusercontent*(.+)\/SQL(.+)\.sql") {
			$URL = $matches[0]
			
			if ([System.Web.HttpUtility]::UrlDecode($URL) -Match "SQL Server (.+) Diagnostic") {
				$SQLVersion = $matches[1].Replace(" ", "")
			}
			
			if ([System.Web.HttpUtility]::UrlDecode($URL) -Match "\((.+) (.+)\)") {
				$FileYear = "{0}" -f $matches[2]
				[int]$MonthNr = [CultureInfo]::InvariantCulture.DateTimeFormat.MonthNames.IndexOf($matches[1]) + 1
				$FileMonth = "{0:00}" -f $MonthNr
			}
			
			$glenberrysql += [pscustomobject]@{
				URL = $URL
				SQLVersion = $SQLVersion
				FileYear = $FileYear
				FileMonth = $FileMonth
				FileVersion = 0
			}
		}
	}
	
	foreach ($group in $glenberrysql | Group-Object FileYear) {
		$maxmonth = "{0:00}" -f ($group.Group.FileMonth | Measure-Object -Maximum).Maximum
		foreach ($item in $glenberrysql | Where-Object FileYear -eq $group.Name) {
			if ($item.FileMonth -eq "00") {
				$item.FileMonth = $maxmonth
			}
		}
	}
	
	foreach ($item in $glenberrysql) {
		$item.FileVersion = "$($item.FileYear)$($item.FileMonth)"
	}
	
	foreach ($item in $glenberrysql | Sort-Object FileVersion -Descending | Where-Object FileVersion -eq ($glenberrysql.FileVersion | Measure-Object -Maximum).Maximum) {
		$filename = "{0}\SQLServerDiagnosticQueries_{1}_{2}.sql" -f $Path, $item.SQLVersion, $item.FileVersion
		Write-Message -Level Output -Message "Downloading $($item.URL) to $filename"
		
		try {
			Invoke-WebRequest -Uri $item.URL -OutFile $filename -ErrorAction Stop
		}
		catch {
			Stop-Function -Message "Invoke-WebRequest failed: $_" -Target $filename -InnerErrorRecord $_
			return
		}
	}
}
