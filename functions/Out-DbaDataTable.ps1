#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

Function Out-DbaDataTable {
	<#
	.SYNOPSIS
		Creates a DataTable for an object
	
	.DESCRIPTION
		Creates a DataTable based on an objects properties. This allows you to easily write to SQL Server tables.
		
		Thanks to Chad Miller, this is based on his script. https://gallery.technet.microsoft.com/scriptcenter/4208a159-a52e-4b99-83d4-8048468d29dd
	
		If the attempt to convert to datatable fails, try the -Raw parameter for less accurate datatype detection.
	
	.PARAMETER InputObject
		The object to transform into a DataTable
	
	.PARAMETER TimeSpanType
		Sets what type to convert TimeSpan into before creating the datatable.
		Default: TotalMilliseconds
		Options: Ticks, TotalDays, TotalHours, TotalMinutes, TotalSeconds, TotalMilliseconds and String.
	
	.PARAMETER SizeType
		Sets what type to convert DbaSize to.
		Default: Int64
		Options: Int32, Int64, String
	
	.PARAMETER IgnoreNull
		If this switch is used, objects with null values will be ignored (empty rows will be added by default)
	
	.PARAMETER Raw
		Creates a datatable with all strings - no attempt to parse out datatypes is made
	
	.PARAMETER EnableException
		By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
		This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
		Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
		
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
	
	.OUTPUTS
		System.Object[]
	
	.NOTES
		dbatools PowerShell module (https://dbatools.io)
		Copyright (C) 2016 Chrissy LeMaire
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
	
	.LINK
		https://dbatools.io/Out-DbaDataTable
#>	
	[CmdletBinding()]
	[OutputType([System.Object[]])]
	param (
		[Parameter(Position = 0,
			Mandatory = $true,
			ValueFromPipeline = $true)]
		[AllowNull()]
		[PSObject[]]$InputObject,
		[Parameter(Position = 1)]
		[ValidateSet("Ticks",
			"TotalDays",
			"TotalHours",
			"TotalMinutes",
			"TotalSeconds",
			"TotalMilliseconds",
			"String")]
		[ValidateNotNullOrEmpty()]
		[string]$TimeSpanType = "TotalMilliseconds",
		[ValidateSet("Int64", "Int32", "String")]
		[string]$SizeType = "Int64",
		[switch]$IgnoreNull,
		[switch]$Raw,
		[switch][Alias('Silent')]$EnableException
	)
	
	Begin {
		Write-Message -Level InternalComment -Message "Starting"
		Write-Message -Level Debug -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
		Write-Message -Level Debug -Message "TimeSpanType = $TimeSpanType | SizeType = $SizeType"
		
		function ConvertType {
			# This function will check so that the type is an accepted type which could be used when inserting into a table.
			# If a type is accepted (included in the $type array) then it will be passed on, otherwise it will first change type before passing it on.
			# Special types will have both their types converted as well as the value.
			# TimeSpan is a special type and will be converted into the $timespantype. (default: TotalMilliseconds) 
			# so that the timespan can be store in a database further down the line.
			param (
				$type,
				
				$value,
				
				$timespantype = 'TotalMilliseconds',
				
				$sizetype = 'Int64'
			)
			
			$types = [System.Collections.ArrayList]@(
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
				'System.DateTime',
				'System.Guid',
				'System.Char'
			)
			
			# The $special variable is used to mark the return value if a conversion was made on the value itself.
			# If this is set to true the original value will later be ignored when updating the DataTable.
			# And the value returned from this function will be used instead. (cannot modify existing properties)
			$special = $false
			
			# Special types need to be converted in some way.
			# This attempt is to convert timespan into something that works in a table.
			# I couldn't decide on what to convert it to so the user can decide.
			# If the parameter is not used, TotalMilliseconds will be used as default.
			# Ticks are more accurate but I think milliseconds are more useful most of the time.
			if (($type -eq 'System.TimeSpan') -or ($type -eq 'Sqlcollaborative.Dbatools.Utility.DbaTimeSpan') -or ($type -eq 'Sqlcollaborative.Dbatools.Utility.DbaTimeSpanPretty')) {
				$special = $true
				if ($timespantype -eq 'String') {
					$value = $value.ToString()
					$type = 'System.String'
				}
				else {
					# Lets use Int64 for all other types than string.
					# We could match the type more closely with the timespantype but that can be added in the future if needed.
					$value = $value.$timespantype
					$type = 'System.Int64'
				}
			}
			elseif ($type -eq 'Sqlcollaborative.Dbatools.Utility.Size') {
				$special = $true
				switch ($sizetype) {
					'Int64' {
						$value = $value.Byte
						$type = 'System.Int64'
					}
					'Int32' {
						$value = $value.Byte
						$type = 'System.Int32'
					}
					'String' {
						$value = $value.ToString()
						$type = 'System.String'
					}
				}
			}
			elseif (!$types.Contains($type)) {
				# All types which are not found in the array will be converted into strings.
				# In this way we dont ignore it completely and it will be clear in the end why it looks as it does.
				$type = 'System.String'
			}
			
			# return a hashtable instead of an object. I like hashtables :)
			return @{ type = $type; Value = $value; Special = $special }
		}
		
		$datatable = New-Object System.Data.DataTable
		$specialColumns = @{ } # will store names of properties with special data types
		
		# The shouldCreateColumns variable will be set to false as soon as the column definition has been added to the data table.
		# This is to avoid that the rare scenario when columns are not created because the first object is null, which can be accepted.
		# This means that we cannot rely on the first object to create columns, hence this variable.
		$ShouldCreateCollumns = $true
	}
	
	Process {
		if (!$InputObject) {
			if ($IgnoreNull) {
				# If the object coming down the pipeline is null and the IgnoreNull parameter is set, ignore it.
				Write-Message -Level Warning -Message "The InputObject from the pipe is null. Skipping."
			}
			else {
				# If the object coming down the pipeline is null, add an empty row and then skip to next.
				$datarow = $datatable.NewRow()
				$datatable.Rows.Add($datarow)
			}
		}
		else {
			foreach ($object in $InputObject) {
				if (!$object) {
					if ($IgnoreNull) {
						# If the object in the array is null and the IgnoreNull parameter is set, ignore it.
						Write-Message -Level Warning -Message "Object in array is null. Skipping." -EnableException $EnableException
					}
					else {
						# If the object in the array is null, add an empty row and then skip to next.
						$datarow = $datatable.NewRow()
						$datatable.Rows.Add($datarow)
					}
				}
				else {
					$datarow = $datatable.NewRow()
					foreach ($property in $object.PsObject.get_properties()) {
						# The converted variable will get the result from the ConvertType function and used for type and value conversion when adding to the datatable.
						$converted = @{ }
						if ($ShouldCreateCollumns) {
							# this is where the table columns are generated
							if ($property.value -isnot [System.DBNull]) {
								# Check if property is a ScriptProperty, then resolve it while calling ConvertType. (otherwise we dont get the proper type)
								Write-Verbose "Attempting to get type from property $($property.Name)"
								If ($property.MemberType -eq 'ScriptProperty') {
									try {
										$converted = ConvertType -type ($object.($property.Name).GetType().ToString()) -value $property.value -timespantype $TimeSpanType -sizetype $SizeType
									}
									catch {
										# Ends up here when the type is not possible to get so the call to ConvertType fails.
										# In that case we make a string out of it. (in this scenario its often that a script property points to a null value so we can't get the type)
										$converted = @{
											type    = 'System.String'
											Value   = $property.value
											Special = $false
										}
									}
									# We need to check if the type returned by ConvertType is a special type.
									# In that case we add it to the $specialColumns variable for future reference.
									if ($converted.special) {
										$specialColumns.Add($property.Name, $object.($property.Name).GetType().ToString())
									}
								}
								else {
									$converted = ConvertType -type $property.TypeNameOfValue -value $property.value -timespantype $TimeSpanType -sizetype $SizeType
									# We need to check if the type returned by ConvertType is a special type.
									# In that case we add it to the $specialColumns variable for future reference.
									if ($converted.special) {
										$specialColumns.Add($property.Name, $property.TypeNameOfValue)
									}
								}
							}
							$column = New-Object System.Data.DataColumn
							$column.ColumnName = $property.Name.ToString()
							if (-not $Raw) {
								$column.DataType = [System.Type]::GetType($converted.type)
							}
							$datatable.Columns.Add($column)
						}
						else {
							# This is where we end up if the columns has been created in the data table.
							# We still need to check for special columns again, to make sure that the value is converted properly.
							if ($property.value -isnot [System.DBNull]) {
								if ($specialColumns.Keys -contains $property.Name) {
									$converted = ConvertType -type $specialColumns.($property.Name) -value $property.Value -timespantype $TimeSpanType -sizetype $SizeType
								}
							}
						}
						
						try {
							$propValueLength = $property.value.length
						}
						catch {
							$propValueLength = 0
						}
						if ($propValueLength -gt 0) {
							if ($property.value.ToString() -eq 'System.Object[]' -or $property.value.ToString() -eq 'System.String[]') {
								$datarow.Item($property.Name) = $property.value -join ", "
							}
							else {
								# If the typename was a special typename we want to use the value returned from ConvertType instead.
								# We might get error if we try to change the value for $property.value if it is read-only. That's why we use $converted.value instead.
								if ($converted.special) {
									$datarow.Item($property.Name) = $converted.value
								}
								else {
									$datarow.Item($property.Name) = $property.value
								}
							}
						}
					}
					
					$datatable.Rows.Add($datarow)
					# If this is the first non-null object then the columns has just been created.
					# Set variable to false to skip creating columns from now on.
					if ($ShouldCreateCollumns) {
						$ShouldCreateCollumns = $false
					}
				}
			}
		}
	}
	
	End {
		Write-Message -Level InternalComment -Message "Finished"
		return @( , ($datatable))
	}
}