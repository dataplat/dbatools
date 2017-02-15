<#
This configuration file is for all settings of how dbatools interacts with users
#>

# Configure the message levels at which the function will write either an info, a verbose message or debug message
# Used by the internal 'Write-Message' function
Set-DbaConfig -Name 'message.maximum.info' -Value 3 -Default
Set-DbaConfig -Name 'message.maximum.verbose' -Value 6 -Default
Set-DbaConfig -Name 'message.maximum.warning' -Value 9 -Default
Set-DbaConfig -Name 'message.minimum.info' -Value 1 -Default
Set-DbaConfig -Name 'message.minimum.verbose' -Value 4 -Default
Set-DbaConfig -Name 'message.minimum.warning' -Value 1 -Default