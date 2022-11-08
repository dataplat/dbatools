$global:FunctionHelpTestExceptions = @(
    "TabExpansion2"
)

$global:HelpTestEnumeratedArrays = @(
    "Dataplat.Dbatools.Connection.ManagementConnectionType[]"
    "Dataplat.Dbatools.Message.MessageLevel[]"
    "Dataplat.Dbatools.Discovery.DbaInstanceScanType[]"
)

$global:HelpTestSkipParameterType = @{
    "Get-DbaCmObject"      = @("DoNotUse")
    "Test-DbaCmConnection" = @("Type")
    "Get-DbaService"       = @("DoNotUse")
}