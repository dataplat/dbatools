#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaServiceErrorMessage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Private service error message command" {
    BeforeAll {
        $script:serviceMessageModule = Get-Module dbatools | Where-Object ModuleType -eq Script
        $script:serviceMessageExpected = @(
            "The request was accepted.",
            "The request is not supported.",
            "The user did not have the necessary access.",
            "The service cannot be stopped because other services that are running are dependent on it.",
            "The requested control code is not valid, or it is unacceptable to the service.",
            "The requested control code cannot be sent to the service because the state of the service (Win32_BaseService.State property) is equal to 0, 1, or 2.",
            "The service has not been started.",
            "The service did not respond to the start request in a timely fashion.",
            "Unknown failure when starting the service.",
            "The directory path to the service executable file was not found.",
            "The service is already running.",
            "The database to add a new service is locked.",
            "A dependency this service relies on has been removed from the system.",
            "The service failed to find the service needed from a dependent service.",
            "The service has been disabled from the system.",
            "The service does not have the correct authentication to run on the system.",
            "This service is being removed from the system.",
            "The service has no execution thread.",
            "The service has circular dependencies when it starts.",
            "A service is running under the same name.",
            "The service name has invalid characters.",
            "Invalid parameters have been passed to the service.",
            "The account under which this service runs is either invalid or lacks the permissions to run the service.",
            "The service exists in the database of services available from the system.",
            "The service is currently paused in the system."
        )
    }

    It "resolves inside the module with the pinned parameter and export contract" {
        $privateCommand = & $script:serviceMessageModule { Get-Command Get-DbaServiceErrorMessage }
        $privateCommand.CommandType | Should -Be Cmdlet
        $privateCommand.ImplementingType.FullName | Should -BeExactly "Dataplat.Dbatools.Commands.GetDbaServiceErrorMessageCommand"
        # The pinned test helper intentionally reimports the psm1 to expose private commands.
        $serviceManifest = Import-PowerShellDataFile (Join-Path $script:serviceMessageModule.ModuleBase "dbatools.psd1")
        $serviceManifest.CmdletsToExport | Should -Not -Contain "Get-DbaServiceErrorMessage"
        $serviceManifest.CmdletsToExport | Should -Not -Contain "*"
        $expectedParameters = @($TestConfig.CommonParameters) + "ErrorNumber"
        Compare-Object $expectedParameters @($privateCommand.Parameters.Keys) | Should -BeNullOrEmpty
        $errorNumberParameter = $privateCommand.Parameters["ErrorNumber"]
        $errorNumberParameter.ParameterType | Should -Be ([int])
        $binding = $errorNumberParameter.Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] }
        $binding.Position | Should -Be 1
        $binding.ValueFromPipeline | Should -BeTrue
    }

    It "returns all pinned messages for omitted, zero and null input" {
        $defaultMessages = @(& $script:serviceMessageModule { Get-DbaServiceErrorMessage })
        $zeroMessages = @(& $script:serviceMessageModule { Get-DbaServiceErrorMessage -ErrorNumber 0 })
        $nullMessages = @(& $script:serviceMessageModule { Get-DbaServiceErrorMessage -ErrorNumber $null })
        $defaultMessages.Count | Should -Be 25
        ($defaultMessages -join "`n") | Should -BeExactly ($script:serviceMessageExpected -join "`n")
        ($zeroMessages -join "`n") | Should -BeExactly ($defaultMessages -join "`n")
        ($nullMessages -join "`n") | Should -BeExactly ($defaultMessages -join "`n")
    }

    It "returns the pinned message for each nonzero code and handles unknown codes" {
        foreach ($serviceErrorCode in 1..24) {
            $selectedMessages = @(& $script:serviceMessageModule { param($value) Get-DbaServiceErrorMessage $value } $serviceErrorCode)
            $selectedMessages.Count | Should -Be 1
            $selectedMessages[0] | Should -BeOfType System.String
            $selectedMessages[0] | Should -BeExactly $script:serviceMessageExpected[$serviceErrorCode]
        }
        foreach ($unknownServiceCode in @(-1, 25, [int]::MinValue, [int]::MaxValue)) {
            & $script:serviceMessageModule { param($value) Get-DbaServiceErrorMessage $value } $unknownServiceCode | Should -BeExactly "Unknown error."
        }
    }

    It "binds numeric strings and preserves last-record end-block output" {
        & $script:serviceMessageModule { Get-DbaServiceErrorMessage -ErrorNumber "2" } | Should -BeExactly $script:serviceMessageExpected[2]
        $lastMessages = @(& $script:serviceMessageModule { 1, 2 | Get-DbaServiceErrorMessage })
        $lastMessages.Count | Should -Be 1
        $lastMessages[0] | Should -BeExactly $script:serviceMessageExpected[2]
        $lastZeroMessages = @(& $script:serviceMessageModule { 2, 0 | Get-DbaServiceErrorMessage })
        $lastZeroMessages.Count | Should -Be 25
        ($lastZeroMessages -join "`n") | Should -BeExactly ($script:serviceMessageExpected -join "`n")
    }
}
