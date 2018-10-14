$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        <#
            The $paramCount is adjusted based on the parameters your command will have.

            The $defaultParamCount is adjusted based on what type of command you are writing the test for:
                - Commands that *do not* include SupportShouldProcess, set defaultParamCount    = 11
                - Commands that *do* include SupportShouldProcess, set defaultParamCount        = 13
        #>
        $paramCount = 6
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Test-DbaDbCompatibility).Parameters.Keys
        $knownParameters = 'SqlInstance','Credential','Database','ExcludeDatabase','Detailed','EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}
<#
    Integration test are custom to the command you are writing it for,
        but something similar to below should be included if applicable.

    The below examples are by no means set in stone and there are already
        a number of test that you can pull examples from in how they are done.
#>

# # Add-DbaNoun
# Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
#     Context "XYZ is added properly" {
#         $results = Add-DbaXyz <# your specific parameters and values #> -Confirm:$false

#         It "Should show the proper LMN has been added" {
#             $results.Property1 | Should Be "daper dan"
#         }

#         It "Should be in SomeSpecificLocation" {
#             $results.PSParentPath | Should Be "51??16'25.7 N + 30??13'37.7 E"
#         }
#     }
# }

# # New-DbaNoun
# Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
#     Context "Can generate/create a new XYZ" {
#         BeforeAll {
#             $results = New-DbaXyz <# your specific parameters #> -Silent
#         }
#         AfterAll {
#             Remove-DbaXyz <# your specific parameters #> -Confirm:$false
#         }
#         It "Returns the right UGY" {
#             "$($results.Property1)" -match 'SqlServer' | Should Be $true
#         }
#     }
# }

# # Get-DbaNoun
# Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
#     Context "Command actually works" {
#         $results = Get-DbaXyz -ComputerName $script:instance1, $script:instance2
#         It "Should have correct properties" {
#             $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Property1,Property2,Property3'.Split(',')
#             ($results.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
#         }

#         It "Shows only one type of value" {
#             foreach ($result in $results) {
#                 $result.Property1 | Should BeLike "*FilterValue*"
#             }
#         }
#     }
# }

# # Invoke-DbaNoun
# Describe "$CommandName Integration Test" -Tag "IntegrationTests" {
#     $results = Invoke-DbaXyz -SqlInstance $script:instance1 -Type SpecialValue
#     Context "Validate output" {
#         It "Should have correct properties" {
#             $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,LogType,IsSuccessful,Notes'.Split(',')
#             ($results.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
#         }
#         It "Should cycle instance error log" {
#             $results.LogType | Should Be "instance"
#         }
#     }
# }
