#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Remove-InvalidFileNameChars",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Private filename filtering behavior" {
    BeforeAll {
        $filenameModule = Get-Module dbatools | Where-Object ModuleType -eq Script
    }

    It "preserves mandatory string and pipeline binding" {
        $filenameCommand = & $filenameModule { Get-Command Remove-InvalidFileNameChars }
        $filenameCommand.Parameters["Name"].ParameterType | Should -Be ([string])
        $filenameBinding = $filenameCommand.ParameterSets.Parameters | Where-Object Name -eq Name
        $filenameBinding.Position | Should -Be 0
        $filenameBinding.IsMandatory | Should -BeTrue
        $filenameBinding.ValueFromPipeline | Should -BeTrue
        $filenameBinding.ValueFromPipelineByPropertyName | Should -BeTrue
        $filenameCommand.Parameters.ContainsKey("EnableException") | Should -BeFalse
        Compare-Object (@($TestConfig.CommonParameters) + "Name") @($filenameCommand.Parameters.Keys) | Should -BeNullOrEmpty
    }

    It "removes invalid characters and retains valid text including an empty result" {
        $filenameInvalid = [string]::Join("", [IO.Path]::GetInvalidFileNameChars())
        $filenameValid = "Report [Q1] - " + [char]0x00e9 + " " + [char]0x6f22 + ".sql"
        $filenameMixed = $filenameInvalid + $filenameValid + $filenameInvalid
        $filenameRows = @(& $filenameModule { param($value) Remove-InvalidFileNameChars -Name $value } $filenameMixed)
        $filenameRows.Count | Should -Be 1
        $filenameRows[0] | Should -BeOfType System.String
        $filenameRows[0] | Should -BeExactly $filenameValid
        $filenameEmptyRows = @(& $filenameModule { param($value) Remove-InvalidFileNameChars -Name $value } $filenameInvalid)
        $filenameEmptyRows.Count | Should -Be 1
        $filenameEmptyRows[0] | Should -BeOfType System.String
        $filenameEmptyRows[0] | Should -BeExactly ""
    }

    It "emits only the last value from a string pipeline" {
        $filenamePipeline = @(& $filenameModule { @("first?.txt", "last*.sql") | Remove-InvalidFileNameChars })
        $filenamePipeline.Count | Should -Be 1
        $filenamePipeline[0] | Should -BeExactly "last.sql"
    }

    It "binds Name properties and emits only the last pipeline value" {
        $filenameProperties = @(& $filenameModule {
            @([pscustomobject]@{ Name = "first?.txt" }, [pscustomobject]@{ Name = "last*.sql" }) | Remove-InvalidFileNameChars
        })
        $filenameProperties.Count | Should -Be 1
        $filenameProperties[0] | Should -BeExactly "last.sql"
    }

    It "rejects null and empty mandatory input" {
        { & $filenameModule { Remove-InvalidFileNameChars -Name $null } } | Should -Throw
        { & $filenameModule { Remove-InvalidFileNameChars -Name "" } } | Should -Throw
    }
}
