Function Out-DbaDataTable
{
<#
.SYNOPSIS 
Creates a DataTable for an object 
	
.DESCRIPTION 
Creates a DataTable based on an objects properties. This allows you to easily write to SQL Server tables
	
Thanks to Chad Miller, this script is all him. https://gallery.technet.microsoft.com/scriptcenter/4208a159-a52e-4b99-83d4-8048468d29dd

.PARAMETER InputObject
The object to transform into a DataTable
	
.NOTES
dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/Out-DbaDataTable

.EXAMPLE
Out-DbaDataTable -InputObject $dblist

Does whatever

.EXAMPLE
$dblist | Out-DbaDataTable

Does whatever
	
#>	
	[CmdletBinding()]
	param (
		[Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
		[PSObject[]]$InputObject
	)
	
	BEGIN
	{
		function Get-Type
		{
			param ($type)
			
			$types = @(
				'System.Boolean',
				'System.Byte[]',
				'System.Byte',
				'System.Char',
				'System.Datetime',
				'System.Decimal',
				'System.Double',
				'System.Guid',
				'System.Int16',
				'System.Int32',
				'System.Int64',
				'System.Single',
				'System.UInt16',
				'System.UInt32',
				'System.UInt64')
			
			if ($types -contains $type)
			{
				return $type
			}
			else
			{
				return 'System.String'
			}
		}
		
		$datatable = New-Object System.Data.DataTable
	}
	PROCESS
	{
		foreach ($object in $InputObject)
		{
			$datarow = $datatable.NewRow()
			foreach ($property in $object.PsObject.get_properties())
			{
				if (++$i -eq 1)
				{
					$column = New-Object Data.DataColumn
					$column.ColumnName = $property.Name.ToString()
					
					if ($property.value)
					{
						if ($property.value -isnot [System.DBNull])
						{
							$type = Get-Type $property.TypeNameOfValue
							$column.DataType = [System.Type]::GetType($type)
						}
					}
					
					$null = $datatable.Columns.Add($column)
				}
				
				if ($property.Gettype().IsArray)
				{
					$datarow.Item($property.Name) = $property.value | ConvertTo-XML -AS String -NoTypeInformation -Depth 1
				}
				else
				{
					$datarow.Item($property.Name) = $property.value
				}
			}
			
			$datatable.Rows.Add($datarow)
		}
	}
}