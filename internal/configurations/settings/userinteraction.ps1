<#
This configuration file is for all settings of how dbatools interacts with users
#>

# Configure the message levels at which the function will write either an info, a verbose message or debug message
# Used by the internal "Write-Message" function
Set-DbaConfig -Name 'message.maximuminfo' -Value 3 -Initialize -Validation integer0to9 -Handler { [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::MaximumInformation = $args[0] } -Description "The maximum message level to still display to the user directly."
Set-DbaConfig -Name 'message.maximumverbose' -Value 6 -Initialize -Validation integer0to9 -Handler { [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::MaximumVerbose = $args[0] } -Description "The maxium message level where verbose information is still written."
Set-DbaConfig -Name 'message.maximumdebug' -Value 9 -Initialize -Validation integer0to9 -Handler { [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::MaximumDebug = $args[0] } -Description "The maximum message level where debug information is still written."
Set-DbaConfig -Name 'message.minimuminfo' -Value 1 -Initialize -Validation integer0to9 -Handler { [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::MinimumInformation = $args[0] } -Description "The minimum required message level for messages that will be shown to the user."
Set-DbaConfig -Name 'message.minimumverbose' -Value 4 -Initialize -Validation integer0to9 -Handler { [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::MinimumVerbose = $args[0] } -Description "The minimum required message level where verbose information is written."
Set-DbaConfig -Name 'message.minimumdebug' -Value 1 -Initialize -Validation integer0to9 -Handler { [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::MinimumDebug = $args[0] } -Description "The minimum required message level where debug information is written."

# Default color used by the "Write-Message" function in info mode
Set-DbaConfig -Name 'message.infocolor' -Value 'Cyan' -Initialize -Validation consolecolor -Handler { [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::InfoColor = $args[0] } -Description "The color to use when writing text to the screen on PowerShell."
Set-DbaConfig -Name 'message.developercolor' -Value 'Grey' -Initialize -Validation consolecolor -Handler { [Sqlcollaborative.Dbatools.dbaSystem.MessageHost]::DeveloperColor = $args[0] } -Description "The color to use when writing text with developer specific additional information to the screen on PowerShell."

# Messaging mode in non-critical terminations
Set-DbaConfig -Name 'message.mode.default' -Value ([DbaMode]::Strict) -Initialize -Validation string -Handler { } -Description "The mode controls how some functions handle non-critical terminations by default. Strict: Write a warning | Lazy: Write a message | Report: Generate a report object"
Set-DbaConfig -Name 'message.mode.lazymessagelevel' -Value 4 -Initialize -Validation integer0to9 -Handler { } -Description "At what level will the lazy message be written? (By default invisible to the user)"

# Enable Developer mode
Set-DbaConfig -Name 'developer.mode.enable' -Value $false -Initialize -Validation bool -Handler { [Sqlcollaborative.Dbatools.dbaSystem.DebugHost]::DeveloperMode = $args[0] } -Description "Developermode enables advanced logging and verbosity features. There is little benefit for enabling this as a regular user. but developers can use it to more easily troubleshoot issues."