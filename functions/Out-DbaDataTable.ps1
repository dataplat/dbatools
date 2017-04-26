Function Out-DbaDataTable
{
<#
.SYNOPSIS 
Creates a DataTable for an object 
	
.DESCRIPTION 
Creates a DataTable based on an objects properties. This allows you to easily write to SQL Server tables.
	
Thanks to Chad Miller, this is based on his script. https://gallery.technet.microsoft.com/scriptcenter/4208a159-a52e-4b99-83d4-8048468d29dd

.PARAMETER InputObject
The object to transform into a DataTable
	
.PARAMETER IgnoreNull 
Use this switch to ignore null rows

.PARAMETER TimeSpanType
Sets what type to convert TimeSpan into before creating the datatable. Options are Ticks, TotalDays, TotalHours, TotalMinutes, TotalSeconds, TotalMilliseconds and String.

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
 https://dbatools.io/Out-DbaDataTable

.EXAMPLE
Get-Service | Out-DbaDataTable

Creates a $datatable based off of the output of Get-Service 
	
.EXAMPLE
Out-DbaDataTable -InputObject $csv.cheesetypes

Creates a DataTable from the CSV object, $csv.cheesetypes
	
.EXAMPLE
$dblist | Out-DbaDataTable

Similar to above but $dbalist gets piped in

.EXAMPLE
Get-Process | Out-DbaDataTable -TimeSpanType TotalSeconds

Creates a DataTable with the running processes and converts any TimeSpan property to TotalSeconds.

#>	
	[CmdletBinding()]
	param (
		[Parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $true)]
		[AllowNull()]
		[PSObject[]]$InputObject,
		[switch]$IgnoreNull,
        [ValidateSet("Ticks", "TotalDays", "TotalHours", "TotalMinutes", "TotalSeconds", "TotalMilliseconds", "String")]
        [string]$TimeSpanType = "TotalMilliseconds",		
        [switch]$Silent
        
	)
	
	BEGIN
	{
        # This function will check so that the type is an accepted type which could be used when inserting into a table
        # If a type is accepted (included in the $type array) then it will be passed on, otherwise it will first change type before passing it on
        # Special types will have both their types converted as well as the value
        # TimeSpan is a special type and will be converted into the $timespantype (default: TotalMilliseconds) 
        # so that the timespan can be store in a database further down the line
		function ConvertType
		{
			param (
                $type,
                $value,
                $timespantype = 'TotalMilliseconds'
            )
			
			$types = @(
                'Int32',
                'UInt32',
                'Int16',
                'UInt16',
                'Int64',
                'UInt64',
                'Decimal',
                'Single',
                'Double',
                'Byte',
                'SByte',
                'Boolean',
                'Bool',
                'String',
                'DateTime',
                'Guid',
                'Char',
                'int',
                'long',
                'System.Int32',
                'System.UInt32',
                'System.Int16',
                'System.UInt16',
                'System.Int64',
                'System.UInt64',
                'System.Decimal',
                'System.Single',
                'System.Double',
                'System.Byte',
                'System.SByte',
                'System.Boolean',
                'System.String',
                'System.DateTime',
                'System.Guid',
                'System.Char'
            )

            # the $special variable is used to mark the return value if a conversion was made on the value itself
            # If this is set to true the original value will later be ignored when updating the DataTable 
            # and the value returned from this function will be used instead (cannot modify existing properties)
            $special = $false

            # Special types need to be converted in some way.
            # This attempt is to convert timespan into something that works in a table
            # I couldn't decide on what to convert it to so the user can decide
            # If the parameter is not used, TotalMilliseconds will be used as default
            # Ticks are more accurate but I think milliseconds are more useful most of the time
            if ($type -in 'System.TimeSpan', 'TimeSpan') 
            {
                $special = $true
                # Debug, remove when done
                Write-Verbose "Found match: $type (special)"
                if ($timespantype -eq 'String') 
                {
                    # Debug, remove when done
                    Write-Verbose "Converting TimeSpan to string"
                    $value = $value.ToString()
                    $type = 'System.String'
                }
                else 
                {
                    # Debug, remove when done
                    Write-Verbose "Converting TimeSpan to $timespantype (Int64)"
                    # Lets use Int64 for all other types than string.
                    # We could match the type more closely with the timespantype but that can be added in the future if needed
                    $value = $value.$timespantype
                    $type = 'System.Int64'
                }
            }
            elseif ($types -notcontains $type) 
            {
                # Debug, remove when done
                Write-Verbose "Did not find match: $type"
                # All types which are not found in the array will be converted into strings
                # In this way we dont ignore it completely and it will be clear in the end why it looks as it does
                $type = 'System.String'
            }
            
            # return a hashtable instead of an object. I like hashtables :)
            return @{ type=$type; Value=$value; Special=$special}
		}
	
		$datatable = New-Object System.Data.DataTable
	}
	
	PROCESS
	{
		if (!$InputObject)
		{
			if ($IgnoreNull)
			{
				Stop-Function -Message "The InputObject from the pipe is null. Skipping." -Continue
			}
			else
			{
				$datarow = $datatable.NewRow()
				$datatable.Rows.Add($datarow)
				continue
			}
		}
		foreach ($object in $InputObject)
		{
			$datarow = $datatable.NewRow()
			foreach ($property in $object.PsObject.get_properties())
			{
                # the converted variable will get the result from the ConvertType function and used for type and value conversion when adding to the datatable
                $converted = @{}

				if ($datatable.Rows.Count -eq 0)
				{
					$column = New-Object System.Data.DataColumn
					$column.ColumnName = $property.Name.ToString()
					
                    # There was an if statement here before which checked if the $property.value had a value which has been removed
                    # Even if property value is $false or $null we need to check the type
					if ($property.value -isnot [System.DBNull])
					{
                        # Check if property is a ScriptProperty, then resolve it while calling ConvertType (otherwise we dont get the proper type)
                        If ($property.MemberType -eq 'ScriptProperty') {
                            $converted = ConvertType -type ($object.($property.Name).GetType().ToString()) -value $property.value -timespantype $TimeSpanType
                        } else {
                            $converted = ConvertType -type $property.TypeNameOfValue -value $property.value -timespantype $TimeSpanType
                        }
						$column.DataType = [System.Type]::GetType($converted.type)
					}
					$datatable.Columns.Add($column)
				}

				if ($property.value.length -gt 0)
				{
					if ($property.value.ToString() -eq 'System.Object[]')
					{
						$datarow.Item($property.Name) = $property.value -join ", "
					}
					else
					{
                        # If the typename was a special typename we want to use the value returned from ConvertType instead
                        # We might get error if we try to change the value for $property.value if it is read-only.
                        if ($converted.special) 
                        {
						    $datarow.Item($property.Name) = $converted.value
                        }
                        else
                        {
                            $datarow.Item($property.Name) = $property.value
                        }
					}
				}
			}
			$datatable.Rows.Add($datarow)
		}
	}
	
	End
	{
		return @( ,($datatable))
	}
	
}
