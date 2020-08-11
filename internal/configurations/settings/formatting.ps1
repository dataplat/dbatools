# The default formatting style for dates
Set-DbatoolsConfig -FullName 'Formatting.Date' -Value "dd MMM yyyy" -Initialize -Validation string -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::FormatDate = $args[0] } -Description "The default formatting of Dates"

# The default formatting style for full datetime objects
Set-DbatoolsConfig -FullName 'Formatting.DateTime' -Value "yyyy-MM-dd HH:mm:ss.fff" -Initialize -Validation string -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::FormatDateTime = $args[0] } -Description "The default formatting style for full datetime objects"

# The default formatting style for time objects
Set-DbatoolsConfig -FullName 'Formatting.Time' -Value "HH:mm:ss" -Initialize -Validation string -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::FormatTime = $args[0] } -Description "The default formatting style for full datetime objects"

# Disable custom Datetime formats
Set-DbatoolsConfig -FullName 'Formatting.Disable.CustomDateTime' -Value $false -Initialize -Validation bool -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::DisableCustomDateTime = $args[0] } -Description "Controls whether custom DateTime formats are used or whether to default back to DateTime standard."

# Disable custom TimeSpan formats
Set-DbatoolsConfig -FullName 'Formatting.Disable.CustomTimeSpan' -Value $false -Initialize -Validation bool -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::DisableCustomTimeSpan = $args[0] } -Description "Controls whether custom TimeSpan formats are used or whether to default back to DateTime standard."

Set-DbatoolsConfig -FullName 'Formatting.size.style' -Value ([Sqlcollaborative.Dbatools.Utility.SizeStyle]::Dynamic) -Initialize -Validation sizestyle -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::SizeStyle = $args[0] } -Description "Controls how size objects are displayed by default. Generally, their string representation is calculated to be user friendly (dynamic), can be updated to 'plain' number or a specific size. Can be overriden on a per-object basis."
Set-DbatoolsConfig -FullName 'Formatting.size.digits' -Value 2 -Initialize -Validation integer0to9 -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::SizeDigits = $args[0] } -Description "How many digits are used when displaying a size object."

# The default batch separator to use when exporting scripts
Set-DbatoolsConfig -FullName 'Formatting.BatchSeparator' -Value "GO" -Initialize -Validation string -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::FormatDate = $args[0] } -Description "The default batch separator used in export of scripts"

# The default uformat style for formatting dates in scripts
Set-DbatoolsConfig -FullName 'Formatting.UFormat' -Value "%Y%m%d%H%M%S" -Initialize -Validation string -Handler { [Sqlcollaborative.Dbatools.Utility.UtilityHost]::FormatDate = $args[0] } -Description "The default batch separator used in export of scripts"