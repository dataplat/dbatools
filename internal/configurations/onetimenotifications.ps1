<#
This configuration script is for all notifications that shown once only.
Basically, if you want to show a message only once per session, make that dependent on a configuration flag.

Example:
Set-DbaConfig -Name 'MessageShown.DeprecatedAlias.FooBar' -Value $false -Default -Hidden

In your function, only display the message, if the value of this setting is $false.
If you display the message, set it to $true
#>
