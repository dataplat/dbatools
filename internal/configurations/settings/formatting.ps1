# The default formatting style for dates
Set-DbaConfig -FullName 'Formatting.Date' -Value "dd MMM yyyy" -Initialize -Validation string -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::FormatDate = $args[0] } -Description "The default formatting of Dates"

# The default formatting style for full datetime objects
Set-DbaConfig -FullName 'Formatting.DateTime' -Value "yyyy-MM-dd HH:mm:ss.fff" -Initialize -Validation string -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::FormatDateTime = $args[0] } -Description "The default formatting style for full datetime objects"

# The default formatting style for time objects
Set-DbaConfig -FullName 'Formatting.Time' -Value "HH:mm:ss" -Initialize -Validation string -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::FormatTime = $args[0] } -Description "The default formatting style for full datetime objects"

# Disable custom Datetime formats
Set-DbaConfig -FullName 'Formatting.Disable.CustomDateTime' -Value $false -Initialize -Validation bool -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::DisableCustomDateTime = $args[0] } -Description "Controls whether custom DateTime formats are used or whether to default back to DateTime standard."

# Disable custom TimeSpan formats
Set-DbaConfig -FullName 'Formatting.Disable.CustomTimeSpan' -Value $false -Initialize -Validation bool -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::DisableCustomTimeSpan = $args[0] } -Description "Controls whether custom TimeSpan formats are used or whether to default back to DateTime standard."

Set-DbaConfig -FullName 'Formatting.size.style' -Value ([Sqlcollaborative.Dbatools.Utility.SizeStyle]::Dynamic) -Initialize -Validation sizestyle -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::SizeStyle = $args[0] } -Description "Controls how size objects are displayed by default. Generally, their string representation is calculated to be user friendly (dynamic), can be updated to 'plain' number or a specific size. Can be overriden on a per-object basis."
Set-DbaConfig -FullName 'Formatting.size.digits' -Value 2 -Initialize -Validation integer0to9 -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::SizeDigits = $args[0] } -Description "How many digits are used when displaying a size object."