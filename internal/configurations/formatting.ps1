# The default formatting style for dates
Set-DbaConfig -Name 'Formatting.Date' -Value "dd MMM yyyy" -Default -DisableHandler -Description "The default formatting of Dates"

# The default formatting style for full datetime objects
Set-DbaConfig -Name 'Formatting.DateTime' -Value "yyyy-MM-dd HH:mm:ss.fff" -Default -DisableHandler -Description "The default formatting style for full datetime objects"

# The default formatting style for time objects
Set-DbaConfig -Name 'Formatting.Time' -Value "HH:mm:ss" -Default -DisableHandler -Description "The default formatting style for full datetime objects"

# Disable custom Datetime formats
Set-DbaConfig -Name 'Formatting.Disable.CustomDateTime' -Value $false -Default -DisableHandler -Description "Controls whether custom DateTime formats are used or whether to default back to DateTime standard."

# Disable custom TimeSpan formats
Set-DbaConfig -Name 'Formatting.Disable.CustomTimeSpan' -Value $false -Default -DisableHandler -Description "Controls whether custom TimeSpan formats are used or whether to default back to DateTime standard."