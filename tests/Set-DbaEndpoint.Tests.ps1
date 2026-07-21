#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaEndpoint",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Endpoint",
                "Owner",
                "Type",
                "AllEndpoints",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: actually altering an endpoint (owner/type) needs a real endpoint to modify
    # and asserts against live SMO state, so the endpoint-resolution/Alter leg is DEFERRED-TO-GATE.
    # What IS characterizable on a standalone instance is the guard the source runs before any
    # resolution, plus a genuinely silent no-input path: resolution rides
    # foreach ($instance in $SqlInstance) { Get-DbaEndpoint ... }, so an unbound SqlInstance
    # iterates zero times and never reaches Get-DbaEndpoint (probe-verified). Both calls pass
    # WhatIf as belt-and-braces on this Alter command.
    BeforeAll {
        $random = Get-Random
    }

    Context "Guarding before the change" {
        It "Stays fully silent when neither SqlInstance nor InputObject is supplied" {
            $splatNoInput = @{
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Set-DbaEndpoint @splatNoInput)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 0
        }

        It "Warns once and returns nothing when SqlInstance is supplied without Endpoint or AllEndpoints" {
            $splatNoEndpoint = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(Set-DbaEndpoint @splatNoEndpoint)
            $result.Count | Should -Be 0
            $warn.Count | Should -Be 1

            # strip the bracketed [timestamp]/[function] prefix added by Write-Message from the warning
            $payload = $warn[0].Message -replace "^(\[[^\]]*\]\s*)+", ""
            $payload | Should -Be "You must specify AllEndpoints or Endpoint when using the SqlInstance parameter."
        }
    }

    # The Alter leg. Only Owner is characterized here: the source assigns EndpointType from -Type
    # before Alter(), but SMO does not permit changing the type of an existing endpoint, so a -Type
    # characterization would assert on a server-side failure rather than on this command's contract.
    # A ServiceBroker endpoint on a free high port is used so the instance's DatabaseMirroring
    # endpoint (one per instance, often already present) is left alone.
    Context "Altering an endpoint" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $endpointName = "dbatoolsci_setep_$random"
            $ownerLogin = "dbatoolsci_epowner_$random"
            $endpointPort = Get-Random -Minimum 55000 -Maximum 58999

            $splatOwnerLogin = @{
                SqlInstance    = $TestConfig.InstanceSingle
                Login          = $ownerLogin
                SecurePassword = (ConvertTo-SecureString -String "dbatools.IO$random" -AsPlainText -Force)
            }
            $null = New-DbaLogin @splatOwnerLogin

            $splatNewEndpoint = @{
                SqlInstance = $TestConfig.InstanceSingle
                Name        = $endpointName
                Type        = "ServiceBroker"
                Protocol    = "Tcp"
                Port        = $endpointPort
            }
            $null = New-DbaEndpoint @splatNewEndpoint

            $originalOwner = (Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint $endpointName).Owner

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Remove-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint $endpointName
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $ownerLogin

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Does not change the owner under -WhatIf" {
            $splatWhatIf = @{
                SqlInstance = $TestConfig.InstanceSingle
                Endpoint    = $endpointName
                Owner       = $ownerLogin
                WhatIf      = $true
            }
            $result = @(Set-DbaEndpoint @splatWhatIf)

            $result.Count | Should -Be 0
            (Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint $endpointName).Owner | Should -Be $originalOwner
        }

        It "Sets the owner and emits the altered endpoint" {
            $splatSetOwner = @{
                SqlInstance = $TestConfig.InstanceSingle
                Endpoint    = $endpointName
                Owner       = $ownerLogin
            }
            $result = @(Set-DbaEndpoint @splatSetOwner)

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be $endpointName
            $result[0].Owner | Should -Be $ownerLogin
        }

        It "Persists the new owner on the server" {
            (Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint $endpointName).Owner | Should -Be $ownerLogin
        }

        It "Accepts an endpoint on the pipeline and returns it" {
            $result = @(Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint $endpointName | Set-DbaEndpoint -Owner $originalOwner)

            $result.Count | Should -Be 1
            $result[0].Owner | Should -Be $originalOwner
            (Get-DbaEndpoint -SqlInstance $TestConfig.InstanceSingle -Endpoint $endpointName).Owner | Should -Be $originalOwner
        }
    }
}