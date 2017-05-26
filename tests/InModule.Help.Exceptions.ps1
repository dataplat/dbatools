$global:FunctionHelpTestExceptions = @(
    "TabExpansion2"
)

$global:HelpTestEnumeratedArrays = @(
	"SqlCollective.Dbatools.Connection.ManagementConnectionType[]"
)

$global:HelpTestSkipParameterType = @{
	"Get-DbaCmObject" = @("DoNotUse")
	"Test-DbaCmConnection" = @("Type")
}