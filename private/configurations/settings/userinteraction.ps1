<#
This configuration file is for all settings of how dbatools interacts with users
#>

# Configure the message levels at which the function will write either an info, a verbose message or debug message
# Used by the internal "Write-Message" function
Set-DbatoolsConfig -Name 'message.maximuminfo' -Value 3 -Initialize -Validation integer0to9 -Handler { [Dataplat.Dbatools.Message.MessageHost]::MaximumInformation = $args[0] } -Description "The maximum message level to still display to the user directly."
Set-DbatoolsConfig -Name 'message.maximumverbose' -Value 6 -Initialize -Validation integer0to9 -Handler { [Dataplat.Dbatools.Message.MessageHost]::MaximumVerbose = $args[0] } -Description "The maxium message level where verbose information is still written."
Set-DbatoolsConfig -Name 'message.maximumdebug' -Value 9 -Initialize -Validation integer0to9 -Handler { [Dataplat.Dbatools.Message.MessageHost]::MaximumDebug = $args[0] } -Description "The maximum message level where debug information is still written."
Set-DbatoolsConfig -Name 'message.minimuminfo' -Value 1 -Initialize -Validation integer0to9 -Handler { [Dataplat.Dbatools.Message.MessageHost]::MinimumInformation = $args[0] } -Description "The minimum required message level for messages that will be shown to the user."
Set-DbatoolsConfig -Name 'message.minimumverbose' -Value 4 -Initialize -Validation integer0to9 -Handler { [Dataplat.Dbatools.Message.MessageHost]::MinimumVerbose = $args[0] } -Description "The minimum required message level where verbose information is written."
Set-DbatoolsConfig -Name 'message.minimumdebug' -Value 1 -Initialize -Validation integer0to9 -Handler { [Dataplat.Dbatools.Message.MessageHost]::MinimumDebug = $args[0] } -Description "The minimum required message level where debug information is written."

Set-DbatoolsConfig -Name 'message.consoleoutput.disable' -Value $false -Initialize -Validation "bool" -Handler { [Dataplat.Dbatools.Message.MessageHost]::DisableVerbosity = $args[0] } -Description "Global toggle that allows disabling all regular messages to screen. Messages from '-Verbose' and '-Debug' are unaffected"
Set-DbatoolsConfig -Name 'message.transform.errorqueuesize' -Value 512 -Initialize -Validation "integerpositive" -Handler { [Dataplat.Dbatools.Message.MessageHost]::TransformErrorQueueSize = $args[0] } -Description "The size of the queue for transformation errors. May be useful for advanced development, but can be ignored usually."
Set-DbatoolsConfig -Name 'message.nestedlevel.decrement' -Value 0 -Initialize -Validation "integer0to9" -Handler { [Dataplat.Dbatools.Message.MessageHost]::NestedLevelDecrement = $args[0] } -Description "How many levels should be reduced per callstack depth. This makes commands less verbose, the more nested they are called"

# Message display style options
Set-DbatoolsConfig -Name 'message.style.breadcrumbs' -Value $false -Initialize -Validation "bool" -Handler { [Dataplat.Dbatools.Message.MessageHost]::EnableMessageBreadcrumbs = $args[0] } -Description "Controls how messages are displayed. Enables Breadcrumb display, showing the entire callstack. Takes precedence over command name display."
Set-DbatoolsConfig -Name 'message.style.functionname' -Value $true -Initialize -Validation "bool" -Handler { [Dataplat.Dbatools.Message.MessageHost]::EnableMessageDisplayCommand = $args[0] } -Description "Controls how messages are displayed. Enables command name, showing the name of the writing command. Is overwritten by enabling breadcrumbs."
Set-DbatoolsConfig -Name 'message.style.timestamp' -Value $true -Initialize -Validation "bool" -Handler { [Dataplat.Dbatools.Message.MessageHost]::EnableMessageTimestamp = $args[0] } -Description "Controls how messages are displayed. Enables timestamp display, including a timestamp in each message."