<#
Registers the cmdlets published by this module.
Necessary for full hybrid module support.
#>
$commonParam = @{
    HelpFile = "$($PSModuleRoot)\en-us\dbatools.dll-Help.xml"
    Module   = $ExecutionContext.SessionState.Module
}

Import-DbaCmdlet @commonParam -Name Write-Message -Type ([Dataplat.Dbatools.Commands.WriteMessageCommand])
Import-DbaCmdlet @commonParam -Name Select-DbaObject -Type ([Dataplat.Dbatools.Commands.SelectDbaObjectCommand])
Import-DbaCmdlet @commonParam -Name Set-DbatoolsConfig -Type ([Dataplat.Dbatools.Commands.SetDbatoolsConfigCommand])