function Convert-HexStringToByte {
<#
	.SYNOPSIS
	Converts hex string into byte object
	
	.DESCRIPTION
	Converts hex string (e.g. '0x01641736') into the byte object ([byte[]]@(1,100,23,54))
	Used when working with SMO logins and their byte parameters: sids and hashed passwords
		
	.PARAMETER InputObject
	Input hex string (e.g. '0x1234' or 'DBA2FF')
	
	.NOTES
	Tags: Login, Internal
	Author: Kirill Kravtsov (@nvarscar)
	dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
	Copyright (C) 2016 Chrissy LeMaire
	
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
	
	This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
	
	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

	.EXAMPLE
	Convert-HexStringToByte '0x01641736'
	
	Returns byte[] object [byte[]]@(1,100,23,54)
	
	.EXAMPLE
	Convert-HexStringToByte '1234'
	
	Returns byte[] object [byte[]]@(18,52)
#>
	Param (
		[string]$InputObject
	)
	$hexString = $InputObject.TrimStart("0x")
	if ($hexString.Length % 2 -eq 1) { $hexString = '0' + $hexString }
	[byte[]]$outByte = $null; $outByte += 0 .. (($hexString.Length)/2-1) | ForEach-Object { [Int16]::Parse($hexString.Substring($_*2, 2), 'HexNumber') }
	Return $outByte
}