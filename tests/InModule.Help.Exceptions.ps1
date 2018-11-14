$global:FunctionHelpTestExceptions = @(
    "TabExpansion2"
)

$global:HelpTestEnumeratedArrays = @(
    "Sqlcollaborative.Dbatools.Connection.ManagementConnectionType[]"
    "Sqlcollaborative.Dbatools.Message.MessageLevel[]"
)

$global:HelpTestSkipParameterType = @{
    "Get-DbaCmObject"      = @("DoNotUse")
    "Test-DbaCmConnection" = @("Type")
    "Get-DbaService"       = @("DoNotUse")
}