#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-ErrorMessage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Private error message behavior" {
    BeforeAll {
        $errorMessageModule = Get-Module dbatools | Where-Object ModuleType -eq Script
        function New-ErrorMessageTestRecord {
            param([string[]]$Messages)
            $messageException = $null
            for ($messageIndex = $Messages.Count - 1; $messageIndex -ge 0; $messageIndex--) {
                if ($null -eq $messageException) {
                    $messageException = New-Object System.Exception -ArgumentList $Messages[$messageIndex]
                } else {
                    $messageException = New-Object System.Exception -ArgumentList $Messages[$messageIndex], $messageException
                }
            }
            New-Object System.Management.Automation.ErrorRecord -ArgumentList $messageException, "NativeMessageTest", ([System.Management.Automation.ErrorCategory]::NotSpecified), "native-test"
        }
    }

    It "preserves the private ErrorRecord binding surface" {
        $errorMessageCommand = & $errorMessageModule { Get-Command Get-ErrorMessage }
        $errorMessageCommand.Parameters["Record"].ParameterType | Should -Be ([System.Management.Automation.ErrorRecord])
        $errorMessageBinding = $errorMessageCommand.ParameterSets.Parameters | Where-Object Name -eq Record
        $errorMessageBinding.IsMandatory | Should -BeTrue
        $errorMessageBinding.ValueFromPipeline | Should -BeTrue
        $errorMessageCommand.Parameters.ContainsKey("EnableException") | Should -BeFalse
        Compare-Object (@($TestConfig.CommonParameters) + "Record") @($errorMessageCommand.Parameters.Keys) | Should -BeNullOrEmpty
    }

    It "returns strings at the five-link limit and ignores a deeper message" {
        $messageAtLimit = New-ErrorMessageTestRecord @("root", "one", "two", "three", "four", "five")
        $messageBeyondLimit = New-ErrorMessageTestRecord @("root", "one", "two", "three", "four", "five", "too deep")
        foreach ($messageDepthRecord in @($messageAtLimit, $messageBeyondLimit)) {
            $messageDepthRows = @(& $errorMessageModule { param($value) Get-ErrorMessage -Record $value } $messageDepthRecord)
            $messageDepthRows.Count | Should -Be 1
            $messageDepthRows[0] | Should -BeOfType System.String
            $messageDepthRows[0] | Should -BeExactly "five"
        }
    }

    It "falls back over empty inner messages and preserves empty or truthy string output" {
        $messageFallback = New-ErrorMessageTestRecord @("outer", "", "")
        & $errorMessageModule { param($value) Get-ErrorMessage -Record $value } $messageFallback | Should -BeExactly "outer"
        $messageEmpty = New-ErrorMessageTestRecord @("", "")
        $messageEmptyRows = @(& $errorMessageModule { param($value) Get-ErrorMessage -Record $value } $messageEmpty)
        $messageEmptyRows.Count | Should -Be 1
        $messageEmptyRows[0] | Should -BeOfType System.String
        $messageEmptyRows[0] | Should -BeExactly ""
        foreach ($messageTruthy in @(" ", "0")) {
            $messageTruthyRecord = New-ErrorMessageTestRecord @("outer", $messageTruthy)
            & $errorMessageModule { param($value) Get-ErrorMessage -Record $value } $messageTruthyRecord | Should -BeExactly $messageTruthy
        }
    }

    It "processes every pipeline ErrorRecord in order" {
        $messageFirst = New-ErrorMessageTestRecord @("first wrapper", "first")
        $messageSecond = New-ErrorMessageTestRecord @("second")
        $messagePipelineRows = @(& $errorMessageModule {
            param($firstRecord, $secondRecord)
            @($firstRecord, $secondRecord) | Get-ErrorMessage
        } $messageFirst $messageSecond)
        $messagePipelineRows.Count | Should -Be 2
        $messagePipelineRows[0] | Should -BeExactly "first"
        $messagePipelineRows[1] | Should -BeExactly "second"
    }

    It "rejects an explicit null mandatory record" {
        { & $errorMessageModule { Get-ErrorMessage -Record $null } } | Should -Throw
    }
}
