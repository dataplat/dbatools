<#
This configuration file is for all settings of how dbatools interacts with users
#>

# Configure the message levels at which the function will write either an info, a verbose message or debug message
# Used by the internal "Write-Message" function
Set-DbaConfig -Name 'message.maximuminfo' -Value 3 -Default -DisableHandler -Description "The maximum message level to still display to the user directly."
Set-DbaConfig -Name 'message.maximumverbose' -Value 6 -Default -DisableHandler -Description "The maxium message level where verbose information is still written."
Set-DbaConfig -Name 'message.maximumdebug' -Value 9 -Default -DisableHandler -Description "The maximum message level where debug information is still written."
Set-DbaConfig -Name 'message.minimuminfo' -Value 1 -Default -DisableHandler -Description "The minimum required message level for messages that will be shown to the user."
Set-DbaConfig -Name 'message.minimumverbose' -Value 4 -Default -DisableHandler -Description "The minimum required message level where verbose information is written."
Set-DbaConfig -Name 'message.minimumdebug' -Value 1 -Default -DisableHandler -Description "The minimum required message level where debug information is written."

# Default color used by the PS3-4 "Write-Message" function in info mode
Set-DbaConfig -Name 'message.infocolor' -Value 'Cyan' -Default -Description "The color to use when writing text to the screen on PowerShell 3 or 4."