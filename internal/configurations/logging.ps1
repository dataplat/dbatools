<#
This is for all configuration values regarding the logging system

NOTES:
- All these configurations should have a handler, as the logging system relies entirely on static fields for performance reasons
- If you want to change the default values, change them both here AND in the C# library
#>

Set-DbaConfig -Name 'Logging.MaxErrorCount' -Value 128 -Default -DisableHandler -Description "The maximum number of error records maintained in-memory. This setting is on a per-Process basis. Runspaces share, jobs or other consoles counted separately."
Set-DbaConfig -Name 'Logging.MaxMessageCount' -Value 1024 -Default -DisableHandler -Description "The maximum number of messages that can be maintained in the in-memory message queue. This setting is on a per-Process basis. Runspaces share, jobs or other consoles counted separately."
Set-DbaConfig -Name 'Logging.MaxMessagefileBytes' -Value 5MB -Default -DisableHandler -Description "The maximum size of a given logfile. When reaching this limit, the file will be abandoned and a new log created. Set to 0 to not limit the size. This setting is on a per-Process basis. Runspaces share, jobs or other consoles counted separately."
Set-DbaConfig -Name 'Logging.MaxMessagefileCount' -Value 5 -Default -DisableHandler -Description "The maximum number of logfiles maintained at a time. Exceeding this number will cause the oldest to be culled. Set to 0 to disable the limit. This setting is on a per-Process basis. Runspaces share, jobs or other consoles counted separately."
Set-DbaConfig -Name 'Logging.MaxErrorFileBytes' -Value 20MB -Default -DisableHandler -Description "The maximum size all error files combined may have. When this number is exceeded, the oldest entry is culled. This setting is on a per-Process basis. Runspaces share, jobs or other consoles counted separately."
Set-DbaConfig -Name 'Logging.MaxTotalFolderSize' -Value 100MB -Default -DisableHandler -Description "This is the upper limit of length all items in the log folder may have combined across all processes."
Set-DbaConfig -Name 'Logging.MaxLogFileAge' -Value (New-TimeSpan -Days 7) -Default -DisableHandler -Description "Any logfile older than this will automatically be cleansed. This setting is global."
Set-DbaConfig -Name 'Logging.MessageLogFileEnabled' -Value $true -Default -DisableHandler -Description "Governs, whether a log file for the system messages is written. This setting is on a per-Process basis. Runspaces share, jobs or other consoles counted separately."
Set-DbaConfig -Name 'Logging.MessageLogEnabled' -Value $true -Default -DisableHandler -Description "Governs, whether a log of recent messages is kept in memory. This setting is on a per-Process basis. Runspaces share, jobs or other consoles counted separately."
Set-DbaConfig -Name 'Logging.ErrorLogFileEnabled' -Value $true -Default -DisableHandler -Description "Governs, whether log files for errors are written. This setting is on a per-Process basis. Runspaces share, jobs or other consoles counted separately."
Set-DbaConfig -Name 'Logging.ErrorLogEnabled' -Value $true -Default -DisableHandler -Description "Governs, whether a log of recent errors is kept in memory. This setting is on a per-Process basis. Runspaces share, jobs or other consoles counted separately."