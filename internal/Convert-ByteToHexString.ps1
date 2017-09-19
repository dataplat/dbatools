function Convert-ByteToHexString {
<#
	.SYNOPSIS
	Converts byte object into hex string
	
	.DESCRIPTION
	Converts byte object ([byte[]]@(1,100,23,54)) into the hex string (e.g. '0x01641736')
	Used when working with SMO logins and their byte parameters: sids and hashed passwords
		
	.PARAMETER InputObject
	Input byte[] object (e.g. [byte[]]@(18,52))
	
	.NOTES
	Tags: Login, Internal
	Author: Kirill Kravtsov (@nvarscar)
	dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
	Copyright (C) 2016 Chrissy LeMaire
	
	This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
	
	This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
	
	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

	.EXAMPLE
	Convert-ByteToHexString ([byte[]]@(1,100,23,54))
	
	Returns hex string '0x01641736'
	
	.EXAMPLE
	Convert-ByteToHexString 18,52
	
	Returns hex string '0x1234'
#>
	Param ([byte[]]$InputObject)
	$outString = "0x"; $InputObject | ForEach-Object { $outString += ("{0:X}" -f $_).PadLeft(2, "0") }
	Return $outString
}